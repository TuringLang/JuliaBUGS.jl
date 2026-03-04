<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick, computed } from 'vue'
import { useScriptStore } from '../../stores/scriptStore'
import { useDataStore } from '../../stores/dataStore'
import { useGraphStore } from '../../stores/graphStore'
import { storeToRefs } from 'pinia'
import 'codemirror/lib/codemirror.css'
import 'codemirror/theme/material-darker.css'
import 'codemirror/mode/julia/julia.js'
import 'codemirror/mode/python/python.js'
import 'codemirror/addon/scroll/simplescrollbars.css'
import 'codemirror/addon/scroll/simplescrollbars.js'
import CodeMirror from 'codemirror'
import type { Editor } from 'codemirror'
import BaseButton from '../ui/BaseButton.vue'
import {
  generateStanDataJson,
  generateStanInitsJson,
  extractCensoredFields,
} from '../../composables/useStanCodeGenerator'

export type ScriptLanguage = 'julia' | 'stan'

const props = defineProps<{
  isActive: boolean
}>()

defineEmits<{
  (e: 'open-settings'): void
  (e: 'download'): void
  (e: 'download-stan-script'): void
  (e: 'download-stan-data'): void
  (e: 'download-stan-inits'): void
  (e: 'generate'): void
}>()

const scriptStore = useScriptStore()
const dataStore = useDataStore()
const graphStore = useGraphStore()
const { standaloneScript, standaloneStanScript } = storeToRefs(scriptStore)

const activeScriptLang = ref<ScriptLanguage>('julia')

const hasAnyScript = computed(() => !!standaloneScript.value || !!standaloneStanScript.value)
const currentLangHasScript = computed(() =>
  activeScriptLang.value === 'stan' ? !!standaloneStanScript.value : !!standaloneScript.value
)
const activeScriptContent = computed(() =>
  activeScriptLang.value === 'stan' ? standaloneStanScript.value : standaloneScript.value
)

const stanDataJson = computed(() => {
  const data = dataStore.parsedGraphData?.data || {}
  const censoredFields = extractCensoredFields(graphStore.currentGraphElements)
  return generateStanDataJson(data, censoredFields)
})

const stanInitsJson = computed(() => {
  const inits = dataStore.parsedGraphData?.inits || {}
  return generateStanInitsJson(inits)
})

const showDataPreview = ref(false)
const showInitsPreview = ref(false)
const dataCopySuccess = ref(false)
const initsCopySuccess = ref(false)

const juliaEditorContainer = ref<HTMLDivElement | null>(null)
const stanEditorContainer = ref<HTMLDivElement | null>(null)
let juliaEditorInstance: Editor | null = null
let stanEditorInstance: Editor | null = null
const copySuccess = ref(false)

const initJuliaEditor = () => {
  if (!juliaEditorContainer.value) return
  if (juliaEditorInstance) {
    juliaEditorInstance.setValue(standaloneScript.value)
    return
  }
  juliaEditorInstance = CodeMirror(juliaEditorContainer.value, {
    value: standaloneScript.value,
    mode: 'julia',
    theme: 'material-darker',
    lineNumbers: true,
    readOnly: true,
    tabSize: 2,
    scrollbarStyle: 'simple',
    lineWrapping: false,
  })
}

const initStanEditor = () => {
  if (!stanEditorContainer.value) return
  if (stanEditorInstance) {
    stanEditorInstance.setValue(standaloneStanScript.value)
    return
  }
  stanEditorInstance = CodeMirror(stanEditorContainer.value, {
    value: standaloneStanScript.value,
    mode: 'python',
    theme: 'material-darker',
    lineNumbers: true,
    readOnly: true,
    tabSize: 4,
    scrollbarStyle: 'simple',
    lineWrapping: false,
  })
}

onMounted(() => {
  if (juliaEditorContainer.value && standaloneScript.value) initJuliaEditor()
  if (stanEditorContainer.value && standaloneStanScript.value) initStanEditor()
})

onUnmounted(() => {
  if (juliaEditorInstance) {
    const wrapper = juliaEditorInstance.getWrapperElement()
    wrapper.parentNode?.removeChild(wrapper)
    juliaEditorInstance = null
  }
  if (stanEditorInstance) {
    const wrapper = stanEditorInstance.getWrapperElement()
    wrapper.parentNode?.removeChild(wrapper)
    stanEditorInstance = null
  }
})

watch(standaloneScript, (newValue) => {
  if (newValue) {
    nextTick(() => {
      if (!juliaEditorInstance && juliaEditorContainer.value) initJuliaEditor()
      if (juliaEditorInstance && juliaEditorInstance.getValue() !== newValue) {
        juliaEditorInstance.setValue(newValue)
      }
    })
  }
})

