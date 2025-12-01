import type { Core, NodeSingular, Position, BoundingBox12, EventObject } from 'cytoscape'

export interface CompoundDragDropOptions {
  grabbedNode: (node: NodeSingular) => boolean
  dropTarget: (node: NodeSingular) => boolean
  dropSibling: () => boolean
  outThreshold: number
  onToast?: (message: string, severity?: 'info' | 'warn' | 'error' | 'success') => void
  shouldDetach?: () => boolean
}

interface DragState {
  isDragging: boolean
  draggedNode: NodeSingular | null
  originalParent: NodeSingular | null
  originalParentBounds: BoundingBox12 | null
  originalPosition: Position | null
  potentialDropTarget: NodeSingular | null
  platePositions: Map<string, Position>
  detachedOnGrab: boolean
  ghostNode: NodeSingular | null
  toastShown: boolean
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UndoRedoInstance = any

export function useCompoundDragDrop(
  cy: Core,
  options: CompoundDragDropOptions,
  ur?: UndoRedoInstance
) {
  const dragState: DragState = {
    isDragging: false,
    draggedNode: null,
    originalParent: null,
    originalParentBounds: null,
    originalPosition: null,
    potentialDropTarget: null,
    platePositions: new Map<string, Position>(),
    detachedOnGrab: false,
    ghostNode: null,
    toastShown: false,
  }

  /**
   * Checks if a node can be dropped into a potential target parent.
   */
  const canDropInto = (draggedNode: NodeSingular, targetNode: NodeSingular): boolean => {
    if (draggedNode.id() === targetNode.id()) return false

    let current = targetNode.parent()
    while (current.length > 0) {
      const currentNode = current[0]
      if (currentNode && currentNode.id() === draggedNode.id()) return false
      current = currentNode ? currentNode.parent() : cy.collection()
    }

    return options.dropTarget(targetNode)
  }

  /**
   * Finds the deepest valid drop target at a given position.
   */
  const findDropTargetAtPosition = (
    position: Position,
    draggedNode: NodeSingular
  ): NodeSingular | null => {
    const nodesAtPosition = cy.nodes().filter((node) => {
      if (node.id() === draggedNode.id()) return false
      const bb = node.boundingBox()
      return (
        position.x >= bb.x1 && position.x <= bb.x2 && position.y >= bb.y1 && position.y <= bb.y2
      )
    })

    const sortedNodes = nodesAtPosition.sort(
      (a, b) => getNodeDepth(b as NodeSingular) - getNodeDepth(a as NodeSingular)
    )

    for (const element of sortedNodes) {
      if (canDropInto(draggedNode, element as NodeSingular)) {
        return element as NodeSingular
      }
    }

    return null
  }

  const getNodeDepth = (node: NodeSingular): number => {
    let depth = 0
    let current = node.parent()
    while (current.length > 0) {
      depth++
      current = current[0].parent()
    }
    return depth
  }

  /**
   * Determines if a node has been dragged out of its parent's original bounds.
   * Returns true if the node is no longer fully contained within the original parent box.
   */
  const isOutsideOriginalParent = (node: NodeSingular): boolean => {
    if (!dragState.originalParentBounds) return false

    const nodeBounds = node.boundingBox({ includeOverlays: false, includeLabels: true })
    const parentBounds = dragState.originalParentBounds

    // Use a small buffer to tolerate slight border overlaps/jitter
    const buffer = 5

    const isContained =
      nodeBounds.x1 >= parentBounds.x1 - buffer &&
      nodeBounds.x2 <= parentBounds.x2 + buffer &&
      nodeBounds.y1 >= parentBounds.y1 - buffer &&
      nodeBounds.y2 <= parentBounds.y2 + buffer

    return !isContained
  }

  /**
   * Logic to transition a node into 'detached' mode (floating).
   * Creates a ghost node to hold parent shape and moves node to root.
   */
  const enterDetachMode = (node: NodeSingular) => {
    if (!dragState.originalParent || dragState.detachedOnGrab) return

    const ghostId = `ghost_${node.id()}_${Date.now()}`

    // Create node first without style object to avoid "bypass at creation" warning
    dragState.ghostNode = cy.add({
      group: 'nodes',
      data: {
        id: ghostId,
        parent: dragState.originalParent.id(),
        nodeType: 'constant',
        name: ' ', // Dummy name for label mapper
      },
      position: { ...(dragState.originalPosition || node.position()) },
      grabbable: false,
      selectable: false,
    })

    // Apply styles post-creation
    dragState.ghostNode.style({
      'background-opacity': 0,
      'border-opacity': 0,
      width: node.width(),
      height: node.height(),
      label: '',
      events: 'no',
    })

    // Detach Node
    dragState.detachedOnGrab = true

    // The ghost node is a transient visual element used only during the drag interaction
    // and is explicitly cleaned up in `endDrag`. It is intentionally excluded from the
    // undo history to prevent restoring temporary UI artifacts.
    if (ur) {
      ur.do('move', { eles: node, location: { parent: null } })
    } else {
      node.move({ parent: null })
    }
  }

  const startDrag = (event: EventObject) => {
    const node = event.target as NodeSingular
    if (!options.grabbedNode(node) || dragState.isDragging) return

    // Cleanup any orphaned ghost node from a previous cancelled interaction
    if (dragState.ghostNode) {
      cy.remove(dragState.ghostNode)
      dragState.ghostNode = null
    }

    dragState.isDragging = true
    dragState.draggedNode = node
    dragState.originalPosition = { ...node.position() }
    dragState.platePositions.clear()
    dragState.toastShown = false

    const currentParent = node.parent()
    const hasParent = currentParent.length > 0

    if (hasParent) {
      dragState.originalParent = currentParent[0]
      dragState.originalParentBounds = currentParent[0].boundingBox({
        includeOverlays: false,
        includeLabels: true,
      })
    } else {
      dragState.originalParent = null
      dragState.originalParentBounds = null
    }

    // Check for Alt key OR the detach mode toggle (for touch devices)
    const isAltPressed = event.originalEvent?.altKey || options.shouldDetach?.()

    if (isAltPressed && hasParent && dragState.originalParent) {
      enterDetachMode(node)
    } else {
      dragState.detachedOnGrab = false

      if (node.data('nodeType') !== 'plate') {
        cy.nodes('[nodeType="plate"]').forEach((plate) => {
          dragState.platePositions.set(plate.id(), { ...plate.position() })
        })
      }
    }

    node.addClass('cdnd-grabbed-node')
    cy.trigger('compound-drag-start', [{ node }])
  }

  const updateDrag = (node: NodeSingular, position: Position, event: EventObject) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return

    // Dynamic Detach Mode: Trigger if Alt is pressed mid-drag OR detach mode is toggled
    const isAltPressed = event.originalEvent?.altKey || options.shouldDetach?.()

    if (isAltPressed && !dragState.detachedOnGrab && dragState.originalParent) {
      enterDetachMode(node)
    }

    const newDropTarget = findDropTargetAtPosition(position, node)

    if (
      dragState.potentialDropTarget &&
      dragState.potentialDropTarget.id() !== newDropTarget?.id()
    ) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target')
    }

