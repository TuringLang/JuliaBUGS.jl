<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useGraphStore } from '../../stores/graphStore';
import { useDataStore } from '../../stores/dataStore';
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator';
import BaseButton from '../ui/BaseButton.vue';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/julia/julia.js';
import CodeMirror from 'codemirror';
import type { Editor } from 'codemirror';

const graphStore = useGraphStore();
const dataStore = useDataStore();

const { currentGraphElements } = storeToRefs(graphStore);
const { parsedGraphData } = storeToRefs(dataStore);

const { generatedCode } = useBugsCodeGenerator(currentGraphElements, parsedGraphData);

const copySuccess = ref(false);
const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: generatedCode.value,
      mode: 'julia',
      theme: 'material-darker',
      lineNumbers: true,
      readOnly: true,
      tabSize: 2,
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

watch(generatedCode, (newCode) => {
  if (cmInstance && cmInstance.getValue() !== newCode) {
    cmInstance.setValue(newCode);
  }
});

const copyCodeToClipboard = () => {
  navigator.clipboard.writeText(generatedCode.value).then(() => {
    copySuccess.value = true;
    setTimeout(() => {
      copySuccess.value = false;
    }, 2000);
  }).catch(err => {
    console.error('Failed to copy code: ', err);
    alert('Failed to copy code to clipboard.');
  });
};
</script>

<template>
  <div class="code-preview-panel">
    <h4>Generated BUGS Code</h4>
    <div class="code-output">
      <div ref="editorContainer" class="editor-container"></div>
      <BaseButton @click="copyCodeToClipboard" class="copy-button" type="secondary">
        <i v-if="copySuccess" class="fas fa-check"></i>
        <span v-else>Copy Code</span>
      </BaseButton>
    </div>
  </div>
</template>

<style>
.code-preview-panel .CodeMirror {
  height: 100%;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.85em;
  border-radius: 8px;
}
</style>

<style scoped>
.code-preview-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
}

h4 {
  margin: 0 0 10px 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.code-output {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  background-color: #282c34;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
  min-height: 0;
}

.editor-container {
  flex-grow: 1;
  position: relative;
}

.copy-button {
  position: absolute;
  bottom: 10px;
  right: 10px;
  padding: 8px 15px;
  background-color: var(--color-secondary);
  color: white;
  border: none;
  border-radius: 5px;
  cursor: pointer;
  z-index: 10;
  opacity: 0.9;
  min-width: 100px;
  text-align: center;
}

.copy-button:hover {
  opacity: 1;
  background-color: var(--color-secondary-hover);
}

.copy-button .fa-check {
  color: var(--color-success);
}
</style>
