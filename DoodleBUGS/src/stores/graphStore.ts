import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import type { GraphElement } from '../types';
import { useDataStore } from './dataStore';

export interface GraphContent {
  graphId: string;
  elements: GraphElement[];
  lastLayout?: string;
  zoom?: number;
  pan?: { x: number; y: number };
}

export const useGraphStore = defineStore('graph', () => {
  const dataStore = useDataStore();
  const graphContents = ref<Map<string, GraphContent>>(new Map());
  const currentGraphId = ref<string | null>(
    localStorage.getItem('doodlebugs-currentGraphId') || null
  );
  
  // Shared selection state
  const selectedElement = ref<GraphElement | null>(null);
  // Shared focus state (for zooming/panning to element)
  const elementToFocus = ref<GraphElement | null>(null);

  watch(currentGraphId, (newId) => {
    if (newId) {
      localStorage.setItem('doodlebugs-currentGraphId', newId);
    } else {
      localStorage.removeItem('doodlebugs-currentGraphId');
    }
  });

  const currentGraphElements = computed<GraphElement[]>(() => {
    if (currentGraphId.value && graphContents.value.has(currentGraphId.value)) {
      return graphContents.value.get(currentGraphId.value)!.elements;
    }
    return [];
  });

  const selectGraph = (graphId: string | null) => {
    currentGraphId.value = graphId;
    if (graphId && !graphContents.value.has(graphId)) {
      loadGraph(graphId);
    }
  };
  
  const setSelectedElement = (element: GraphElement | null) => {
    selectedElement.value = element;
  };

  const setElementToFocus = (element: GraphElement | null) => {
    elementToFocus.value = element;
  };

  const createNewGraphContent = (graphId: string) => {
    const newContent: GraphContent = {
      graphId: graphId,
      elements: [],
      lastLayout: 'dagre', // Default layout for new graphs
    };
    graphContents.value.set(graphId, newContent);
    saveGraph(graphId, newContent);
    dataStore.createNewGraphData(graphId);
  };

  const updateGraphElements = (graphId: string, newElements: GraphElement[]) => {
    if (graphContents.value.has(graphId)) {
      const content = graphContents.value.get(graphId)!;
      content.elements = newElements;
      saveGraph(graphId, content);
    }
  };

  const updateGraphLayout = (graphId: string, layoutName: string) => {
    if (graphContents.value.has(graphId)) {
      const content = graphContents.value.get(graphId)!;
      if (content.lastLayout !== layoutName) {
        content.lastLayout = layoutName;
        saveGraph(graphId, content);
      }
    }
  };

  const updateGraphViewport = (graphId: string, zoom: number, pan: { x: number; y: number }) => {
    if (graphContents.value.has(graphId)) {
      const content = graphContents.value.get(graphId)!;
      content.zoom = zoom;
      content.pan = pan;
      saveGraph(graphId, content);
    }
  };

  const deleteGraphContent = (graphId: string) => {
    graphContents.value.delete(graphId);
    localStorage.removeItem(`doodlebugs-graph-${graphId}`);
    dataStore.deleteGraphData(graphId);
    if (currentGraphId.value === graphId) {
      selectGraph(null);
    }
  };

  const saveGraph = (graphId: string, content: GraphContent) => {
    localStorage.setItem(`doodlebugs-graph-${graphId}`, JSON.stringify(content));
  };

  const loadGraph = (graphId: string): GraphContent | null => {
    const storedContent = localStorage.getItem(`doodlebugs-graph-${graphId}`);
    if (storedContent) {
      const content: GraphContent = JSON.parse(storedContent);
      graphContents.value.set(graphId, content);
      return content;
    }
    return null;
  };

  return {
    graphContents,
    currentGraphId,
    currentGraphElements,
    selectedElement,
    elementToFocus,
    setSelectedElement,
    setElementToFocus,
    selectGraph,
    createNewGraphContent,
    updateGraphElements,
    updateGraphLayout,
    updateGraphViewport,
    deleteGraphContent,
    saveGraph,
    loadGraph,
  };
});
