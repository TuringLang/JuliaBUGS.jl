<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import { useGraphStore } from '../../stores/graphStore';
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator';
import BaseButton from '../ui/BaseButton.vue';

import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/julia/julia.js';
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

const graphStore = useGraphStore();

const { currentGraphElements } = storeToRefs(graphStore);

const { generatedCode } = useBugsCodeGenerator(currentGraphElements);

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
      scrollbarStyle: "simple",
      foldGutter: true,
      gutters: ["CodeMirror-linenumbers", "CodeMirror-foldgutter"]
    });

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

watch(generatedCode, (newCode) => {
  if (cmInstance && cmInstance.getValue() !== newCode) {
    cmInstance.setValue(newCode);
  }
});

watch(() => props.isActive, (newVal) => {
  if (newVal && cmInstance) {
    nextTick(() => {
      cmInstance?.refresh();
    });
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
    <div class="header-section">
      <h4>Generated BUGS Code</h4>
    </div>
    <div class="editor-wrapper">
      <div ref="editorContainer" class="editor-container"></div>
      <BaseButton
        @click="copyCodeToClipboard"
        class="copy-button"
        type="secondary"
      >
        <i v-if="copySuccess" class="fas fa-check"></i>
        <i v-else class="fas fa-copy"></i>
      </BaseButton>
    </div>
  </div>
</template>

<style>
.code-preview-panel .CodeMirror,
.code-preview-panel .CodeMirror-scroll,
.code-preview-panel .CodeMirror-gutters,
.code-preview-panel .CodeMirror textarea,
.code-preview-panel .CodeMirror pre,
.code-preview-panel .CodeMirror-line,
.code-preview-panel .CodeMirror-code {
  cursor: not-allowed !important;
}

.code-preview-panel .CodeMirror-readonly .CodeMirror-cursors {
  display: none !important;
}

.code-preview-panel .CodeMirror-scroll {
  overflow: auto !important;
  white-space: pre !important;
}

.code-preview-panel .CodeMirror-simplescroll-horizontal div,
.code-preview-panel .CodeMirror-simplescroll-vertical div {
  background: #666;
  border-radius: 3px;
}

.code-preview-panel .CodeMirror-foldgutter-open,
.code-preview-panel .CodeMirror-foldgutter-folded {
  color: #999;
}
</style>

<style scoped>
.code-preview-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
}

.header-section {
  flex-shrink: 0;
}

h4 {
  margin: 0 0 10px;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.editor-wrapper {
  position: relative;
  flex-grow: 1;
  background-color: #282c34;
  border-radius: 8px;
  overflow: hidden;
}

.editor-container {
  width: 100%;
  height: 100%;
}

.copy-button {
  position: absolute;
  bottom: 12px;
  right: 12px;
  width: 36px;
  height: 36px;
  background-color: var(--color-secondary);
  color: #fff;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  cursor: pointer;
  opacity: 0.9;
  transition: background-color 0.2s, opacity 0.2s;
}

.copy-button:hover {
  background-color: var(--color-secondary-hover);
  opacity: 1;
}

.copy-button .fa-copy,
.copy-button .fa-check {
  font-size: 1.1rem;
}
</style>
