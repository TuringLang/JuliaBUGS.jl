<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { useGraphStore } from '../../stores/graphStore';
import type { GraphElement } from '../../types';

const graphStore = useGraphStore();

const jsonText = ref('');
const errorText = ref('');

const graphElements = computed(() => graphStore.currentGraphElements);

watch(graphElements, (newElements) => {
  if (newElements) {
    try {
      if (jsonText.value) {
        const currentJson = JSON.parse(jsonText.value);
        if (JSON.stringify(currentJson) === JSON.stringify(newElements)) {
          return;
        }
      }
    } catch (e) {
      // Ignore parse error, we will overwrite it.
    }
    jsonText.value = JSON.stringify(newElements, null, 2);
    errorText.value = '';
  }
}, { deep: true, immediate: true });

const handleJsonInput = () => {
  try {
    const newElements: GraphElement[] = JSON.parse(jsonText.value);
    if (!Array.isArray(newElements)) {
        throw new Error("JSON must be an array of graph elements.");
    }
    if (graphStore.currentGraphId) {
      if (JSON.stringify(graphStore.currentGraphElements) !== JSON.stringify(newElements)) {
        graphStore.updateGraphElements(graphStore.currentGraphId, newElements);
      }
    }
    errorText.value = '';
  } catch (e: any) {
    errorText.value = `Invalid JSON: ${e.message}`;
  }
};
</script>

<template>
  <div class="json-editor-panel">
    <div class="header-section">
      <h4>Live Graph JSON</h4>
      <p class="description">
        Edit the JSON below to see live updates on the canvas. Changes on the canvas will reflect here.
      </p>
    </div>
    <textarea
      v-model="jsonText"
      @input="handleJsonInput"
      class="json-textarea"
      placeholder="Graph JSON will appear here..."
      spellcheck="false"
    ></textarea>
    <div v-if="errorText" class="error-message">
      {{ errorText }}
    </div>
  </div>
</template>

<style scoped>
.json-editor-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.header-section {
  padding: 15px;
  padding-bottom: 10px;
  flex-shrink: 0;
}

h4 {
  margin: 0 0 10px 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.description {
  font-size: 0.85em;
  color: var(--color-secondary);
  text-align: center;
  margin: 0;
  line-height: 1.4;
}

.json-textarea {
  flex-grow: 1;
  width: 100%;
  border: none;
  border-top: 1px solid var(--color-border);
  border-bottom: 1px solid var(--color-border);
  padding: 10px;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.8em;
  line-height: 1.5;
  background-color: #282c34;
  color: #abb2bf;
  resize: none;
  box-sizing: border-box;
}

.json-textarea:focus {
  border-color: var(--color-primary);
  outline: none;
  box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25) inset;
}

.error-message {
  color: var(--color-danger);
  background-color: #ffe0e0;
  border: 1px solid var(--color-danger);
  border-radius: 4px;
  padding: 10px;
  margin: 15px;
  font-size: 0.8em;
  white-space: pre-wrap;
  word-break: break-all;
  flex-shrink: 0;
}
</style>
