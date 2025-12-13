<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import BaseModal from '../common/BaseModal.vue'
import BaseInput from '../ui/BaseInput.vue'
import BaseButton from '../ui/BaseButton.vue'
import type { Project } from '../../stores/projectStore'

const props = defineProps<{
  isOpen: boolean
  url: string
  project?: Project | null
  currentGraphId?: string | null
}>()

const emit = defineEmits(['close', 'generate'])

type ShareScope = 'current' | 'project' | 'custom'

const activeTab = ref<ShareScope>('current')
const selectedGraphs = ref<Set<string>>(new Set())

const copySuccess = ref(false)
const shortUrl = ref<string | null>(null)
const isLoadingShort = ref(false)
const shortError = ref<string | null>(null)

// Track which history item shows the "Copied" state
const copiedHistoryIndex = ref<number | null>(null)

interface HistoryItem {
  shortUrl: string
  label: string
  timestamp: number
}

const urlHistory = ref<HistoryItem[]>([])

const projectGraphs = computed(() => props.project?.graphs || [])

// Load history from localStorage
const storedHistory = localStorage.getItem('doodlebugs-urlHistory')
if (storedHistory) {
  try {
    urlHistory.value = JSON.parse(storedHistory)
  } catch {
    urlHistory.value = []
  }
}

const saveHistory = () => {
  localStorage.setItem('doodlebugs-urlHistory', JSON.stringify(urlHistory.value))
}

const deleteHistoryItem = (index: number) => {
  urlHistory.value.splice(index, 1)
  saveHistory()
}

// Reset state when modal opens
watch(
  () => props.isOpen,
  (val) => {
    if (val) {
      activeTab.value = 'current'
      selectedGraphs.value = new Set()
      if (props.currentGraphId) {
        selectedGraphs.value.add(props.currentGraphId)
      }
      resetUrlState()
      triggerGeneration()
    }
  }
)

// Regenerate when tab changes
watch(activeTab, () => {
  resetUrlState()
  triggerGeneration()
})

const resetUrlState = () => {
  copySuccess.value = false
  shortUrl.value = null
  shortError.value = null
  isLoadingShort.value = false
  copiedHistoryIndex.value = null
}

const toggleGraphSelection = (id: string) => {
  if (selectedGraphs.value.has(id)) {
    selectedGraphs.value.delete(id)
  } else {
    selectedGraphs.value.add(id)
  }
  resetUrlState()
  triggerGeneration()
}

const triggerGeneration = () => {
  let ids: string[] = []

  if (activeTab.value === 'current') {
    if (props.currentGraphId) ids = [props.currentGraphId]
  } else if (activeTab.value === 'project') {
    ids = projectGraphs.value.map((g) => g.id)
  } else if (activeTab.value === 'custom') {
    ids = Array.from(selectedGraphs.value)
  }

  // Only generate if we have something to share
  if (ids.length > 0) {
    emit('generate', { scope: activeTab.value, selectedGraphIds: ids })
  }
}

const displayUrl = computed(() => shortUrl.value || props.url)

const copyToClipboard = async () => {
  if (!displayUrl.value) return
  await performCopy(displayUrl.value)
  copySuccess.value = true
  setTimeout(() => (copySuccess.value = false), 2000)
}

const copyHistoryItem = async (text: string, index: number) => {
  await performCopy(text)
  copiedHistoryIndex.value = index
  setTimeout(() => {
    if (copiedHistoryIndex.value === index) {
      copiedHistoryIndex.value = null
    }
  }, 2000)
}

const performCopy = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    const input = document.createElement('textarea')
    input.value = text
    document.body.appendChild(input)
    input.select()
    document.execCommand('copy')
    document.body.removeChild(input)
  }
}

const shortenUrl = async () => {
  if (shortUrl.value || !props.url) return

  isLoadingShort.value = true
  shortError.value = null

  try {
    const target = `https://is.gd/create.php?format=json&url=${encodeURIComponent(props.url)}`
    const proxy = `https://api.allorigins.win/get?url=${encodeURIComponent(target)}`

    const response = await fetch(proxy)
    if (!response.ok) throw new Error(`HTTP Error ${response.status}`)

    const proxyData = await response.json()

    if (proxyData.contents) {
      const data = JSON.parse(proxyData.contents)
      if (data.errorcode) throw new Error(data.errormessage || 'Unknown is.gd error')
      if (data.shorturl) {
        shortUrl.value = data.shorturl

        // Add to history
        let label = 'Shared Model'
        if (activeTab.value === 'current' && props.currentGraphId) {
          const g = projectGraphs.value.find((g) => g.id === props.currentGraphId)
          label = g ? g.name : 'Current Graph'
        } else if (activeTab.value === 'project' && props.project) {
          label = `Project: ${props.project.name}`
        } else if (activeTab.value === 'custom') {
          label = `Selection (${selectedGraphs.value.size} graphs)`
        }

        const newItem: HistoryItem = {
          shortUrl: data.shorturl,
          label,
          timestamp: Date.now(),
        }

        // Add to history (avoid duplicates, limit to 10)
        urlHistory.value = [
          newItem,
          ...urlHistory.value.filter((i) => i.shortUrl !== data.shorturl),
        ].slice(0, 10)
        saveHistory()
      } else {
        throw new Error('Invalid response from is.gd')
      }
    } else {
      throw new Error('Empty response from proxy')
    }
  } catch (e: unknown) {
    console.error('Shortening failed:', e)
    shortError.value = e instanceof Error ? e.message : String(e)
    if (shortError.value?.includes('Rate limit')) {
      shortError.value = 'Rate limit exceeded. Please try again later.'
    } else if (shortError.value?.includes('Failed to fetch') || shortError.value?.includes('414')) {
      shortError.value = 'URL is too long for the shortener service. Please use the Long URL.'
    }
  } finally {
    isLoadingShort.value = false
  }
}

