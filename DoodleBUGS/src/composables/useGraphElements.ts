import { computed, ref } from 'vue';
import { useGraphStore } from '../stores/graphStore';
import { useGraphInstance } from './useGraphInstance';
import type { GraphElement, GraphNode } from '../types';

export function useGraphElements() {
  const graphStore = useGraphStore();
  const { getCyInstance, getUndoRedoInstance } = useGraphInstance();

  const selectedElement = ref<GraphElement | null>(null);

  const elements = computed<GraphElement[]>({
    get: () => graphStore.currentGraphElements,
    set: (newElements) => {
      if (graphStore.currentGraphId) {
        graphStore.updateGraphElements(graphStore.currentGraphId, newElements);
      }
    }
  });

  const addElement = (newElement: GraphElement) => {
    // Add to Vue store first for immediate UI update
    elements.value = [...elements.value, newElement];
    selectedElement.value = newElement;
    
    // Add to cytoscape - let cytoscape-undo-redo handle the tracking
    const cy = getCyInstance();
    const ur = getUndoRedoInstance();
    
    if (cy) {
      try {
        const cyElement = cy.add({
          group: newElement.type === 'node' ? 'nodes' : 'edges',
          data: newElement,
          position: newElement.type === 'node' ? (newElement as GraphNode).position : undefined
        });
        
        console.log('Element added to cytoscape:', newElement.id);
        
        // Manually trigger undo-redo tracking if needed
        if (ur) {
          console.log('Undo-redo instance available for tracking');
        }
      } catch (error) {
        console.warn('Failed to add element to cytoscape:', error);
      }
    }
  };

  const updateElement = (updatedElement: GraphElement) => {
    elements.value = elements.value.map(el =>
      el.id === updatedElement.id ? updatedElement : el
    );
    if (selectedElement.value?.id === updatedElement.id) {
      selectedElement.value = updatedElement;
    }
  };

  const deleteElement = (elementId: string, visited = new Set<string>()) => {
    const elementToDelete = elements.value.find(el => el.id === elementId);
    if (!elementToDelete) return;
    
    // Remove from Vue store for immediate UI update
    deleteElementManually(elementId, visited);
    
    // Remove from cytoscape - let cytoscape-undo-redo handle the tracking  
    const cy = getCyInstance();
    const ur = getUndoRedoInstance();
    
    if (cy) {
      try {
        const element = cy.getElementById(elementId);
        if (element.length > 0) {
          element.remove();
          console.log('Element removed from cytoscape:', elementId);
          
          if (ur) {
            console.log('Undo-redo instance available for tracking removal');
          }
        }
      } catch (error) {
        console.warn('Failed to remove element from cytoscape:', error);
      }
    }
  };

  const deleteElementManually = (elementId: string, visited = new Set<string>()) => {
    if (visited.has(elementId)) {
      return;
    }
    visited.add(elementId);

    const elementToDelete = elements.value.find(el => el.id === elementId);
    if (!elementToDelete) return;

    const allIdsToDelete = new Set<string>([elementId]);

    // Recursively find all descendant nodes when deleting a plate.
    if (elementToDelete.type === 'node' && elementToDelete.nodeType === 'plate') {
      const findDescendants = (currentParentId: string) => {
        elements.value.forEach(el => {
          if (el.type === 'node' && el.parent === currentParentId) {
            allIdsToDelete.add(el.id);
            if (el.nodeType === 'plate') {
              findDescendants(el.id);
            }
          }
        });
      };
      findDescendants(elementId);
    }
    
    const nodesBeingDeleted = new Set<string>();
    allIdsToDelete.forEach(id => {
        const el = elements.value.find(e => e.id === id);
        if (el?.type === 'node') {
            nodesBeingDeleted.add(id);
        }
    });

    // Delete edges connected to the nodes being removed.
    elements.value.forEach(el => {
        if (el.type === 'edge' && (nodesBeingDeleted.has(el.source) || nodesBeingDeleted.has(el.target))) {
            allIdsToDelete.add(el.id);
        }
    });

    elements.value = elements.value.filter(el => !allIdsToDelete.has(el.id));

    if (selectedElement.value && allIdsToDelete.has(selectedElement.value.id)) {
      selectedElement.value = null;
    }
  };

  return {
    elements,
    selectedElement,
    addElement,
    updateElement,
    deleteElement,
  };
}