watch(standaloneStanScript, (newValue) => {
  if (newValue) {
    nextTick(() => {
      if (!stanEditorInstance && stanEditorContainer.value) initStanEditor()
      if (stanEditorInstance && stanEditorInstance.getValue() !== newValue) {
        stanEditorInstance.setValue(newValue)
      }
    })
  }
})

watch(
  () => props.isActive,
  (newVal) => {
    if (newVal) {
      nextTick(() => {
        juliaEditorInstance?.refresh()
        stanEditorInstance?.refresh()
      })
    }
  }
)

watch(activeScriptLang, () => {
  nextTick(() => {
    if (activeScriptLang.value === 'julia') {
      if (!juliaEditorInstance && juliaEditorContainer.value && standaloneScript.value)
        initJuliaEditor()
      juliaEditorInstance?.refresh()
    } else {
      if (!stanEditorInstance && stanEditorContainer.value && standaloneStanScript.value)
        initStanEditor()
      stanEditorInstance?.refresh()
    }
  })
})

const copyToClipboard = async (text: string, successRef: typeof copySuccess) => {
  try {
    await navigator.clipboard.writeText(text)
    successRef.value = true
    setTimeout(() => (successRef.value = false), 2000)
  } catch {
    const textArea = document.createElement('textarea')
    textArea.value = text
    textArea.style.position = 'fixed'
    textArea.style.opacity = '0'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()
    try {
      document.execCommand('copy')
      successRef.value = true
      setTimeout(() => (successRef.value = false), 2000)
    } catch (e) {
      console.error(e)
    }
    document.body.removeChild(textArea)
  }
}

const copyScript = () => copyToClipboard(activeScriptContent.value, copySuccess)
const copyDataJson = () => copyToClipboard(stanDataJson.value, dataCopySuccess)
const copyInitsJson = () => copyToClipboard(stanInitsJson.value, initsCopySuccess)
</script>

<template>
  <div class="db-local-script-panel">
    <div v-if="!hasAnyScript" class="db-ls-empty-state">
      <p>No script generated yet.</p>
      <BaseButton type="primary" @click="$emit('generate')">Generate Scripts</BaseButton>
    </div>
    <div v-else class="db-ls-panel-container">
      <div class="db-ls-panel-header">
        <div class="db-ls-lang-toggle">
          <button
            class="db-ls-lang-btn"
            :class="{ active: activeScriptLang === 'julia' }"
            @click="activeScriptLang = 'julia'"
          >
            Julia
          </button>
          <button
            class="db-ls-lang-btn"
            :class="{ active: activeScriptLang === 'stan' }"
            @click="activeScriptLang = 'stan'"
          >
            Stan (Python)
          </button>
        </div>
        <div class="db-ls-actions">
          <button
            @click="$emit('open-settings')"
            title="Script Configuration"
            class="db-ls-action-btn"
          >
            <i class="fas fa-cog"></i>
          </button>
          <button
            v-if="activeScriptLang === 'julia' && standaloneScript"
            @click="$emit('download')"
            title="Download Julia Script"
            class="db-ls-action-btn"
          >
            <i class="fas fa-download"></i>
          </button>
          <button
            v-if="activeScriptLang === 'stan' && standaloneStanScript"
            @click="$emit('download-stan-script')"
            title="Download Stan Script"
            class="db-ls-action-btn"
          >
            <i class="fas fa-download"></i>
          </button>
          <button @click="$emit('generate')" title="Regenerate Scripts" class="db-ls-action-btn">
            <i class="fas fa-sync-alt"></i>
          </button>
        </div>
      </div>

      <div v-if="!currentLangHasScript" class="db-ls-empty-state db-ls-lang-empty">
        <p>{{ activeScriptLang === 'stan' ? 'Stan script' : 'Julia script' }} not generated yet.</p>
        <BaseButton type="primary" @click="$emit('generate')">Generate Scripts</BaseButton>
      </div>

      <template v-else>
        <div v-if="activeScriptLang === 'stan'" class="db-ls-stan-data-section">
          <div class="db-ls-data-row">
            <button class="db-ls-data-toggle" @click="showDataPreview = !showDataPreview">
              <i :class="showDataPreview ? 'fas fa-chevron-down' : 'fas fa-chevron-right'"></i>
              <span>data.json</span>
            </button>
            <div class="db-ls-data-row-actions">
              <button class="db-ls-action-btn" title="Copy data.json" @click="copyDataJson">
                <i :class="dataCopySuccess ? 'fas fa-check' : 'fas fa-copy'"></i>
              </button>
              <button
                class="db-ls-action-btn"
                title="Download data.json"
                @click="$emit('download-stan-data')"
              >
                <i class="fas fa-download"></i>
              </button>
            </div>
          </div>
          <div v-if="showDataPreview" class="db-ls-json-preview">
            <pre>{{ stanDataJson }}</pre>
          </div>

          <div class="db-ls-data-row">
            <button class="db-ls-data-toggle" @click="showInitsPreview = !showInitsPreview">
              <i :class="showInitsPreview ? 'fas fa-chevron-down' : 'fas fa-chevron-right'"></i>
              <span>inits.json</span>
            </button>
            <div class="db-ls-data-row-actions">
              <button class="db-ls-action-btn" title="Copy inits.json" @click="copyInitsJson">
                <i :class="initsCopySuccess ? 'fas fa-check' : 'fas fa-copy'"></i>
              </button>
              <button
                class="db-ls-action-btn"
                title="Download inits.json"
                @click="$emit('download-stan-inits')"
              >
                <i class="fas fa-download"></i>
              </button>
            </div>
          </div>
          <div v-if="showInitsPreview" class="db-ls-json-preview">
            <pre>{{ stanInitsJson }}</pre>
          </div>
        </div>

        <div class="db-ls-editor-wrapper">
          <div
            v-show="activeScriptLang === 'julia'"
            ref="juliaEditorContainer"
            class="db-ls-editor-container"
          ></div>
          <div
            v-show="activeScriptLang === 'stan'"
            ref="stanEditorContainer"
            class="db-ls-editor-container"
          ></div>
          <button
            v-if="activeScriptContent"
            @click.stop="copyScript"
            class="db-ls-copy-btn"
            type="button"
            title="Copy Script"
          >
            <i v-if="copySuccess" class="fas fa-check"></i>
            <i v-else class="fas fa-copy"></i>
          </button>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.db-local-script-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: 0;
  box-sizing: border-box;
}