const handleUrlFocus = (event: FocusEvent) => {
  ;(event.target as HTMLInputElement).select()
}
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>Share Model</h3>
    </template>
    <template #body>
      <div class="db-share-layout">
        <!-- Tab Navigation -->
        <div class="db-share-tabs">
          <button
            class="db-tab-btn"
            :class="{ 'db-active': activeTab === 'current' }"
            @click="activeTab = 'current'"
          >
            <i class="fas fa-file-alt"></i> Current Graph
          </button>
          <button
            class="db-tab-btn"
            :class="{ 'db-active': activeTab === 'project' }"
            @click="activeTab = 'project'"
          >
            <i class="fas fa-folder"></i> Whole Project
          </button>
          <button
            class="db-tab-btn"
            :class="{ 'db-active': activeTab === 'custom' }"
            @click="activeTab = 'custom'"
          >
            <i class="fas fa-check-square"></i> Select Graphs
          </button>
        </div>

        <!-- Custom Selection Area -->
        <div v-if="activeTab === 'custom'" class="db-selection-area">
          <div class="db-selection-header">Select graphs to include:</div>
          <div class="db-graph-list">
            <div v-for="graph in projectGraphs" :key="graph.id" class="db-graph-item">
              <label>
                <input
                  type="checkbox"
                  :checked="selectedGraphs.has(graph.id)"
                  @change="toggleGraphSelection(graph.id)"
                />
                <span class="db-graph-name">{{ graph.name }}</span>
              </label>
            </div>
          </div>
        </div>

        <div class="db-divider"></div>

        <!-- URL Result Area -->
        <div class="db-result-area">
          <div v-if="!url" class="db-empty-message">Select graphs to generate a link.</div>
          <template v-else>
            <label class="db-url-label">Share Link ({{ shortUrl ? 'Shortened' : 'Base64' }})</label>
            <div class="db-url-row">
              <BaseInput
                :model-value="displayUrl"
                readonly
                class="db-url-input"
                :class="{ 'db-is-short': !!shortUrl }"
                @focus="handleUrlFocus"
              />
              <BaseButton
                @click="copyToClipboard"
                type="primary"
                class="db-icon-only-btn"
                title="Copy to Clipboard"
              >
                <i :class="copySuccess ? 'fas fa-check' : 'fas fa-copy'"></i>
              </BaseButton>
            </div>

            <div class="db-actions-row">
              <BaseButton
                v-if="!shortUrl"
                @click="shortenUrl"
                type="secondary"
                size="small"
                :disabled="isLoadingShort"
                class="db-shorten-btn"
              >
                <i v-if="isLoadingShort" class="fas fa-spinner fa-spin"></i>
                <span v-else>Shorten URL (is.gd)</span>
              </BaseButton>

              <div v-if="shortError" class="db-error-msg">
                <i class="fas fa-exclamation-circle"></i> {{ shortError }}
              </div>
            </div>

            <div class="db-info-note">
              <i class="fas fa-info-circle"></i>
              <span
                >The model, data & inits are directly encoded as the base64 URL. Nothing is stored
                on our servers.</span
              >
            </div>

            <div class="db-disclaimer-box">
              <i class="fas fa-exclamation-triangle"></i>
              <small>
                <strong>Note:</strong>
                <a
                  href="https://is.gd"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="db-text-link"
                  >is.gd</a
                >
                is a third-party service. Please avoid generating short links excessively to prevent
                hitting rate limits. If generation fails, use the Long URL above.
              </small>
            </div>
          </template>
        </div>

        <!-- History Section -->
        <div v-if="urlHistory.length > 0" class="db-history-section">
          <div class="db-divider"></div>
          <div class="db-history-header">Recent Short Links</div>
          <div class="db-history-list">
            <div v-for="(item, index) in urlHistory" :key="item.shortUrl" class="db-history-item">
              <div class="db-history-info">
                <span class="db-history-label">{{ item.label }}</span>
                <a :href="item.shortUrl" target="_blank" class="db-history-link">{{
                  item.shortUrl
                }}</a>
              </div>
              <div class="db-history-actions">
                <button
                  @click="copyHistoryItem(item.shortUrl, index)"
                  class="db-icon-btn db-small"
                  :title="copiedHistoryIndex === index ? 'Copied' : 'Copy'"
                >
                  <i
                    :class="copiedHistoryIndex === index ? 'fas fa-check' : 'fas fa-copy'"
                    :style="{ color: copiedHistoryIndex === index ? 'var(--theme-success)' : '' }"
                  ></i>
                </button>
                <button
                  @click="deleteHistoryItem(index)"
                  class="db-icon-btn db-small db-danger"
                  title="Delete"
                >
                  <i class="fas fa-trash-alt"></i>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </BaseModal>
