<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, nextTick, computed } from 'vue'
import { useGraphStore } from '../../stores/graphStore'
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator'

import 'codemirror/lib/codemirror.css'
import 'codemirror/theme/material-darker.css'
import 'codemirror/mode/julia/julia.js'
import 'codemirror/addon/scroll/simplescrollbars.css'
import 'codemirror/addon/scroll/simplescrollbars.js'
import 'codemirror/addon/fold/foldgutter.css'
import 'codemirror/addon/fold/foldgutter.js'
import 'codemirror/addon/fold/brace-fold.js'

import CodeMirror from 'codemirror'
import type { Editor } from 'codemirror'

const props = defineProps<{
  isActive: boolean
  graphId?: string
}>()

const graphStore = useGraphStore()

const targetElements = computed(() => {
  if (props.graphId) {
    return graphStore.graphContents.get(props.graphId)?.elements || []
  }
  return graphStore.currentGraphElements
})

const { generatedCode } = useBugsCodeGenerator(targetElements)

const copySuccess = ref(false)
const editorContainer = ref<HTMLDivElement | null>(null)
let cmInstance: Editor | null = null

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: generatedCode.value,
      mode: 'julia',
      theme: 'material-darker',
      lineNumbers: true,
      readOnly: true,
      tabSize: 2,
      scrollbarStyle: 'simple',
      foldGutter: true,
      gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter'],
    })

    if (props.isActive) {
      nextTick(() => cmInstance?.refresh())
    }
  }
})

onUnmounted(() => {
  if (cmInstance) {
    const editorElement = cmInstance.getWrapperElement()
    editorElement.parentNode?.removeChild(editorElement)
    cmInstance = null
  }
})

watch(generatedCode, (newCode) => {
  if (cmInstance && cmInstance.getValue() !== newCode) {
    cmInstance.setValue(newCode)
  }
})

watch(
  () => props.isActive,
  (newVal) => {
    if (newVal && cmInstance) {
      nextTick(() => {
        cmInstance?.refresh()
      })
    }
  }
)

const copyCodeToClipboard = async () => {
  const text = generatedCode.value
  try {
    await navigator.clipboard.writeText(text)
    triggerSuccess()
  } catch {
    const textArea = document.createElement('textarea')
    textArea.value = text
    textArea.style.position = 'fixed'
    textArea.style.opacity = '0'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()
    try {
      const successful = document.execCommand('copy')
      if (successful) {
        triggerSuccess()
      } else {
        console.error('Fallback copy failed.')
        alert('Failed to copy code to clipboard.')
      }
    } catch (e) {
      console.error('Copy failed', e)
      alert('Failed to copy code to clipboard.')
    } finally {
      document.body.removeChild(textArea)
    }
  }
}

const triggerSuccess = () => {
  copySuccess.value = true
  setTimeout(() => {
    copySuccess.value = false
  }, 2000)
}
</script>

<template>
  <div class="db-code-preview-panel">
    <div class="db-cp-wrapper">
      <div ref="editorContainer" class="db-cp-container"></div>
      <button
        @click.stop="copyCodeToClipboard"
        class="db-cp-copy-btn"
        type="button"
        title="Copy Code"
      >
        <i v-if="copySuccess" class="fas fa-check"></i>
        <i v-else class="fas fa-copy"></i>
      </button>
    </div>
  </div>
</template>

<style scoped>
.db-code-preview-panel {
  padding: 0; /* Removed padding */
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
}

.db-cp-wrapper {
  position: relative;
  flex-grow: 1;
  background-color: #282c34;
  overflow: hidden;
  height: 100%;
}

.db-cp-container {
  width: 100%;
  height: 100%;
}

.db-cp-copy-btn {
  position: absolute;
  bottom: 10px;
  right: 10px;
  width: 36px;
  height: 36px;
  background-color: rgba(255, 255, 255, 0.1);
  color: #fff;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  cursor: pointer;
  opacity: 0.7;
  transition:
    background-color 0.2s,
    opacity 0.2s;
  z-index: 1000;
  pointer-events: auto;
  border: 1px solid rgba(255, 255, 255, 0.2);
  outline: none;
}

.db-cp-copy-btn:hover {
  background-color: rgba(255, 255, 255, 0.2);
  opacity: 1;
}

.db-cp-copy-btn:active {
  transform: scale(0.95);
}

.db-cp-copy-btn .fa-copy,
.db-cp-copy-btn .fa-check {
  font-size: 1rem;
}

/* Scrollbar hiding logic */
:deep(.CodeMirror) {
  height: 100%;
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