.db-ls-empty-state {
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

.db-ls-lang-empty {
  flex-grow: 0;
  padding: 30px 20px;
}

.db-ls-panel-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: 10px;
  gap: 10px;
}

.db-ls-panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--color-border);
}

.db-ls-lang-toggle {
  display: flex;
  gap: 0;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  overflow: hidden;
}

.db-ls-lang-btn {
  padding: 3px 10px;
  font-size: 0.78em;
  font-weight: 600;
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  transition: all 0.15s;
}

.db-ls-lang-btn.active {
  background: var(--db-accent-color, #5b8fd9);
  color: #fff;
}

.db-ls-lang-btn:not(.active):hover {
  background: var(--color-bg-hover, rgba(91, 143, 217, 0.1));
}

.db-ls-actions {
  display: flex;
  gap: 8px;
}

.db-ls-action-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  font-size: 14px;
  padding: 4px;
  transition: color 0.2s;
}

.db-ls-action-btn:hover {
  color: var(--theme-text-primary);
}

.db-ls-stan-data-section {
  display: flex;
  flex-direction: column;
  gap: 2px;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  overflow: hidden;
}

.db-ls-data-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 8px;
  background: var(--color-bg-secondary, rgba(0, 0, 0, 0.1));
}

.db-ls-data-toggle {
  display: flex;
  align-items: center;
  gap: 6px;
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--theme-text-primary);
  font-size: 0.82em;
  font-weight: 600;
  padding: 2px 0;
}

.db-ls-data-toggle:hover {
  color: var(--db-accent-color, #5b8fd9);
}

.db-ls-data-toggle i {
  font-size: 0.7em;
  width: 10px;
}

.db-ls-data-row-actions {
  display: flex;
  gap: 4px;
}

.db-ls-json-preview {
  max-height: 180px;
  overflow: auto;
  background: #1e2127;
  border-top: 1px solid var(--color-border);
}

.db-ls-json-preview pre {
  margin: 0;
  padding: 8px;
  font-family: monospace;
  font-size: 0.78em;
  color: #abb2bf;
  white-space: pre-wrap;
  word-break: break-all;
}

.db-ls-editor-wrapper {
  flex-grow: 1;
  background-color: #282c34;
  border-radius: 4px;
  position: relative;
  overflow: hidden;
  min-height: 0;
}

.db-ls-editor-container {
  height: 100%;
}

:deep(.CodeMirror) {
  height: 100%;
  font-family: monospace;
  font-size: 0.85em;
}

.db-ls-copy-btn {
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
  transition:
    background-color 0.2s,
    opacity 0.2s;
  z-index: 1000;
  pointer-events: auto;
  border: none;
  outline: none;
}

.db-ls-copy-btn:hover {
  background-color: transparent;
  opacity: 1;
}

.db-ls-copy-btn:active {
  transform: scale(0.95);
}

.db-ls-copy-btn .fa-copy,
.db-ls-copy-btn .fa-check {
  font-size: 1rem;
}
</style>
