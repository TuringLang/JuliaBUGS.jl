<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import { useDataStore } from '../../stores/dataStore';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/javascript/javascript.js';
import 'codemirror/addon/scroll/simplescrollbars.css';
import 'codemirror/addon/scroll/simplescrollbars.js';
import 'codemirror/addon/fold/foldgutter.css';
import 'codemirror/addon/fold/foldgutter.js';
import 'codemirror/addon/fold/brace-fold.js';
import CodeMirror from 'codemirror';
import type { Editor } from 'codemirror';

const props = defineProps<{
  isActive: boolean;
}>();

const dataStore = useDataStore();
const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
let isUpdatingFromSource = false;

const jsonError = ref<string | null>(null);

/**
 * Validates a string to see if it is valid JSON.
 * @param jsonString The string to validate.
 */
const validateJson = (jsonString: string) => {
  try {
    JSON.parse(jsonString);
    jsonError.value = null;
  } catch (e: unknown) {
    jsonError.value = e instanceof Error ? e.message : String(e);
  }
};

onMounted(async () => {
  await nextTick();
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: dataStore.currentGraphDataString,
      mode: { name: "javascript", json: true },
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
      scrollbarStyle: "simple",
      lineWrapping: false,
      foldGutter: true,
      gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"]
    });

    cmInstance.on('change', (instance: Editor) => {
      if (isUpdatingFromSource) return;
      const currentValue = instance.getValue();
      dataStore.currentGraphDataString = currentValue;
      validateJson(currentValue);
    });
    
    validateJson(dataStore.currentGraphDataString);

    if (props.isActive) {
      nextTick(() => cmInstance?.refresh());
    }
  }
});

onUnmounted(() => {
  if (cmInstance) {
    const editorElement = cmInstance.getWrapperElement();
    editorElement.parentNode?.removeChild(editorElement);
    cmInstance = null;
  }
});

watch(() => dataStore.currentGraphDataString, (newData) => {
  if (cmInstance && cmInstance.getValue() !== newData) {
    isUpdatingFromSource = true;
    cmInstance.setValue(newData);
    isUpdatingFromSource = false;
    validateJson(newData);
  }
});

watch(() => props.isActive, (newVal) => {
  if (newVal && cmInstance) {
    nextTick(() => {
      cmInstance?.refresh();
    });
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
    <div class="footer-status">
      <div v-if="jsonError" class="status-message error">
        <i class="fas fa-times-circle"></i> {{ jsonError }}
      </div>
      <div v-else class="status-message success">
        <i class="fas fa-check-circle"></i> Valid JSON
      </div>
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
.CodeMirror-simplescroll-horizontal div, .CodeMirror-simplescroll-vertical div {
  background: #666;
  border-radius: 3px;
}
.CodeMirror-simplescroll-horizontal, .CodeMirror-simplescroll-vertical {
  background: transparent;
  z-index: 99;
}
.CodeMirror-foldgutter-open,
.CodeMirror-foldgutter-folded {
  color: #999;
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
  display: flex;
  position: relative;
  min-height: 0;
}
.editor-container {
  flex-grow: 1;
  position: relative;
  overflow: auto;
}
.footer-status {
  flex-shrink: 0;
  padding-top: 8px;
  min-height: 25px;
  height: auto;
  box-sizing: border-box;
  display: flex;
  align-items: flex-start;
  font-size: 0.8em;
}
.status-message {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  font-weight: 500;
}
.status-message.success {
  color: var(--color-success);
}
.status-message.error {
  color: var(--color-danger);
  white-space: normal;
  word-break: break-word;
}
</style>
