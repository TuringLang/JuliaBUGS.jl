
<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import { useDataStore } from '../../stores/dataStore';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/javascript/javascript.js';
import 'codemirror/mode/julia/julia.js';
import 'codemirror/addon/scroll/simplescrollbars.css';
import 'codemirror/addon/scroll/simplescrollbars.js';
import 'codemirror/addon/fold/foldgutter.css';
import 'codemirror/addon/fold/foldgutter.js';
import 'codemirror/addon/fold/brace-fold.js';
import CodeMirror from 'codemirror';
import type { Editor, EditorConfiguration } from 'codemirror';
import BaseButton from '../ui/BaseButton.vue';

const props = defineProps<{
  isActive: boolean;
}>();

const dataStore = useDataStore();
const dataEditorContainer = ref<HTMLDivElement | null>(null);
const initsEditorContainer = ref<HTMLDivElement | null>(null);

let dataCm: Editor | null = null;
let initsCm: Editor | null = null;
let isUpdatingFromSource = false;

const jsonError = ref<string | null>(null);
const jsonInitsError = ref<string | null>(null);

const validateJson = (jsonString: string) => {
  try {
    JSON.parse(jsonString);
    jsonError.value = null;
  } catch (e: unknown) {
    jsonError.value = e instanceof Error ? e.message : String(e);
  }
};

const validateJsonInits = (jsonString: string) => {
  try {
    JSON.parse(jsonString);
    jsonInitsError.value = null;
  } catch (e: unknown) {
    jsonInitsError.value = e instanceof Error ? e.message : String(e);
  }
};

const setupCodeMirror = () => {
  // Destroy existing instances
  [dataCm, initsCm].forEach(cm => {
    if (cm) {
      const wrapper = cm.getWrapperElement();
      wrapper.parentNode?.removeChild(wrapper);
    }
  });
  dataCm = null;
  initsCm = null;

  nextTick(() => {
    if (dataStore.inputMode === 'julia') {
      if (dataEditorContainer.value) {
        dataCm = createCmInstance(dataEditorContainer.value, `data = ${dataStore.dataString}\n\ninits = ${dataStore.initsString}`, 'julia');
        dataCm.on('change', (instance) => {
          if (isUpdatingFromSource) return;
          const combinedValue = instance.getValue();
          const dataMatch = combinedValue.match(/data\s*=\s*(\([\s\S]*?\))\s*/m);
          const initsMatch = combinedValue.match(/inits\s*=\s*(\([\s\S]*?\))\s*/m);
          dataStore.dataString = dataMatch ? dataMatch[1] : '()';
          dataStore.initsString = initsMatch ? initsMatch[1] : '()';
        });
      }
    } else { // JSON mode
      if (dataEditorContainer.value) {
        dataCm = createCmInstance(dataEditorContainer.value, dataStore.dataString, { name: "javascript", json: true });
        dataCm.on('change', (instance) => {
          if (isUpdatingFromSource) return;
          dataStore.dataString = instance.getValue();
          validateJson(instance.getValue());
        });
      }
      if (initsEditorContainer.value) {
        initsCm = createCmInstance(initsEditorContainer.value, dataStore.initsString, { name: "javascript", json: true });
        initsCm.on('change', (instance) => {
          if (isUpdatingFromSource) return;
          dataStore.initsString = instance.getValue();
          validateJsonInits(instance.getValue());
        });
      }
    }
  });
};

const createCmInstance = (container: HTMLElement, value: string, mode: string | EditorConfiguration["mode"]): Editor => {
  return CodeMirror(container, {
    value,
    mode,
    theme: 'material-darker',
    lineNumbers: true,
    tabSize: 2,
    scrollbarStyle: "simple",
    lineWrapping: false,
    foldGutter: true,
    gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"]
  });
};

onMounted(setupCodeMirror);
onUnmounted(() => {
  [dataCm, initsCm].forEach(cm => {
    if (cm) {
      const wrapper = cm.getWrapperElement();
      wrapper.parentNode?.removeChild(wrapper);
    }
  });
});

watch(() => dataStore.inputMode, setupCodeMirror);

