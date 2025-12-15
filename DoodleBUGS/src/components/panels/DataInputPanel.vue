<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useDataStore } from '../../stores/dataStore'
import 'codemirror/lib/codemirror.css'
import 'codemirror/theme/material-darker.css'
import 'codemirror/mode/javascript/javascript.js'
import 'codemirror/addon/scroll/simplescrollbars.css'
import 'codemirror/addon/scroll/simplescrollbars.js'
import 'codemirror/addon/fold/foldgutter.css'
import 'codemirror/addon/fold/foldgutter.js'
import 'codemirror/addon/fold/brace-fold.js'
import 'codemirror/addon/edit/matchbrackets.js'
import CodeMirror from 'codemirror'
import type { Editor } from 'codemirror'

const props = defineProps<{
  isActive: boolean
}>()

const dataStore = useDataStore()
const editorContainer = ref<HTMLDivElement | null>(null)

let cm: Editor | null = null
let isUpdatingFromSource = false
let resizeObserver: ResizeObserver | null = null

const jsonError = ref<string | null>(null)

const validateJson = (jsonString: string) => {
  try {
    JSON.parse(jsonString)
    jsonError.value = null
  } catch (e: unknown) {
    jsonError.value = e instanceof Error ? e.message : String(e)
  }
}

const setupCodeMirror = () => {
  if (cm) {
    const wrapper = cm.getWrapperElement()
    wrapper.parentNode?.removeChild(wrapper)
    cm = null
  }

  nextTick(() => {
    if (editorContainer.value) {
      cm = CodeMirror(editorContainer.value, {
        value: dataStore.dataContent,
        mode: { name: 'javascript', json: true },
        theme: 'material-darker',
        lineNumbers: true,
        tabSize: 2,
        scrollbarStyle: 'simple',
        lineWrapping: false,
        foldGutter: true,
        gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter'],
        matchBrackets: true,
      })

      cm.on('change', (instance) => {
        if (isUpdatingFromSource) return
        const val = instance.getValue()
        dataStore.dataContent = val
        validateJson(val)
      })
    }
  })
}

onMounted(() => {
  setupCodeMirror()

  if (editorContainer.value) {
    resizeObserver = new ResizeObserver(() => {
      if (cm) cm.refresh()
    })
    resizeObserver.observe(editorContainer.value)
  }
})

onUnmounted(() => {
  if (cm) {
    const wrapper = cm.getWrapperElement()
    wrapper.parentNode?.removeChild(wrapper)
  }
  if (resizeObserver) {
    resizeObserver.disconnect()
  }
})

watch(
  () => dataStore.dataContent,
  (newValue) => {
    if (!cm) return
    if (cm.getValue() !== newValue) {
      isUpdatingFromSource = true
      cm.setValue(newValue)
      validateJson(newValue)
      isUpdatingFromSource = false
    }
  }
)

watch(
  () => props.isActive,
  (newVal) => {
    if (newVal) {
      nextTick(() => {
        cm?.refresh()
      })
    }
  }
)
</script>

<template>
  <div class="db-data-input-panel">
    <!-- Status Header -->
    <div v-if="jsonError" class="db-di-status-header db-error">
      <div class="db-status-row">
        <i class="fas fa-times-circle"></i>
        <span class="db-status-label">Invalid JSON</span>
      </div>
      <div class="db-error-msg">{{ jsonError }}</div>
    </div>
    <div v-else class="db-di-status-header db-success">
      <i class="fas fa-check-circle"></i>
      <span class="db-status-label">Valid JSON</span>
    </div>

    <!-- Editor Wrapper -->
    <div class="db-di-wrapper flex-grow">
      <div ref="editorContainer" class="db-di-container"></div>
    </div>
  </div>
</template>

<style scoped>
.db-data-input-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 0;
  background-color: #282c34;
}

.db-di-status-header {
  flex-shrink: 0;
  padding: 6px 10px;
  font-size: 0.85em;
  display: flex;
  flex-direction: column;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

.db-di-status-header.db-success {
  background-color: transparent;
  color: var(--color-success);
  flex-direction: row;
  align-items: center;
  gap: 6px;
  padding: 8px 10px;
}

.db-di-status-header.db-error {
  background-color: rgba(239, 68, 68, 0.2);
  color: #fca5a5;
  border-bottom: 1px solid rgba(239, 68, 68, 0.4);
}

.db-status-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
}

.db-status-label {
  font-weight: 600;
}

.db-error-msg {
  margin-top: 4px;
  padding-left: 20px; /* Indent to align under icon roughly */
  font-family: monospace;
  font-size: 0.9em;
  white-space: pre-wrap;
  word-break: break-all;
  color: #fff;
  opacity: 0.9;
}

.db-di-wrapper {
  flex: 1;
  position: relative;
  min-height: 0;
}

.db-di-container {
  flex-grow: 1;
  position: relative;
  overflow: hidden;
  height: 100%;
}

/* Scrollbar hiding logic */
:deep(.CodeMirror) {
  height: 100%;
  font-family: monospace;
  font-size: 0.85em;
}

:deep(.CodeMirror-scroll) {
  scrollbar-width: none; /* Firefox */
  -ms-overflow-style: none; /* IE/Edge */
}

:deep(.CodeMirror-scroll::-webkit-scrollbar) {
  display: none; /* Chrome/Safari/Webkit */
}

/* Hide CodeMirror specific simple scrollbars */
:deep(.CodeMirror-simplescroll-horizontal),
:deep(.CodeMirror-simplescroll-vertical) {
  display: none !important;
}
</style>
