import { computed, ref } from 'vue';
import { useGraphStore } from '../stores/graphStore';
import type { GraphElement } from '../types';

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
    elements.value = elements.value.filter(el => el.id !== elementId);
    if (selectedElement.value?.id === elementId) {
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
