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
    // Temporarily disable undo-redo integration to troubleshoot
    // const cy = getCyInstance();
    // const ur = getUndoRedoInstance();
    
    // if (cy && ur) {
    //   try {
    //     // Use cytoscape undo-redo to add element
    //     const elementData = newElement.type === 'node' ? {
    //       ...newElement,
    //       parent: newElement.parent
    //     } : {
    //       ...newElement
    //     };
        
    //     ur.do('add', {
    //       group: newElement.type === 'node' ? 'nodes' : 'edges',
    //       data: elementData,
    //       position: newElement.type === 'node' ? newElement.position : undefined
    //     });
    //   } catch (error) {
    //     console.warn('⚠️ Undo-redo add failed, falling back to direct addition:', error);
    //     elements.value = [...elements.value, newElement];
    //   }
    // } else {
      // Fallback to direct addition
      elements.value = [...elements.value, newElement];
    // }
    
    selectedElement.value = newElement;
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
    // Temporarily disable undo-redo integration to troubleshoot
    // const cy = getCyInstance();
    // const ur = getUndoRedoInstance();
    
    // if (cy && ur) {
    //   try {
    //     // Use cytoscape undo-redo to remove element
    //     const element = cy.getElementById(elementId);
    //     if (element.length > 0) {
    //       ur.do('remove', element);
    //     }
    //   } catch (error) {
    //     console.warn('⚠️ Undo-redo delete failed, falling back to manual deletion:', error);
    //     deleteElementManually(elementId, visited);
    //   }
    // } else {
      // Fallback to manual deletion logic
      deleteElementManually(elementId, visited);
    // }
  };

  const deleteElementManually = (elementId: string, visited = new Set<string>()) => {
    if (visited.has(elementId)) {
      return;
    }
    visited.add(elementId);

    const elementToDelete = elements.value.find(el => el.id === elementId);
    if (!elementToDelete) return;

    const parentId = elementToDelete.type === 'node' ? elementToDelete.parent : undefined;

    const allIdsToDelete = new Set<string>([elementId]);

    // Recursively find all descendant nodes when deleting a plate
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

    // Delete edges connected to nodes being removed
    elements.value.forEach(el => {
        if (el.type === 'edge' && (nodesBeingDeleted.has(el.source) || nodesBeingDeleted.has(el.target))) {
            allIdsToDelete.add(el.id);
        }
    });

    elements.value = elements.value.filter(el => !allIdsToDelete.has(el.id));

    if (selectedElement.value && allIdsToDelete.has(selectedElement.value.id)) {
      selectedElement.value = null;
    }

    // Auto-cleanup empty parent plates
    if (parentId) {
      const parentPlate = elements.value.find(el => el.id === parentId);
      if (parentPlate && parentPlate.type === 'node' && parentPlate.nodeType === 'plate') {
        const hasRemainingChildren = elements.value.some(el => el.type === 'node' && el.parent === parentId);
        if (!hasRemainingChildren) {
          deleteElement(parentId, visited);
        }
      }
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
