// src/stores/dataStore.ts

import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { useGraphStore } from './graphStore';
import type { ModelData } from '../types';

const defaultJson = `{}`;
const defaultJulia = `()`;

/**
 * A robust utility to convert a Julia NamedTuple string to a JSON string.
 * This version correctly handles Julia's matrix syntax.
 * @param juliaString - The string representing a Julia NamedTuple.
 * @returns A JSON string representation.
 */
function juliaStringToJson(juliaString: string): string {
    if (!juliaString || !juliaString.trim() || juliaString.trim() === '()') {
        return defaultJson;
    }
    try {
        let jsonCompatString = juliaString.trim();

        // 1. Remove outer parentheses if they exist
        if (jsonCompatString.startsWith('(') && jsonCompatString.endsWith(')')) {
            jsonCompatString = jsonCompatString.slice(1, -1).trim();
        }

        // 2. Handle matrices: [1 2; 3 4] -> [[1,2],[3,4]]
        jsonCompatString = jsonCompatString.replace(
            /\[([\s\S]*?)\]/g,
            (match, content) => {
                const trimmedContent = content.trim();
                // If it contains ';', it's a matrix
                if (trimmedContent.includes(';')) {
                    const rows = trimmedContent.split(';')
                        .map((row: string) => row.trim().split(/\s+/).join(', '));
                    return `[${rows.map((row: string) => `[${row}]`).join(', ')}]`;
                }
                // Otherwise, it's a vector or already JSON-like, return as is
                return match;
            }
        );

        // 3. Add quotes around keys
        jsonCompatString = jsonCompatString.replace(/([a-zA-Z_][a-zA-Z0-9_.]*)\s*=/g, '"$1":');

        // 4. Wrap in braces and parse
        const parsed = JSON.parse(`{${jsonCompatString}}`);
        return JSON.stringify(parsed, null, 2);
    } catch (e) {
        console.error("Failed to convert Julia string to JSON:", e, "Input:", juliaString);
        return defaultJson;
    }
}


/**
 * Converts a JSON string to a beautifully formatted Julia NamedTuple string.
 * @param jsonString - The JSON string to convert.
 * @returns A string representing a Julia NamedTuple.
 */
function jsonStringToJuliaString(jsonString: string): string {
    try {
        const obj = JSON.parse(jsonString);
        if (Object.keys(obj).length === 0) return defaultJulia;

        const formatValue = (value: unknown, indentLevel = 1): string => {
            const indent = '  '.repeat(indentLevel);
            if (Array.isArray(value)) {
                // Check if it's a matrix (array of arrays of numbers)
                if (Array.isArray(value[0]) && typeof value[0][0] === 'number') {
                    const formattedRows = value.map(row => `${indent}  ${(row as unknown[]).join(' ')}`);
                    return `[\n${formattedRows.join(';\n')}\n${indent}]`;
                }
                // Handle simple arrays (vectors)
                return `[${value.join(', ')}]`;
            }
            // For scalars, JSON.stringify is fine as it won't add .0 to integers.
            return JSON.stringify(value);
        };

        const entries = Object.entries(obj).map(([key, value]) => {
            const formattedValue = formatValue(value, 1);
            return `  ${key} = ${formattedValue}`;
        });
        return `(\n${entries.join(',\n')}\n)`;
    } catch {
        return defaultJulia;
    }
}

interface DataState {
    mode: 'json' | 'julia';
    jsonData: string;
    jsonInits: string;
    juliaData: string;
    juliaInits: string;
}

export const useDataStore = defineStore('data', () => {
    const graphStore = useGraphStore();
    const dataContents = ref<Map<string, DataState>>(new Map());

    const getGraphData = (graphId: string): DataState => {
        if (!dataContents.value.has(graphId)) {
            const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`);
            if (storedData) {
                const loadedState: DataState = JSON.parse(storedData);
                // If reloading in Julia mode, ensure JSON versions are correctly hydrated.
                if (loadedState.mode === 'julia') {
                    loadedState.jsonData = juliaStringToJson(loadedState.juliaData);
                    loadedState.jsonInits = juliaStringToJson(loadedState.juliaInits);
                }
                dataContents.value.set(graphId, loadedState);
            } else {
                // Default to Julia mode for new/uninitialized graphs.
                dataContents.value.set(graphId, {
                    mode: 'julia',
                    jsonData: defaultJson,
                    jsonInits: defaultJson,
                    juliaData: defaultJulia,
                    juliaInits: defaultJulia
                });
            }
        }
        return dataContents.value.get(graphId)!;
    };

    const currentGraphState = computed(() => {
        const graphId = graphStore.currentGraphId;
        return graphId ? getGraphData(graphId) : null;
    });

    const inputMode = computed({
        get: () => currentGraphState.value?.mode || 'julia',
        set: (newMode) => {
            if (currentGraphState.value && currentGraphState.value.mode !== newMode) {
                currentGraphState.value.mode = newMode;
                updateGraphData(graphStore.currentGraphId!, currentGraphState.value);
            }
        }
    });

    const dataString = computed({
        get: () => {
            if (!currentGraphState.value) return '';
            return inputMode.value === 'json' ? currentGraphState.value.jsonData : currentGraphState.value.juliaData;
        },
        set: (newData) => {
            if (currentGraphState.value) {
                if (inputMode.value === 'json') {
                    currentGraphState.value.jsonData = newData;
                    currentGraphState.value.juliaData = jsonStringToJuliaString(newData);
                } else {
                    currentGraphState.value.juliaData = newData;
                    currentGraphState.value.jsonData = juliaStringToJson(newData);
                }
                updateGraphData(graphStore.currentGraphId!, currentGraphState.value);
            }
        }
    });

    const initsString = computed({
        get: () => {
            if (!currentGraphState.value) return '';
            return inputMode.value === 'json' ? currentGraphState.value.jsonInits : currentGraphState.value.juliaInits;
        },
        set: (newInits) => {
            if (currentGraphState.value) {
                if (inputMode.value === 'json') {
                    currentGraphState.value.jsonInits = newInits;
                    currentGraphState.value.juliaInits = jsonStringToJuliaString(newInits);
                } else {
                    currentGraphState.value.juliaInits = newInits;
                    currentGraphState.value.jsonInits = juliaStringToJson(newInits);
                }
                updateGraphData(graphStore.currentGraphId!, currentGraphState.value);
            }
        }
    });

    const parsedGraphData = computed<ModelData>(() => {
        try {
            const data = JSON.parse(currentGraphState.value?.jsonData || defaultJson);
            const inits = JSON.parse(currentGraphState.value?.jsonInits || defaultJson);
            return { data, inits };
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
            mode: 'julia', // Default to Julia for new graphs
            jsonData: defaultJson,
            jsonInits: defaultJson,
            juliaData: defaultJulia,
            juliaInits: defaultJulia
        };
        dataContents.value.set(graphId, newState);
        updateGraphData(graphId, newState);
    };

    const deleteGraphData = (graphId: string) => {
        dataContents.value.delete(graphId);
        localStorage.removeItem(`doodlebugs-data-${graphId}`);
    };

    return {
        inputMode,
        dataString,
        initsString,
        parsedGraphData,
        createNewGraphData,
        deleteGraphData,
        getGraphData,
        updateGraphData
    };
});
