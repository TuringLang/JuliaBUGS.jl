<script setup lang="ts">
import { ref, watch, computed, onMounted, onUnmounted, nextTick } from 'vue';
import { useGraphStore } from '../../stores/graphStore';
import { useGraphElements } from '../../composables/useGraphElements';
import type { GraphElement } from '../../types';
// These imports will now work because you installed the package via npm
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/material-darker.css';
import 'codemirror/mode/javascript/javascript.js';
import CodeMirror from 'codemirror';

// After running `npm i --save-dev @types/codemirror`, we can import its types
import type { Editor, TextMarker } from 'codemirror';

const graphStore = useGraphStore();
const { selectedElement } = useGraphElements();

const errorText = ref('');
const editorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
let isUpdatingFromSource = false; // A flag to prevent cyclical updates

const graphElements = computed(() => graphStore.currentGraphElements);
const protectedFields = ['id', 'type', 'nodeType', 'source', 'target', 'parent'];

/**
 * Marks protected fields in the editor as read-only.
 */
const markProtectedFields = () => {
  if (!cmInstance) return;
  
  // Clear previous marks
  cmInstance.getAllMarks().forEach((mark: TextMarker) => mark.clear());

  const text = cmInstance.getValue();
  const lines = text.split('\n');
  
  lines.forEach((line: string, index: number) => {
    const trimmedLine = line.trim();
    const keyMatch = trimmedLine.match(/"([^"]+)"\s*:/);
    if (keyMatch && protectedFields.includes(keyMatch[1])) {
      cmInstance?.markText(
        { line: index, ch: 0 },
        { line: index, ch: line.length },
        { readOnly: true, className: 'cm-protected' }
      );
    }
  });
};

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: "[]",
      mode: { name: "javascript", json: true },
      theme: 'material-darker',
      lineNumbers: true,
      tabSize: 2,
    });

    cmInstance.on('change', (instance: Editor) => {
      if (isUpdatingFromSource) return;
      handleJsonInput(instance.getValue());
    });

    // Initial population and marking
    const initialJson = JSON.stringify(graphElements.value, null, 2);
    isUpdatingFromSource = true;
    cmInstance.setValue(initialJson);
    markProtectedFields();
    isUpdatingFromSource = false;
  }
});

onUnmounted(() => {
  // Correctly clean up the CodeMirror instance
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
    // Check if the content is semantically the same, ignoring formatting
    if (JSON.stringify(JSON.parse(currentEditorValue)) === JSON.stringify(JSON.parse(newJsonString))) {
        return;
    }
  } catch (e) {
    // Fallback to string comparison if parsing fails
    if (currentEditorValue === newJsonString) {
        return;
    }
  }

  isUpdatingFromSource = true;
  cmInstance.setValue(newJsonString);
  markProtectedFields();
  isUpdatingFromSource = false;

}, { deep: true });

watch(selectedElement, async (newSelection) => {
  if (!newSelection || !cmInstance) return;

  await nextTick();

  const searchText = `"id": "${newSelection.id}"`;
  const cursor = (cmInstance as any).getSearchCursor(searchText);
  
  if (cursor.findNext()) {
    const from = cursor.from();
    const to = cursor.to();
    
    // Find the start and end of the JSON object
    const text = cmInstance.getValue();
    const objectStartIndex = text.lastIndexOf('{', cmInstance.indexFromPos(from));
    const objectEndIndex = text.indexOf('}', cmInstance.indexFromPos(to)) + 1;

    if (objectStartIndex !== -1 && objectEndIndex > objectStartIndex) {
      cmInstance.focus();
      cmInstance.setSelection(
        cmInstance.posFromIndex(objectStartIndex),
        cmInstance.posFromIndex(objectEndIndex)
      );
      cmInstance.scrollIntoView({
        from: cmInstance.posFromIndex(objectStartIndex),
        to: cmInstance.posFromIndex(objectEndIndex)
      }, 50); // 50px margin
    }
  }
});

const handleJsonInput = (value: string) => {
  try {
    const newElements: GraphElement[] = JSON.parse(value);
    if (!Array.isArray(newElements)) {
      throw new Error("JSON must be an array of graph elements.");
    }
    
    if (graphStore.currentGraphId) {
      // The sanitization logic is now handled by the read-only marks.
      // We directly update the store.
      graphStore.updateGraphElements(graphStore.currentGraphId, newElements);
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
        Edit the JSON below to see live updates on the canvas. Read-only fields are protected.
      </p>
    </div>

    <!-- This wrapper provides the border and rounded corners for the editor -->
    <div class="editor-wrapper">
      <div ref="editorContainer" class="json-editor-container"></div>
    </div>
    
    <!-- This new footer section will hold status text or error messages -->
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
/* Global styles for CodeMirror, not scoped */
.CodeMirror {
  height: 100%;
  font-family: 'Fira Code', 'Cascadia Code', monospace;
  font-size: 0.85em;
  border-radius: 8px; /* Ensure editor itself has rounded corners */
}
.cm-protected {
  background-color: rgba(255, 255, 255, 0.1);
  cursor: not-allowed;
  opacity: 0.7;
}
</style>

<style scoped>
.json-editor-panel {
  /* Add padding to create left/right margins */
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
  /* Add a border and rounded corners to the editor's container */
  border: 1px solid var(--color-border);
  border-radius: 8px;
  overflow: hidden; /* This is crucial for the border-radius to apply to the CodeMirror instance */
  display: flex; /* Helps the child container fill the space */
  position: relative;
}

.json-editor-container {
  flex-grow: 1;
  position: relative;
}

.footer-section {
  flex-shrink: 0;
  padding-top: 10px;
  height: 40px;
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
  white-space: pre-wrap;
  word-break: break-all;
  width: 100%;
}
</style>
