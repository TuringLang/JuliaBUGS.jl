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

    const parentId = elementToDelete.type === 'node' ? elementToDelete.parent : undefined;

    const allIdsToDelete = new Set<string>([elementId]);

    // Recursively find all descendant nodes when deleting a plate
    if (elementToDelete.type === 'node' && elementToDelete.nodeType === 'plate') {
      const findDescendants = (parentId: string) => {
        elements.value.forEach(el => {
          if (el.type === 'node' && el.parent === parentId) {
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
          deleteElement(parentId);
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
