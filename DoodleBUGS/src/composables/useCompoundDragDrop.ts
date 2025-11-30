import type { Core, NodeSingular, Position, BoundingBox12, EventObject } from 'cytoscape'

export interface CompoundDragDropOptions {
  grabbedNode: (node: NodeSingular) => boolean
  dropTarget: (node: NodeSingular) => boolean
  dropSibling: () => boolean
  outThreshold: number
  onToast?: (message: string, severity?: 'info' | 'warn' | 'error' | 'success') => void
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
    toastShown: false,
  }

  /**
   * Checks if a node can be dropped into a potential target parent.
   * Prevents dropping a node into itself or one of its descendants.
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

  const expandBounds = (bb: BoundingBox12, padding: number): BoundingBox12 => {
    return {
      x1: bb.x1 - padding,
      x2: bb.x2 + padding,
      y1: bb.y1 - padding,
      y2: bb.y2 + padding,
    }
  }

  const boundsOverlap = (bb1: BoundingBox12, bb2: BoundingBox12): boolean => {
    return !(bb1.x1 > bb2.x2 || bb2.x1 > bb1.x2 || bb1.y1 > bb2.y2 || bb2.y1 > bb1.y2)
  }

  /**
   * Determines if a node has been dragged sufficiently far out of its parent's bounding box.
   */
  const shouldRemoveFromParent = (node: NodeSingular): boolean => {
    if (!dragState.originalParentBounds) return false

    const nodeBounds = node.boundingBox({ includeOverlays: false, includeLabels: true })
    const expandedNodeBounds = expandBounds(nodeBounds, options.outThreshold)

    return !boundsOverlap(dragState.originalParentBounds, expandedNodeBounds)
  }

  const startDrag = (event: EventObject) => {
    const node = event.target as NodeSingular
    if (!options.grabbedNode(node) || dragState.isDragging) return

    // Initialize State
    dragState.isDragging = true
    dragState.draggedNode = node
    dragState.originalPosition = { ...node.position() }
    dragState.platePositions.clear()
    dragState.toastShown = false

    const currentParent = node.parent()
    if (currentParent.length > 0) {
      dragState.originalParent = currentParent[0]
      dragState.originalParentBounds = currentParent[0].boundingBox({
        includeOverlays: false,
        includeLabels: true,
      })
    } else {
      dragState.originalParent = null
      dragState.originalParentBounds = null
    }

    // --- ALT KEY LOGIC (Detach on Click) ---
    // Check for Alt/Option key. If pressed and node is in a plate, detach immediately.
    // This prevents the "plate stretching" behavior.
    const isAltPressed = event.originalEvent?.altKey
    const hasParent = currentParent.length > 0

    if (isAltPressed && hasParent) {
      dragState.detachedOnGrab = true
      if (ur) {
        ur.do('move', { eles: node, location: { parent: null } })
      } else {
        node.move({ parent: null })
      }
    } else {
      dragState.detachedOnGrab = false
      // Cache other plate positions to potentially restore them if needed (legacy logic),
      // though snapping back prevents most destruction.
      if (node.data('nodeType') !== 'plate') {
        cy.nodes('[nodeType="plate"]').forEach((plate) => {
          dragState.platePositions.set(plate.id(), { ...plate.position() })
        })
      }
    }

    node.addClass('cdnd-grabbed-node')
    cy.trigger('compound-drag-start', [{ node }])
  }

  const updateDrag = (node: NodeSingular, position: Position) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return

    const newDropTarget = findDropTargetAtPosition(position, node)

    // Clear previous drop target highlights
    if (dragState.potentialDropTarget && dragState.potentialDropTarget.id() !== newDropTarget?.id()) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target')
    }

    // Logic Branch: Detached vs Bound
    if (dragState.detachedOnGrab) {
      // If detached, we are just looking for a new home (or the old one)
      if (newDropTarget) {
        dragState.potentialDropTarget = newDropTarget
        newDropTarget.addClass('cdnd-drop-target')
      } else {
        dragState.potentialDropTarget = null
      }
    } else {
      // Bound to parent (Alt NOT pressed)
      const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null

      if (currentParentNode && shouldRemoveFromParent(node)) {
        // Node is being dragged OUT, but Alt is NOT pressed.
        // Warn the user and do NOT show drag-out styles (since action is forbidden)
        if (!dragState.toastShown && options.onToast) {
          options.onToast('Hold Alt/Option (⌥) key to remove node from plate', 'warn')
          dragState.toastShown = true // Debounce toast per drag
        }
      } else {
        // Node is inside or near parent, or moving between nested parents safely?
        // Actually, if we aren't detached, normal compound behavior applies.
        if (newDropTarget && newDropTarget.id() !== currentParentNode?.id()) {
          dragState.potentialDropTarget = newDropTarget
          newDropTarget.addClass('cdnd-drop-target')
        } else {
          dragState.potentialDropTarget = null
        }
      }
    }
  }

  const endDrag = (node: NodeSingular) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return

    node.removeClass('cdnd-grabbed-node cdnd-drag-out')
    if (dragState.potentialDropTarget) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target')
    }

    const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null
    const newParent = dragState.potentialDropTarget
    let dropPerformed = false

    // Logic Branch: Detached vs Bound
    if (dragState.detachedOnGrab) {
      // Node was already removed on grab.
      // If dropped on a valid target, put it in.
      // If dropped on nothing, it stays removed (which is the desired "Alt" behavior).
      if (newParent) {
        if (ur) {
          ur.do('move', { eles: node, location: { parent: newParent.id() } })
        } else {
          node.move({ parent: newParent.id() })
        }
        cy.trigger('compound-drop', [{ node, newParent, oldParent: dragState.originalParent }])
        dropPerformed = true
      } else {
        // Stays removed. No action needed as it was moved in startDrag.
        // We might want to emit an event or update state if needed.
        dropPerformed = true // It was technically a change from original state
      }
    } else {
      // Alt was NOT pressed.
      // We enforce "Do not remove".

      // 1. Moving to a new parent (nested drop)?
      if (newParent && newParent.id() !== currentParentNode?.id()) {
        if (ur) {
          ur.do('move', { eles: node, location: { parent: newParent.id() } })
        } else {
          node.move({ parent: newParent.id() })
        }
        cy.trigger('compound-drop', [{ node, newParent, oldParent: currentParentNode }])
        dropPerformed = true
      }
      // 2. Trying to leave parent?
      else if (currentParentNode && !newParent && shouldRemoveFromParent(node)) {
        // User tried to drag out without Alt.
        // REJECT THE MOVE to prevent plate expansion ("hurting plate").
        if (dragState.originalPosition) {
          node.position(dragState.originalPosition)
        }
        
        // Show toast if not already shown during drag
        if (options.onToast && !dragState.toastShown) {
          options.onToast('Hold Alt/Option (⌥) key to remove node from plate', 'warn')
        }
      }
      // 3. Just moving around inside? Cytoscape handles this naturally.
    }

    Object.assign(dragState, {
      isDragging: false,
      draggedNode: null,
      originalParent: null,
      originalParentBounds: null,
      originalPosition: null,
      potentialDropTarget: null,
      detachedOnGrab: false,
      toastShown: false,
    })
    dragState.platePositions.clear()

    cy.trigger('compound-drag-end', [{ node, dropPerformed }])
  }

  // Bind Listeners
  // Note: We bind 'grab' to startDrag to catch the Alt key state at the moment of click
  cy.on('grab', 'node', (event: EventObject) => startDrag(event))
  
  cy.on('drag', 'node', (event: EventObject) => {
    const node = event.target as NodeSingular
    if (dragState.isDragging && dragState.draggedNode?.id() === node.id()) {
      updateDrag(node, node.position())
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
