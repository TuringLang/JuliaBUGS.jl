import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import { useGraphStore } from './graphStore';
import type { ModelData } from '../types';

const defaultData = 
`{
  "data": {
    "N": 30,
    "T": 5,
    "x": [8.0, 15.0, 22.0, 29.0, 36.0],
    "xbar": 22
  },
  "inits": {
    "alpha": "fill(250.0, 30)",
    "beta": "fill(6.0, 30)"
  }
}`;

export const useDataStore = defineStore('data', () => {
  const graphStore = useGraphStore();
  const dataContents = ref<Map<string, string>>(new Map());

  const currentGraphDataString = computed({
    get: () => {
      const graphId = graphStore.currentGraphId;
      if (graphId && dataContents.value.has(graphId)) {
        return dataContents.value.get(graphId)!;
      }
      if (graphId) {
        const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`);
        if (storedData) {
          dataContents.value.set(graphId, storedData);
          return storedData;
        }
        dataContents.value.set(graphId, defaultData);
        return defaultData;
      }
      return defaultData;
    },
    set: (newData: string) => {
      const graphId = graphStore.currentGraphId;
      if (graphId) {
        updateGraphData(graphId, newData);
      }
    }
  });

  // Use a ref and a watcher instead of a computed property to resolve the type mismatch.
  // This ensures that `parsedGraphData` is a writable Ref<ModelData>, which is expected by downstream composables.
  const parsedGraphData = ref<ModelData>({ data: {}, inits: {} });

  watch(currentGraphDataString, (newString) => {
    try {
      parsedGraphData.value = JSON.parse(newString);
    } catch (e) {
      // If JSON is invalid, reset to a default empty structure.
      parsedGraphData.value = { data: {}, inits: {} };
    }
  }, { immediate: true });


  const updateGraphData = (graphId: string, newData: string) => {
    dataContents.value.set(graphId, newData);
    localStorage.setItem(`doodlebugs-data-${graphId}`, newData);
  };
  
  const createNewGraphData = (graphId: string) => {
    updateGraphData(graphId, defaultData);
  };

  const deleteGraphData = (graphId: string) => {
    dataContents.value.delete(graphId);
    localStorage.removeItem(`doodlebugs-data-${graphId}`);
  };

  return {
    currentGraphDataString,
    parsedGraphData,
    createNewGraphData,
    deleteGraphData,
  };
});
