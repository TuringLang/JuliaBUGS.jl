<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import { useScriptStore } from '../../stores/scriptStore';
import { storeToRefs } from 'pinia';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/julia/julia.js';
import 'codemirror/addon/scroll/simplescrollbars.css';
import 'codemirror/addon/scroll/simplescrollbars.js';
import CodeMirror from 'codemirror';
import type { Editor } from 'codemirror';
import BaseButton from '../ui/BaseButton.vue';

const props = defineProps<{
  isActive: boolean;
}>();

defineEmits<{
  (e: 'open-settings'): void;
  (e: 'download'): void;
  (e: 'generate'): void;
}>();

const scriptStore = useScriptStore();
const { standaloneScript } = storeToRefs(scriptStore);

const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
const copySuccess = ref(false);

onMounted(() => {
  if (editorContainer.value && standaloneScript.value) {
    initEditor();
  }
});

const initEditor = () => {
    if (!editorContainer.value) return;
    if (cmInstance) {
        cmInstance.setValue(standaloneScript.value);
        return;
    }
    cmInstance = CodeMirror(editorContainer.value, {
      value: standaloneScript.value,
      mode: 'julia',
      theme: 'material-darker',
      lineNumbers: true,
      readOnly: true,
      tabSize: 2,
      scrollbarStyle: "simple",
      lineWrapping: false,
    });
};

onUnmounted(() => {
  if (cmInstance) {
    const wrapper = cmInstance.getWrapperElement();
    wrapper.parentNode?.removeChild(wrapper);
    cmInstance = null;
  }
});

watch(standaloneScript, (newValue) => {
  if (newValue) {
      nextTick(() => {
          if (!cmInstance && editorContainer.value) {
              initEditor();
          }
          if (cmInstance && cmInstance.getValue() !== newValue) {
              cmInstance.setValue(newValue);
          }
      });
  }
});

watch(() => props.isActive, (newVal) => {
  if (newVal && cmInstance) {
    nextTick(() => cmInstance?.refresh());
  }
});

const copyScript = async () => {
  try {
    await navigator.clipboard.writeText(standaloneScript.value);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  } catch {
    const textArea = document.createElement("textarea");
    textArea.value = standaloneScript.value;
    textArea.style.position = "fixed";
    textArea.style.opacity = "0";
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    try {
      document.execCommand('copy');
      copySuccess.value = true;
      setTimeout(() => copySuccess.value = false, 2000);
    } catch (e) {
      console.error(e);
      alert('Failed to copy script.');
    }
    document.body.removeChild(textArea);
  }
};
</script>

<template>
  <div class="local-script-panel">
    <div v-if="!standaloneScript" class="empty-state">
      <p>No script generated yet.</p>
      <BaseButton type="primary" @click="$emit('generate')">Generate Julia Script</BaseButton>
    </div>
    <div v-else class="panel-container">
        <div class="panel-header">
            <span class="title">Julia Script</span>
            <div class="actions">
                <button @click="$emit('open-settings')" title="Script Configuration" class="action-btn"><i class="fas fa-cog"></i></button>
                <button @click="$emit('download')" title="Download" class="action-btn"><i class="fas fa-download"></i></button>
            </div>
        </div>
        <div class="editor-wrapper">
          <div ref="editorContainer" class="editor-container"></div>
          <button
            @click.stop="copyScript"
            class="native-copy-button"
            type="button"
            title="Copy Script"
          >
            <i v-if="copySuccess" class="fas fa-check"></i>
            <i v-else class="fas fa-copy"></i>
          </button>
        </div>
    </div>
  </div>
</template>

<style scoped>
.local-script-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 0;
  box-sizing: border-box;
}

.empty-state {
    flex-grow: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 15px;
    color: var(--color-text-secondary);
    font-style: italic;
    padding: 20px;
    text-align: center;
}

.panel-container {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 10px;
    gap: 10px;
}

.panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--color-border);
}

.title {
    font-weight: 600;
    color: var(--color-heading);
    font-size: 0.9em;
}

.actions {
    display: flex;
    gap: 8px;
}

.action-btn {
    background: transparent;
    border: none;
    cursor: pointer;
    color: var(--theme-text-secondary);
    font-size: 14px;
    padding: 4px;
    transition: color 0.2s;
}

.action-btn:hover {
    color: var(--theme-text-primary);
}

.editor-wrapper {
  flex-grow: 1;
  background-color: #282c34;
  border-radius: 4px;
  position: relative;
  overflow: hidden;
  min-height: 0;
}

.editor-container {
  height: 100%;
}

:deep(.CodeMirror) {
  height: 100%;
  font-family: monospace;
  font-size: 0.85em;
}

.native-copy-button {
  position: absolute;
  bottom: 5px;
  right: 5px;
  width: 36px;
  height: 36px;
  background-color: transparent;
  color: #fff;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  cursor: pointer;
  opacity: 0.5;
  transition: background-color 0.2s, opacity 0.2s;
  z-index: 1000;
  pointer-events: auto;
  border: none;
  outline: none;
}

.native-copy-button:hover {
  background-color: transparent;
  opacity: 1;
}

.native-copy-button:active {
  transform: scale(0.95);
}

.native-copy-button .fa-copy,
.native-copy-button .fa-check {
  font-size: 1rem;
}
</style>
