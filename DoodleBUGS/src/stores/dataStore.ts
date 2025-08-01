import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { useGraphStore } from './graphStore';
import type { ModelData } from '../types';

const defaultData = 
`{
  "data": {},
  "inits": {}
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

  const parsedGraphData = computed<ModelData>(() => {
    try {
      const parsed = JSON.parse(currentGraphDataString.value);
      return {
        data: parsed.data || {},
        inits: parsed.inits || {}
      };
    } catch {
      return { data: {}, inits: {} };
    }
  });


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
