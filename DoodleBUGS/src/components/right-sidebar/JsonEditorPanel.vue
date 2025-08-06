<script setup lang="ts">
import { ref, watch, computed, onMounted, onUnmounted, nextTick } from 'vue';
import { useGraphStore } from '../../stores/graphStore';
import { useGraphElements } from '../../composables/useGraphElements';
import type { GraphElement } from '../../types';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/javascript/javascript.js';
import 'codemirror/addon/scroll/simplescrollbars.css';
import 'codemirror/addon/scroll/simplescrollbars.js';
import 'codemirror/addon/search/searchcursor.js';
import 'codemirror/addon/fold/foldgutter.css';
import 'codemirror/addon/fold/foldgutter.js';
import 'codemirror/addon/fold/brace-fold.js';

import CodeMirror from 'codemirror';
import type { Editor, TextMarker } from 'codemirror';

// Extend the CodeMirror type declarations to include custom methods.
declare module 'codemirror' {
  interface Editor {
    getSearchCursor(query: string, pos?: CodeMirror.Position | null, caseFold?: boolean): {
      findNext: () => boolean;
      findPrevious: () => boolean;
      from: () => CodeMirror.Position;
      to: () => CodeMirror.Position;
    };
    findMatchingBracket(pos: CodeMirror.Position, strict?: boolean): { to: CodeMirror.Position | null } | null;
  }
}

const props = defineProps<{
  isActive: boolean;
}>();

const graphStore = useGraphStore();
const { selectedElement } = useGraphElements();

const errorText = ref('');
const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
let isUpdatingFromSource = false;
let existingMarks: Set<TextMarker> = new Set();

const graphElements = computed(() => graphStore.currentGraphElements);
const protectedFields = ['id', 'type', 'nodeType', 'source', 'target', 'parent'];

const markProtectedFields = () => {
  if (!cmInstance) return;

  const text = cmInstance.getValue();
  const lines = text.split('\n');
  const newMarks: Set<TextMarker> = new Set();

  lines.forEach((line: string, index: number) => {
    const trimmedLine = line.trim();
    const keyMatch = trimmedLine.match(/"([^"]+)"\s*:/);
    if (keyMatch && protectedFields.includes(keyMatch[1])) {
      const mark = cmInstance?.markText(
        { line: index, ch: 0 },
        { line: index, ch: line.length },
        { readOnly: true, className: 'cm-protected' }
      );
      if (mark) newMarks.add(mark);
    }
  });

  existingMarks.forEach((mark) => {
    if (!newMarks.has(mark)) {
      mark.clear();
    }
  });

  existingMarks = newMarks;
};

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: "[]",
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
      handleJsonInput(instance.getValue());
    });
    const initialJson = JSON.stringify(graphElements.value, null, 2);
    isUpdatingFromSource = true;
    cmInstance.setValue(initialJson);
    markProtectedFields();
    isUpdatingFromSource = false;

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

watch(graphElements, (newElements) => {
  if (!cmInstance) return;
  const currentEditorValue = cmInstance.getValue();
  const newJsonString = JSON.stringify(newElements, null, 2);
  try {
    if (JSON.stringify(JSON.parse(currentEditorValue)) === JSON.stringify(JSON.parse(newJsonString))) {
        return;
    }
  } catch {
    if (currentEditorValue === newJsonString) {
        return;
    }
  }
  isUpdatingFromSource = true;
  cmInstance.setValue(newJsonString);
  markProtectedFields();
  isUpdatingFromSource = false;
}, { deep: true });

watch(() => props.isActive, (newVal) => {
  if (newVal && cmInstance) {
    nextTick(() => {
      cmInstance?.refresh();
    });
  }
});

watch(selectedElement, async (newSelection) => {
  if (!newSelection || !cmInstance) return;
  await nextTick();
  if (!cmInstance) return;
  
  const searchText = `"id": "${newSelection.id}"`;
  const idCursor = cmInstance.getSearchCursor(searchText);

  if (idCursor.findNext()) {
    const idPosition = idCursor.from();
    const objectStartCursor = cmInstance.getSearchCursor('{', idPosition);
    
    if (objectStartCursor.findPrevious()) {
        const fromPos = objectStartCursor.from();
        const foldRange = cmInstance.findMatchingBracket(fromPos, false);

        if (foldRange?.to) {
            const toPos = { line: foldRange.to.line, ch: foldRange.to.ch + 1 };

            cmInstance.focus();
            cmInstance.setSelection(fromPos, toPos);
            cmInstance.scrollIntoView({ from: fromPos, to: toPos }, 50);
        }
    }
  }
});

const handleJsonInput = (value: string) => {
  try {
    const newElements: GraphElement[] = JSON.parse(value);
    if (!Array.isArray(newElements)) {
      throw new Error("Invalid format: The root element must be an array of graph objects.");
    }
    if (graphStore.currentGraphId) {
      graphStore.updateGraphElements(graphStore.currentGraphId, newElements);
    }
    errorText.value = '';
  } catch (e: unknown) {
    errorText.value = (e as Error).message;
  }
};
</script>

<template>
  <div class="json-editor-panel">
    <div class="header-section">
      <h4>Live Graph JSON</h4>
      <p class="description">
        Edit the JSON below to see live updates on the canvas. Read-only fields are protected.
      </p>
    </div>
    <div class="editor-wrapper">
      <div ref="editorContainer" class="json-editor-container"></div>
    </div>
    <div class="footer-section">
      <div v-if="errorText" class="error-message">
        {{ errorText }}
      </div>
      <span v-else class="status-text">
        <i class="fas fa-check-circle"></i> Live Sync Enabled
      </span>
    </div>
  </div>
</template>

<style>
.CodeMirror {
  height: 100%;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.85em;
  border-radius: 8px;
}
.cm-protected {
  background-color: rgba(255, 255, 255, 0.1);
  cursor: not-allowed;
  opacity: 0.7;
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
.json-editor-panel {
  padding: 15px;
  display: flex;
  flex-direction: column;
  height: 100%;
  box-sizing: border-box;
}

.header-section {
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

.editor-wrapper {
  flex-grow: 1;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  display: flex;
  position: relative;
  min-height: 0;
}

.json-editor-container {
  flex-grow: 1;
  position: relative;
  overflow-x: auto;
}

.footer-section {
  flex-shrink: 0;
  padding-top: 10px;
  min-height: 40px;
  height: auto;
  box-sizing: border-box;
  display: flex;
  align-items: center;
}

.status-text {
  font-size: 0.8em;
  color: var(--color-success);
  font-weight: 500;
  display: flex;
  align-items: center;
  gap: 5px;
}

.error-message {
  color: var(--color-danger);
  background-color: #ffe0e0;
  border: 1px solid var(--color-danger);
  border-radius: 4px;
  padding: 5px 10px;
  font-size: 0.8em;
  white-space: normal;
  word-break: break-word;
  width: 100%;
}
</style>