watch([() => dataStore.dataString, () => dataStore.initsString], () => {
  if (!dataCm) return;
  isUpdatingFromSource = true;
  if (dataStore.inputMode === 'julia') {
    const combined = `data = ${dataStore.dataString}\n\ninits = ${dataStore.initsString}`;
    if (dataCm.getValue() !== combined) dataCm.setValue(combined);
  } else {
    if (dataCm.getValue() !== dataStore.dataString) dataCm.setValue(dataStore.dataString);
    if (initsCm && initsCm.getValue() !== dataStore.initsString) initsCm.setValue(dataStore.initsString);
    validateJson(dataStore.dataString);
    validateJsonInits(dataStore.initsString);
  }
  isUpdatingFromSource = false;
}, { deep: true });

watch(() => props.isActive, (newVal) => {
  if (newVal) {
    nextTick(() => {
      dataCm?.refresh();
      initsCm?.refresh();
    });
  }
});
</script>

<template>
  <div class="data-input-panel">
    <div class="header-controls">
        <h4>Model Data & Inits</h4>
        <div class="mode-switcher">
            <BaseButton class="base-button" :class="{active: dataStore.inputMode === 'json'}" @click="dataStore.inputMode = 'json'" size="small">JSON</BaseButton>
            <BaseButton class="base-button" :class="{active: dataStore.inputMode === 'julia'}" @click="dataStore.inputMode = 'julia'" size="small">Julia</BaseButton>
        </div>
    </div>
    <p class="description">
      Define observed data and initial values for your model.
    </p>

    <div v-if="dataStore.inputMode === 'julia'" class="editor-wrapper flex-grow">
      <div ref="dataEditorContainer" class="editor-container"></div>
    </div>

    <div v-else class="json-editors-container">
        <div class="editor-wrapper">
            <label>Data</label>
            <div ref="dataEditorContainer" class="editor-container"></div>
        </div>
        <div class="editor-wrapper">
            <label>Inits</label>
            <div ref="initsEditorContainer" class="editor-container"></div>
        </div>
    </div>

    <div class="footer-status">
      <div v-if="dataStore.inputMode === 'json'">
        <div v-if="jsonError" class="status-message error">
            <i class="fas fa-times-circle"></i> <strong>Data:</strong> {{ jsonError }}
        </div>
        <div v-else class="status-message success">
            <i class="fas fa-check-circle"></i> <strong>Data:</strong> Valid JSON
        </div>
        <div v-if="jsonInitsError" class="status-message error">
            <i class="fas fa-times-circle"></i> <strong>Inits:</strong> {{ jsonInitsError }}
        </div>
        <div v-else class="status-message success">
            <i class="fas fa-check-circle"></i> <strong>Inits:</strong> Valid JSON
        </div>
      </div>
      <div v-else class="status-message info">
        <i class="fas fa-info-circle"></i> Editing in Julia syntax mode.
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
.header-controls {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--color-border-light);
    padding-bottom: 10px;
}
h4 {
  margin: 0;
  color: var(--color-heading);
}
.mode-switcher {
    display: flex;
    border: 1px solid var(--color-border);
    border-radius: 6px;
    overflow: hidden;
}
.mode-switcher .base-button {
    border: none;
    border-radius: 0;
    background-color: var(--color-background-soft);
    color: var(--color-text);
    box-sizing: border-box;
    opacity: 0.7;
    transition: all 0.2s;
}
.mode-switcher .base-button:hover {
    background-color: var(--color-background-mute);
    opacity: 1;
}
.mode-switcher .base-button.active {
    background-color: var(--theme-primary) !important;
    color: var(--theme-text-inverse) !important;
    opacity: 1;
}
:global(html.dark-mode) .mode-switcher .base-button.active {
    /* Ensure contrast in dark mode if inverse is white */
    color: #fff !important; 
}

.description {
  font-size: 0.85em;
  color: var(--color-secondary);
  text-align: center;
  margin: 0 0 5px 0;
  line-height: 1.4;
}
.json-editors-container {
    flex-grow: 1;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 0;
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
.editor-wrapper.flex-grow {
    flex-grow: 1;
}
.editor-wrapper label {
    font-size: 0.8em;
    font-weight: 500;
    padding: 4px 8px;
    background-color: var(--color-background-mute);
    border-bottom: 1px solid var(--color-border);
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
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
.status-message.info {
    color: var(--color-info);
}
</style>