    if (dragState.detachedOnGrab) {
      // Node is floating/detached
      if (newDropTarget) {
        dragState.potentialDropTarget = newDropTarget
        newDropTarget.addClass('cdnd-drop-target')
      } else {
        dragState.potentialDropTarget = null
      }
    } else {
      // Node is still attached as a child
      const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null

      if (currentParentNode && isOutsideOriginalParent(node)) {
        if (!dragState.toastShown && options.onToast) {
          options.onToast('Hold Alt/Option (⌥) key or enable Detach Mode  in View Options from left sidebar to remove node', 'warn')
          dragState.toastShown = true // Debounce
        }
      }

      // Check for nested drop targets
      if (newDropTarget && newDropTarget.id() !== currentParentNode?.id()) {
        dragState.potentialDropTarget = newDropTarget
        newDropTarget.addClass('cdnd-drop-target')
      } else {
        dragState.potentialDropTarget = null
      }
    }
  }

  const endDrag = (node: NodeSingular) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return

    node.removeClass('cdnd-grabbed-node')
    if (dragState.potentialDropTarget) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target')
    }

    // Removing the ghost node triggers the plate to resize to its natural state
    if (dragState.ghostNode) {
      cy.remove(dragState.ghostNode)
      dragState.ghostNode = null
    }

    const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null
    const newParent = dragState.potentialDropTarget
    let dropPerformed = false

    if (dragState.detachedOnGrab) {
      if (newParent) {
        if (ur) {
          ur.do('move', { eles: node, location: { parent: newParent.id() } })
        } else {
          node.move({ parent: newParent.id() })
        }
        cy.trigger('compound-drop', [{ node, newParent, oldParent: dragState.originalParent }])
      }
      dropPerformed = true
    } else {
      if (newParent && newParent.id() !== currentParentNode?.id()) {
        if (ur) {
          ur.do('move', { eles: node, location: { parent: newParent.id() } })
        } else {
          node.move({ parent: newParent.id() })
        }
        cy.trigger('compound-drop', [{ node, newParent, oldParent: currentParentNode }])
        dropPerformed = true
      }
    }

    // Reset State
    Object.assign(dragState, {
      isDragging: false,
      draggedNode: null,
      originalParent: null,
      originalParentBounds: null,
      originalPosition: null,
      potentialDropTarget: null,
      detachedOnGrab: false,
      ghostNode: null,
      toastShown: false,
    })
    dragState.platePositions.clear()

    cy.trigger('compound-drag-end', [{ node, dropPerformed }])
  }

  // Bind Listeners
  cy.on('grab', 'node', (event: EventObject) => startDrag(event))

  cy.on('drag', 'node', (event: EventObject) => {
    const node = event.target as NodeSingular
    if (dragState.isDragging && dragState.draggedNode?.id() === node.id()) {
      // Pass the full event object to access modifier keys (altKey)
      updateDrag(node, node.position(), event)
    }
  })

  cy.on('free', 'node', (event: EventObject) => endDrag(event.target as NodeSingular))

  const destroy = () => {
    cy.off('grab', 'node')
    cy.off('drag', 'node')
    cy.off('free', 'node')
  }

  return {
    destroy,
    getDragState: () => ({ ...dragState }),
  }
}
