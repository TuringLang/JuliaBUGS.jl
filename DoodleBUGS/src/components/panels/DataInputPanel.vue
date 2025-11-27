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
import 'codemirror/addon/edit/matchbrackets.js';
import CodeMirror from 'codemirror';
import type { Editor } from 'codemirror';

const props = defineProps<{
  isActive: boolean;
}>();

const dataStore = useDataStore();
const editorContainer = ref<HTMLDivElement | null>(null);

let cm: Editor | null = null;
let isUpdatingFromSource = false;
let resizeObserver: ResizeObserver | null = null;

const jsonError = ref<string | null>(null);

const validateJson = (jsonString: string) => {
  try {
    JSON.parse(jsonString);
    jsonError.value = null;
  } catch (e: unknown) {
    jsonError.value = e instanceof Error ? e.message : String(e);
  }
};

const setupCodeMirror = () => {
  if (cm) {
    const wrapper = cm.getWrapperElement();
    wrapper.parentNode?.removeChild(wrapper);
    cm = null;
  }

  nextTick(() => {
    if (editorContainer.value) {
      cm = CodeMirror(editorContainer.value, {
        value: dataStore.dataContent,
        mode: { name: "javascript", json: true },
        theme: 'material-darker',
        lineNumbers: true,
        tabSize: 2,
        scrollbarStyle: "simple",
        lineWrapping: false,
        foldGutter: true,
        gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"],
        matchBrackets: true,
      });

      cm.on('change', (instance) => {
        if (isUpdatingFromSource) return;
        const val = instance.getValue();
        dataStore.dataContent = val;
        validateJson(val);
      });
    }
  });
};

onMounted(() => {
  setupCodeMirror();
  
  if (editorContainer.value) {
      resizeObserver = new ResizeObserver(() => {
          if (cm) cm.refresh();
      });
      resizeObserver.observe(editorContainer.value);
  }
});

onUnmounted(() => {
  if (cm) {
    const wrapper = cm.getWrapperElement();
    wrapper.parentNode?.removeChild(wrapper);
  }
  if (resizeObserver) {
      resizeObserver.disconnect();
  }
});

watch(() => dataStore.dataContent, (newValue) => {
  if (!cm) return;
  if (cm.getValue() !== newValue) {
      isUpdatingFromSource = true;
      cm.setValue(newValue);
      validateJson(newValue);
      isUpdatingFromSource = false;
  }
});

watch(() => props.isActive, (newVal) => {
  if (newVal) {
    nextTick(() => {
      cm?.refresh();
    });
  }
});
</script>

<template>
  <div class="data-input-panel">
    <div class="header-controls">
        <h4 class="panel-title">Model Data & Inits</h4>
    </div>
    <p class="description">
      Define observed data and initial values in a single JSON object.
    </p>

    <div class="editor-wrapper flex-grow">
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
  font-family: monospace;
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
.header-controls {
    display: flex;
    justify-content: center;
    align-items: center;
    border-bottom: 1px solid var(--color-border-light);
    padding-bottom: 10px;
}
h4 {
  margin: 0;
  color: var(--color-heading);
}
.description {
  font-size: 0.85em;
  color: var(--color-secondary);
  text-align: center;
  margin: 0 0 5px 0;
  line-height: 1.4;
}
.editor-wrapper {
  flex: 1;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  display: flex;
  flex-direction: column;
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
  padding-top: 0;
  padding-bottom: 4px;
  padding-left: 12px;
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
