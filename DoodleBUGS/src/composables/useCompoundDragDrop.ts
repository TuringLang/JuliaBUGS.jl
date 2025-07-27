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
}

export function useCompoundDragDrop(cy: Core, options: CompoundDragDropOptions) {
  const dragState: DragState = {
    isDragging: false,
    draggedNode: null,
    originalParent: null,
    originalParentBounds: null,
    originalPosition: null,
    potentialDropTarget: null,
  };

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

  const findDropTargetAtPosition = (position: Position, draggedNode: NodeSingular): NodeSingular | null => {
    const allNodes = cy.nodes().filter(node => node.id() !== draggedNode.id());
    const nodesAtPosition = allNodes.filter((node) => {
      const bb = node.boundingBox();
      return position.x >= bb.x1 && position.x <= bb.x2 && 
             position.y >= bb.y1 && position.y <= bb.y2;
    });
    
    const sortedNodes = nodesAtPosition.sort((a, b) => {
      const aDepth = a.isNode() ? getNodeDepth(a as NodeSingular) : 0;
      const bDepth = b.isNode() ? getNodeDepth(b as NodeSingular) : 0;
      return bDepth - aDepth;
    });
    
    for (const element of sortedNodes) {
      if (element.isNode() && canDropInto(draggedNode, element)) {
        return element;
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

  const isOutsideNode = (position: Position, node: NodeSingular, threshold: number): boolean => {
    const bb = node.boundingBox();
    return position.x < bb.x1 - threshold || 
           position.x > bb.x2 + threshold || 
           position.y < bb.y1 - threshold || 
           position.y > bb.y2 + threshold;
  };

  const expandBounds = (bb: BoundingBox12, padding: number) => {
    return {
      x1: bb.x1 - padding,
      x2: bb.x2 + padding,
      y1: bb.y1 - padding,
      y2: bb.y2 + padding
    };
  };

  const boundsOverlap = (bb1: any, bb2: any): boolean => {
    if (bb1.x1 > bb2.x2) { return false; }
    if (bb2.x1 > bb1.x2) { return false; }

    if (bb1.x2 < bb2.x1) { return false; }
    if (bb2.x2 < bb1.x1) { return false; }

    if (bb1.y2 < bb2.y1) { return false; }
    if (bb2.y2 < bb1.y1) { return false; }

    if (bb1.y1 > bb2.y2) { return false; }
    if (bb2.y1 > bb1.y2) { return false; }

    return true;
  };

  const shouldRemoveFromParent = (node: NodeSingular, position: Position): boolean => {
    if (!dragState.originalParentBounds) {
      return false;
    }
    
    const nodeBounds = node.boundingBox({ includeOverlays: false, includeLabels: true });
    const expandedNodeBounds = expandBounds(nodeBounds, options.outThreshold);
    
    return !boundsOverlap(dragState.originalParentBounds, expandedNodeBounds);
  };

  const startDrag = (node: NodeSingular) => {
    if (!options.grabbedNode(node)) return;
    if (dragState.isDragging && dragState.draggedNode) {
      return;
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

  // Update drag operation
  const updateDrag = (node: NodeSingular, position: Position) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return;

    const currentParent = node.parent();
    const currentParentNode = currentParent.length > 0 ? currentParent[0] : null;
    
    // Always check for potential drop targets at current position
    const newDropTarget = findDropTargetAtPosition(position, node);
    
    // First, clear any existing drop target styling
    if (dragState.potentialDropTarget) {
      (dragState.potentialDropTarget as NodeSingular).removeClass('cdnd-drop-target');
      dragState.potentialDropTarget = null;
    }
    
    // Check if we should remove from current parent
    if (currentParentNode && shouldRemoveFromParent(node, position)) {
      // Remove any drop target styling if it was previously added
      if (dragState.potentialDropTarget) {
        (dragState.potentialDropTarget as NodeSingular).removeClass('cdnd-drop-target');
        dragState.potentialDropTarget = null;
      }
      
      // Add visual indicator that node is being dragged out of its parent
      node.addClass('cdnd-drag-out');
      // Will be moved to root when dropped
      // The endDrag function will handle moving to root
    } else {
      // Remove drag-out indicator if it was previously added
      node.removeClass('cdnd-drag-out');
      
      // Check for drop targets only when not dragging out
      if (newDropTarget) {
        // Found a valid drop target
        const newDropTargetId = newDropTarget.id();
        const currentParentId = currentParentNode ? currentParentNode.id() : null;
        
        // Only highlight if it's a different parent or we're moving from root to a parent
        if (newDropTargetId !== currentParentId) {
          dragState.potentialDropTarget = newDropTarget;
          (newDropTarget as NodeSingular).addClass('cdnd-drop-target');
        }
      }
    }
  };

  const endDrag = (node: NodeSingular) => {
    if (!dragState.isDragging || dragState.draggedNode?.id() !== node.id()) return;

    node.removeClass('cdnd-grabbed-node');
    node.removeClass('cdnd-drag-out');
    if (dragState.potentialDropTarget) {
      dragState.potentialDropTarget.removeClass('cdnd-drop-target');
    }

    const currentParent = node.parent();
    const currentParentNode = currentParent.length > 0 ? currentParent[0] : null;
    const newParent = dragState.potentialDropTarget;
    const nodePosition = node.position();
    
    let dropPerformed = false;

    const nodeToMove = node;
    
    if (newParent) {
      const currentParentId = currentParentNode ? currentParentNode.id() : null;
      const newParentId = newParent.id();
      
      if (currentParentId !== newParentId) {
        nodeToMove.move({ parent: newParentId });
        cy.trigger('compound-drop', [{ 
          node: nodeToMove, 
          newParent, 
          oldParent: currentParentNode 
        }]);
        dropPerformed = true;
      }
    } else if (currentParentNode) {
      if (shouldRemoveFromParent(nodeToMove, nodePosition)) {
        nodeToMove.move({ parent: null });
        cy.trigger('compound-drop', [{ 
          node: nodeToMove, 
          newParent: null, 
          oldParent: currentParentNode 
        }]);
        dropPerformed = true;
      }
    }

    dragState.draggedNode = null;
    dragState.originalParent = null;
    dragState.originalPosition = null;
    dragState.isDragging = false;
    dragState.potentialDropTarget = null;

    cy.trigger('compound-drag-end', [{ node: nodeToMove, dropPerformed }]);
  };

  cy.on('grab', 'node', (event) => {
    startDrag(event.target);
  });

  cy.on('drag', 'node', (event) => {
    updateDrag(event.target, event.target.position());
  });

  cy.on('free', 'node', (event) => {
    endDrag(event.target);
  });

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
