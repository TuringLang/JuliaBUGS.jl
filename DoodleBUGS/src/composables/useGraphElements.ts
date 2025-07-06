import { computed, ref } from 'vue';
import { useGraphStore } from '../stores/graphStore';
import type { GraphElement, GraphNode } from '../types';

export function useGraphElements() {
  const graphStore = useGraphStore();

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
    elements.value = [...elements.value, newElement];
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

  const deleteElement = (elementId: string) => {
    const elementToDelete = elements.value.find(el => el.id === elementId);
    if (!elementToDelete) return;

    const allIdsToDelete = new Set<string>([elementId]);

    // If deleting a plate, recursively find all descendant nodes to delete them too.
    if (elementToDelete.type === 'node' && elementToDelete.nodeType === 'plate') {
      const findDescendants = (parentId: string) => {
        elements.value.forEach(el => {
          if (el.type === 'node' && el.parent === parentId) {
            allIdsToDelete.add(el.id);
            // This is for future-proofing in case nested plates are ever supported.
            if (el.nodeType === 'plate') {
              findDescendants(el.id);
            }
          }
        });
      };
      findDescendants(elementId);
    }
    
    // Create a set of all nodes that are marked for deletion.
    const nodesBeingDeleted = new Set<string>();
    allIdsToDelete.forEach(id => {
        const el = elements.value.find(e => e.id === id);
        if (el?.type === 'node') {
            nodesBeingDeleted.add(id);
        }
    });

    // Also mark for deletion any edges connected to the nodes being deleted.
    elements.value.forEach(el => {
        if (el.type === 'edge' && (nodesBeingDeleted.has(el.source) || nodesBeingDeleted.has(el.target))) {
            allIdsToDelete.add(el.id);
        }
    });

    // Filter the elements array to remove all items marked for deletion.
    elements.value = elements.value.filter(el => !allIdsToDelete.has(el.id));

    // If the currently selected element is one of those deleted, deselect it.
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
