<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, nextTick, computed } from 'vue';
import { useGraphStore } from '../../stores/graphStore';
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator';

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
  graphId?: string; // Optional: for multi-canvas code pop-outs
}>();

const graphStore = useGraphStore();

// Use a computed to get the correct elements (global current or specific graph)
const targetElements = computed(() => {
    if (props.graphId) {
        return graphStore.graphContents.get(props.graphId)?.elements || [];
    }
    return graphStore.currentGraphElements;
});

// useBugsCodeGenerator expects a Ref, computed fits
const { generatedCode } = useBugsCodeGenerator(targetElements);

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

const copyCodeToClipboard = async () => {
  const text = generatedCode.value;
  try {
    // Try modern API first
    await navigator.clipboard.writeText(text);
    triggerSuccess();
  } catch {
    // Fallback to legacy API (often needed on iOS/mobile)
    const textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.style.position = "fixed"; // avoid scrolling to bottom
    textArea.style.opacity = "0";
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    try {
      const successful = document.execCommand('copy');
      if (successful) {
        triggerSuccess();
      } else {
        console.error('Fallback copy failed.');
        alert('Failed to copy code to clipboard.');
      }
    } catch (e) {
      console.error('Copy failed', e);
      alert('Failed to copy code to clipboard.');
    } finally {
      document.body.removeChild(textArea);
    }
  }
};

const triggerSuccess = () => {
  copySuccess.value = true;
  setTimeout(() => {
    copySuccess.value = false;
  }, 2000);
};
</script>

<template>
  <div class="code-preview-panel">
    <div class="header-section">
      <h4>Generated BUGS Code</h4>
    </div>
    <div class="editor-wrapper">
      <div ref="editorContainer" class="editor-container"></div>
      <!-- Use native button for reliable touch events -->
      <button
        @click.stop="copyCodeToClipboard"
        class="native-copy-button"
        type="button"
        title="Copy Code"
      >
        <i v-if="copySuccess" class="fas fa-check"></i>
        <i v-else class="fas fa-copy"></i>
      </button>
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

.native-copy-button {
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
  z-index: 1000;
  pointer-events: auto;
  border: none;
  outline: none;
  box-shadow: 0 2px 5px rgba(0,0,0,0.2);
}

.native-copy-button:hover {
  background-color: var(--color-secondary-hover);
  opacity: 1;
}

.native-copy-button:active {
  transform: scale(0.95);
}

.native-copy-button .fa-copy,
.native-copy-button .fa-check {
  font-size: 1.1rem;
}
</style>
