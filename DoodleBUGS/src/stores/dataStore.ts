import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { useGraphStore } from './graphStore';
import type { ModelData } from '../types';

const defaultContent = JSON.stringify({
  data: {},
  inits: {}
}, null, 2);

interface DataState {
    content: string;
}

export const useDataStore = defineStore('data', () => {
    const graphStore = useGraphStore();
    const dataContents = ref<Map<string, DataState>>(new Map());

    const getGraphData = (graphId: string): DataState => {
        if (!dataContents.value.has(graphId)) {
            const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`);
            if (storedData) {
                try {
                    const loadedState = JSON.parse(storedData);
                    if (loadedState.jsonData !== undefined) {
                        const merged = {
                            data: JSON.parse(loadedState.jsonData || '{}'),
                            inits: JSON.parse(loadedState.jsonInits || '{}')
                        };
                        dataContents.value.set(graphId, { content: JSON.stringify(merged, null, 2) });
                    } else {
                        dataContents.value.set(graphId, loadedState);
                    }
                } catch (e) {
                    console.error("Failed to parse stored data", e);
                    dataContents.value.set(graphId, { content: defaultContent });
                }
            } else {
                dataContents.value.set(graphId, { content: defaultContent });
            }
        }
        return dataContents.value.get(graphId)!;
    };

    const currentGraphState = computed(() => {
        const graphId = graphStore.currentGraphId;
        return graphId ? getGraphData(graphId) : null;
    });

    const dataContent = computed({
        get: () => {
            if (!currentGraphState.value) return defaultContent;
            return currentGraphState.value.content;
        },
        set: (newContent) => {
            if (currentGraphState.value) {
                currentGraphState.value.content = newContent;
                updateGraphData(graphStore.currentGraphId!, currentGraphState.value);
            }
        }
    });

    const parsedGraphData = computed<ModelData>(() => {
        try {
            const parsed = JSON.parse(currentGraphState.value?.content || defaultContent);
            return {
                data: parsed.data || {},
                inits: parsed.inits || {}
            };
        } catch {
            return { data: {}, inits: {} };
        }
    });

    const updateGraphData = (graphId: string, newState: DataState) => {
        dataContents.value.set(graphId, newState);
        localStorage.setItem(`doodlebugs-data-${graphId}`, JSON.stringify(newState));
    };

    const createNewGraphData = (graphId: string) => {
        const newState: DataState = {
            content: defaultContent
        };
        dataContents.value.set(graphId, newState);
        updateGraphData(graphId, newState);
    };

    const deleteGraphData = (graphId: string) => {
        dataContents.value.delete(graphId);
        localStorage.removeItem(`doodlebugs-data-${graphId}`);
    };

    return {
        dataContent,
        parsedGraphData,
        createNewGraphData,
        deleteGraphData,
        getGraphData,
        updateGraphData
    };
});
