import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useGraphStore } from '../stores/graphStore';
import type { GraphElement } from '../types';

export function useGraphElements(graphId?: string) {
  const graphStore = useGraphStore();

  const targetGraphId = computed(() => graphId || graphStore.currentGraphId);

  // Use the shared selectedElement from the store
  const { selectedElement } = storeToRefs(graphStore);

  const elements = computed<GraphElement[]>({
    get: () => {
      const id = targetGraphId.value;
      if (id && graphStore.graphContents.has(id)) {
        return graphStore.graphContents.get(id)!.elements;
      }
      return [];
    },
    set: (newElements) => {
      const id = targetGraphId.value;
      if (id) {
        graphStore.updateGraphElements(id, newElements);
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
