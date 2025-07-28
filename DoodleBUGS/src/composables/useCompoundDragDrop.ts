import type { Core, NodeSingular, Position, BoundingBox12 } from 'cytoscape';

export interface CompoundDragDropOptions {
  grabbedNode: (node: NodeSingular) => boolean;
  dropTarget: (node: NodeSingular) => boolean;
  dropSibling: () => boolean;
  outThreshold: number;
}

interface DragState {
  isDragging: boolean;
  draggedNode: NodeSingular | null;
  originalParent: NodeSingular | null;
  originalParentBounds: BoundingBox12 | null;
  originalPosition: Position | null;
  potentialDropTarget: NodeSingular | null;
  platePositions: Map<string, Position>;
}

export function useCompoundDragDrop(cy: Core, options: CompoundDragDropOptions) {
  const dragState: DragState = {
    isDragging: false,
    draggedNode: null,
    originalParent: null,
    originalParentBounds: null,
    originalPosition: null,
    potentialDropTarget: null,
    platePositions: new Map<string, Position>(),
  };

  /**
   * Checks if a node can be dropped into a potential target parent.
   * Prevents dropping a node into itself or one of its descendants.
   */
  const canDropInto = (draggedNode: NodeSingular, targetNode: NodeSingular): boolean => {
    if (draggedNode.id() === targetNode.id()) return false;
    
    let current = targetNode.parent();
    while (current.length > 0) {
      const currentNode = current[0];
      if (currentNode && currentNode.id() === draggedNode.id()) return false;
      current = currentNode ? currentNode.parent() : cy.collection();
    }
    
    return options.dropTarget(targetNode);
  };

  /**
   * Finds the deepest valid drop target at a given position.
   */
  const findDropTargetAtPosition = (position: Position, draggedNode: NodeSingular): NodeSingular | null => {
    const nodesAtPosition = cy.nodes().filter((node) => {
      if (node.id() === draggedNode.id()) return false;
      const bb = node.boundingBox();
      return position.x >= bb.x1 && position.x <= bb.x2 && 
             position.y >= bb.y1 && position.y <= bb.y2;
    });
    
    const sortedNodes = nodesAtPosition.sort((a, b) => getNodeDepth(b as NodeSingular) - getNodeDepth(a as NodeSingular));
    
    for (const element of sortedNodes) {
      if (canDropInto(draggedNode, element as NodeSingular)) {
        return element as NodeSingular;
      }
    }
    
    return null;
  };

  const getNodeDepth = (node: NodeSingular): number => {
    let depth = 0;
    let current = node.parent();
    while (current.length > 0) {
      depth++;
      current = current[0].parent();
    }
    return depth;
  };

  const expandBounds = (bb: BoundingBox12, padding: number): BoundingBox12 => {
    return {
      x1: bb.x1 - padding, x2: bb.x2 + padding,
      y1: bb.y1 - padding, y2: bb.y2 + padding,
    };
  };

  const boundsOverlap = (bb1: BoundingBox12, bb2: BoundingBox12): boolean => {
    return !(bb1.x1 > bb2.x2 || bb2.x1 > bb1.x2 || bb1.y1 > bb2.y2 || bb2.y1 > bb1.y2);
  };

  /**
   * Determines if a node has been dragged sufficiently far out of its parent's bounding box.
   */
  const shouldRemoveFromParent = (node: NodeSingular): boolean => {
    if (!dragState.originalParentBounds) return false;
    
    const nodeBounds = node.boundingBox({ includeOverlays: false, includeLabels: true });
    const expandedNodeBounds = expandBounds(nodeBounds, options.outThreshold);
    
    return !boundsOverlap(dragState.originalParentBounds, expandedNodeBounds);
  };

  const startDrag = (node: NodeSingular) => {
    if (!options.grabbedNode(node) || dragState.isDragging) return;
    
    if (node.data('nodeType') !== 'plate') {
      dragState.platePositions.clear();
      cy.nodes('[nodeType="plate"]').forEach(plate => {
        dragState.platePositions.set(plate.id(), { ...plate.position() });
      });
    }
    
    dragState.draggedNode = node;
    dragState.originalPosition = { ...node.position() };
    dragState.isDragging = true;
    
    const currentParent = node.parent();
    if (currentParent.length > 0) {
      dragState.originalParent = currentParent[0];
      dragState.originalParentBounds = currentParent[0].boundingBox({ includeOverlays: false, includeLabels: true });
    }
    
    node.addClass('cdnd-grabbed-node');
    cy.trigger('compound-drag-start', [{ node }]);
  };

  const updateDrag = (node: NodeSingular, position: Position) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return;

    const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null;
    const newDropTarget = findDropTargetAtPosition(position, node);
    
    if (dragState.potentialDropTarget) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target');
      dragState.potentialDropTarget = null;
    }
    
    if (currentParentNode && shouldRemoveFromParent(node)) {
      node.addClass('cdnd-drag-out');
    } else {
      node.removeClass('cdnd-drag-out');
      if (newDropTarget && newDropTarget.id() !== currentParentNode?.id()) {
        dragState.potentialDropTarget = newDropTarget;
        newDropTarget.addClass('cdnd-drop-target');
      }
    }
  };

  const endDrag = (node: NodeSingular) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return;

    node.removeClass('cdnd-grabbed-node cdnd-drag-out');
    if (dragState.potentialDropTarget) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target');
    }

    const currentParentNode = node.parent().length > 0 ? node.parent()[0] : null;
    const newParent = dragState.potentialDropTarget;
    let dropPerformed = false;

    if (newParent && newParent.id() !== currentParentNode?.id()) {
      node.move({ parent: newParent.id() });
      cy.trigger('compound-drop', [ { node, newParent, oldParent: currentParentNode } ]);
      dropPerformed = true;
    } else if (currentParentNode && !newParent && shouldRemoveFromParent(node)) {
      node.move({ parent: null });
      cy.trigger('compound-drop', [ { node, newParent: null, oldParent: currentParentNode } ]);
      dropPerformed = true;
    }

    const isDraggingPlate = dragState.draggedNode?.data('nodeType') === 'plate';
    const isNodeRemovedFromPlate = dropPerformed && !newParent && currentParentNode;
    
    if (!isDraggingPlate && isNodeRemovedFromPlate && dragState.platePositions.size > 0) {
      dragState.platePositions.forEach((position, plateId) => {
        cy.getElementById(plateId).position(position);
      });
    }

    Object.assign(dragState, {
      isDragging: false,
      draggedNode: null,
      originalParent: null,
      originalParentBounds: null,
      originalPosition: null,
      potentialDropTarget: null,
    });
    dragState.platePositions.clear();

    cy.trigger('compound-drag-end', [{ node, dropPerformed }]);
  };

  cy.on('grab', 'node', (event: cytoscape.EventObject) => startDrag(event.target as NodeSingular));
  cy.on('drag', 'node', (event: cytoscape.EventObject) => {
    const node = event.target as NodeSingular;
    if (dragState.isDragging && dragState.draggedNode?.id() === node.id()) {
      updateDrag(node, node.position());
    }
  });
  cy.on('free', 'node', (event: cytoscape.EventObject) => endDrag(event.target as NodeSingular));

  const destroy = () => {
    cy.off('grab', 'node');
    cy.off('drag', 'node');
    cy.off('free', 'node');
  };

  return {
    destroy,
    getDragState: () => ({ ...dragState })
  };
}
