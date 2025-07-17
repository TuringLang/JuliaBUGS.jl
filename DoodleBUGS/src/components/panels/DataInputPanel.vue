<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useDataStore } from '../../stores/dataStore';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/javascript/javascript.js';
import CodeMirror from 'codemirror';
import type { Editor } from 'codemirror';

const dataStore = useDataStore();
const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
let isUpdatingFromSource = false;

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: dataStore.currentGraphData,
      mode: { name: "javascript", json: true },
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
    });

    cmInstance.on('change', (instance) => {
      if (isUpdatingFromSource) return;
      dataStore.currentGraphData = instance.getValue();
    });
  }
});

onUnmounted(() => {
  if (cmInstance) {
    const editorElement = cmInstance.getWrapperElement();
    editorElement.parentNode?.removeChild(editorElement);
    cmInstance = null;
  }
});

watch(() => dataStore.currentGraphData, (newData) => {
  if (cmInstance && cmInstance.getValue() !== newData) {
    isUpdatingFromSource = true;
    cmInstance.setValue(newData);
    isUpdatingFromSource = false;
  }
});
</script>

<template>
  <div class="data-input-panel">
    <h4>Model Data & Inits</h4>
    <p class="description">
      Define observed data and initial values for your model in JSON format.
    </p>
    <div class="editor-wrapper">
      <div ref="editorContainer" class="editor-container"></div>
    </div>
  </div>
</template>

<style>
.data-input-panel .CodeMirror {
  height: 100%;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.85em;
  border-radius: 8px;
}
</style>

<style scoped>
.data-input-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
h4 {
  margin: 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}
.description {
  font-size: 0.85em;
  color: var(--color-secondary);
  text-align: center;
  margin: 0 0 5px 0;
  line-height: 1.4;
}
.editor-wrapper {
  flex-grow: 1;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  overflow: hidden;
  display: flex;
  position: relative;
  min-height: 0;
}
.editor-container {
  flex-grow: 1;
  position: relative;
}
</style>