</template>

<style scoped>
.db-share-layout {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.db-share-tabs {
  display: flex;
  background-color: var(--theme-bg-hover);
  padding: 4px;
  border-radius: var(--radius-md);
  gap: 4px;
}

.db-tab-btn {
  flex: 1;
  border: none;
  background: transparent;
  padding: 8px;
  border-radius: var(--radius-sm);
  color: var(--theme-text-secondary);
  font-size: 0.9em;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

.db-tab-btn:hover {
  color: var(--theme-text-primary);
  background-color: rgba(0, 0, 0, 0.05);
}

.db-tab-btn.db-active {
  background-color: var(--theme-bg-panel);
  color: var(--theme-primary);
  box-shadow: var(--shadow-sm);
  font-weight: 600;
}

.db-selection-area {
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-md);
  padding: 10px;
  background-color: var(--theme-bg-canvas);
}

.db-selection-header {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--theme-text-secondary);
  margin-bottom: 8px;
}

.db-graph-list {
  max-height: 120px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.db-graph-item label {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  transition: background 0.2s;
}

.db-graph-item label:hover {
  background-color: var(--theme-bg-hover);
}

.db-divider {
  height: 1px;
  background-color: var(--theme-border);
  width: 100%;
}

.db-result-area {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.db-url-label {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--theme-text-secondary);
}

.db-url-row {
  display: flex;
  gap: 8px;
}

.db-url-input {
  flex-grow: 1;
  font-family: monospace;
  font-size: 0.85em;
}

.db-url-input.db-is-short {
  color: var(--theme-primary);
  font-weight: 600;
}

.db-icon-only-btn {
  width: 36px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}

.db-actions-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 32px;
}

.db-shorten-btn {
  min-width: 140px;
}

.db-error-msg {
  font-size: 0.8em;
  color: var(--theme-danger);
}

.db-info-note {
  font-size: 0.8em;
  color: var(--theme-text-muted);
  background-color: var(--theme-bg-hover);
  padding: 8px;
  border-radius: var(--radius-sm);
  display: flex;
  gap: 8px;
  align-items: flex-start;
  line-height: 1.4;
}

.db-disclaimer-box {
  display: flex;
  gap: 8px;
  align-items: flex-start;
  font-size: 0.8em;
  color: var(--theme-text-secondary);
  background-color: rgba(245, 158, 11, 0.1);
  padding: 8px;
  border-radius: var(--radius-sm);
}

.db-disclaimer-box i {
  color: var(--theme-warning);
  margin-top: 2px;
}

.db-text-link {
  color: var(--theme-primary);
  text-decoration: underline;
  font-weight: 500;
}

.db-text-link:hover {
  color: var(--theme-primary-hover);
}

.db-empty-message {
  text-align: center;
  color: var(--theme-text-secondary);
  font-style: italic;
  padding: 20px;
}

.db-history-section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.db-history-header {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--theme-text-secondary);
}

.db-history-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 150px;
  overflow-y: auto;
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-sm);
  padding: 4px;
}

.db-history-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 8px;
  background: var(--theme-bg-hover);
  border-radius: 4px;
  font-size: 0.85em;
}

.db-history-info {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.db-history-label {
  font-weight: 600;
  color: var(--theme-text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.db-history-link {
  color: var(--theme-primary);
  text-decoration: none;
  font-size: 0.9em;
}

.db-history-link:hover {
  text-decoration: underline;
}

.db-history-actions {
  display: flex;
  gap: 4px;
  margin-left: 8px;
}

.db-icon-btn.db-small {
  width: 24px;
  height: 24px;
  font-size: 12px;
  background: transparent;
  border: none;
  color: var(--theme-text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
}

.db-icon-btn.db-small:hover {
  background: rgba(0, 0, 0, 0.05);
  color: var(--theme-text-primary);
}

.db-icon-btn.db-small.db-danger:hover {
  color: var(--theme-danger);
  background: rgba(239, 68, 68, 0.1);
}
</style>
