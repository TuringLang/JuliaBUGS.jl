<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted, nextTick, computed } from 'vue'
import { useGraphStore } from '../../stores/graphStore'
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator'
import { useStanCodeGenerator } from '../../composables/useStanCodeGenerator'

import 'codemirror/lib/codemirror.css'
import 'codemirror/theme/material-darker.css'
import 'codemirror/mode/julia/julia.js'
import 'codemirror/mode/clike/clike.js'
import 'codemirror/addon/scroll/simplescrollbars.css'
import 'codemirror/addon/scroll/simplescrollbars.js'
import 'codemirror/addon/fold/foldgutter.css'
import 'codemirror/addon/fold/foldgutter.js'
import 'codemirror/addon/fold/brace-fold.js'

import CodeMirror from 'codemirror'
import type { Editor } from 'codemirror'

export type CodeLanguage = 'bugs' | 'stan'

const props = defineProps<{
  isActive: boolean
  graphId?: string
  code?: string
  language?: CodeLanguage
}>()

const emit = defineEmits<{
  (e: 'update:language', lang: CodeLanguage): void
}>()

const graphStore = useGraphStore()
const activeLanguage = ref<CodeLanguage>(props.language ?? 'bugs')

watch(
  () => props.language,
  (val) => {
    if (val && val !== activeLanguage.value) activeLanguage.value = val
  }
)

const targetElements = computed(() => {
  if (props.code !== undefined) return []
  if (props.graphId) {
    return graphStore.graphContents.get(props.graphId)?.elements || []
  }
  return graphStore.currentGraphElements
})

const { generatedCode: bugsCode } = useBugsCodeGenerator(targetElements)
const { generatedStanCode: stanCode } = useStanCodeGenerator(targetElements)

const generatedCode = computed(() => {
  if (props.code !== undefined) return props.code
  return activeLanguage.value === 'stan' ? stanCode.value : bugsCode.value
})

const toggleLanguage = () => {
  activeLanguage.value = activeLanguage.value === 'bugs' ? 'stan' : 'bugs'
  emit('update:language', activeLanguage.value)
}

const copySuccess = ref(false)
const editorContainer = ref<HTMLDivElement | null>(null)
let cmInstance: Editor | null = null

const cmMode = computed(() => (activeLanguage.value === 'stan' ? 'text/x-c++src' : 'julia'))

onMounted(() => {
  if (editorContainer.value) {
    cmInstance = CodeMirror(editorContainer.value, {
      value: generatedCode.value,
      mode: cmMode.value,
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

watch(cmMode, (newMode) => {
  if (cmInstance) {
    cmInstance.setOption('mode', newMode)
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
      <div class="db-cp-controls">
        <div class="db-cp-lang-toggle" v-if="!code">
          <button
            :class="{ 'db-active': activeLanguage === 'bugs' }"
            @click.stop="activeLanguage !== 'bugs' && toggleLanguage()"
            type="button"
          >
            BUGS
          </button>
          <button
            :class="{ 'db-active': activeLanguage === 'stan' }"
            @click.stop="activeLanguage !== 'stan' && toggleLanguage()"
            type="button"
          >
            Stan
          </button>
        </div>
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

.db-cp-controls {
  position: absolute;
  bottom: 10px;
  right: 10px;
  display: flex;
  align-items: center;
  gap: 8px;
  z-index: 1000;
}

.db-cp-lang-toggle {
  display: flex;
  border-radius: 6px;
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.2);
}

.db-cp-lang-toggle button {
  background-color: rgba(255, 255, 255, 0.08);
  color: rgba(255, 255, 255, 0.5);
  border: none;
  padding: 4px 10px;
  font-size: 0.7rem;
  font-weight: 600;
  cursor: pointer;
  transition:
    background-color 0.2s,
    color 0.2s;
  outline: none;
  letter-spacing: 0.5px;
}

.db-cp-lang-toggle button.db-active {
  background-color: rgba(255, 255, 255, 0.2);
  color: #fff;
}

.db-cp-lang-toggle button:hover:not(.db-active) {
  background-color: rgba(255, 255, 255, 0.12);
  color: rgba(255, 255, 255, 0.8);
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
