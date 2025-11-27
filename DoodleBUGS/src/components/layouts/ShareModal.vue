<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
import type { Project } from '../../stores/projectStore';

const props = defineProps<{
  isOpen: boolean;
  url: string;
  project?: Project | null;
  currentGraphId?: string | null;
}>();

const emit = defineEmits(['close', 'generate']);

type ShareScope = 'current' | 'project' | 'custom';

const activeTab = ref<ShareScope>('current');
const selectedGraphs = ref<Set<string>>(new Set());

const copySuccess = ref(false);
const shortUrl = ref<string | null>(null);
const isLoadingShort = ref(false);
const shortError = ref<string | null>(null);

const projectGraphs = computed(() => props.project?.graphs || []);

// Reset state when modal opens
watch(() => props.isOpen, (val) => {
    if (val) {
        activeTab.value = 'current';
        selectedGraphs.value = new Set();
        if (props.currentGraphId) {
            selectedGraphs.value.add(props.currentGraphId);
        }
        resetUrlState();
        triggerGeneration();
    }
});

// Regenerate when tab changes
watch(activeTab, () => {
    resetUrlState();
    triggerGeneration();
});

const resetUrlState = () => {
    copySuccess.value = false;
    shortUrl.value = null;
    shortError.value = null;
    isLoadingShort.value = false;
};

const toggleGraphSelection = (id: string) => {
    if (selectedGraphs.value.has(id)) {
        selectedGraphs.value.delete(id);
    } else {
        selectedGraphs.value.add(id);
    }
    resetUrlState();
    triggerGeneration();
};

const triggerGeneration = () => {
    let ids: string[] = [];
    
    if (activeTab.value === 'current') {
        if (props.currentGraphId) ids = [props.currentGraphId];
    } else if (activeTab.value === 'project') {
        ids = projectGraphs.value.map(g => g.id);
    } else if (activeTab.value === 'custom') {
        ids = Array.from(selectedGraphs.value);
    }

    // Only generate if we have something to share
    if (ids.length > 0) {
        emit('generate', { scope: activeTab.value, selectedGraphIds: ids });
    }
};

const displayUrl = computed(() => shortUrl.value || props.url);

const copyToClipboard = async () => {
  if (!displayUrl.value) return;
  try {
    await navigator.clipboard.writeText(displayUrl.value);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  } catch {
    const input = document.createElement("textarea");
    input.value = displayUrl.value;
    document.body.appendChild(input);
    input.select();
    document.execCommand('copy');
    document.body.removeChild(input);
    copySuccess.value = true;
    setTimeout(() => copySuccess.value = false, 2000);
  }
};

const shortenUrl = async () => {
    if (shortUrl.value || !props.url) return; 
    
    isLoadingShort.value = true;
    shortError.value = null;
    
    try {
        const target = `https://is.gd/create.php?format=json&url=${encodeURIComponent(props.url)}`;
        const proxy = `https://api.allorigins.win/get?url=${encodeURIComponent(target)}`;
        
        const response = await fetch(proxy);
        if (!response.ok) throw new Error(`HTTP Error ${response.status}`);
        
        const proxyData = await response.json();
        
        if (proxyData.contents) {
            const data = JSON.parse(proxyData.contents);
            if (data.errorcode) throw new Error(data.errormessage || 'Unknown is.gd error');
            if (data.shorturl) shortUrl.value = data.shorturl;
            else throw new Error('Invalid response from is.gd');
        } else {
             throw new Error('Empty response from proxy');
        }

    } catch (e: unknown) {
        console.error("Shortening failed:", e);
        shortError.value = e instanceof Error ? e.message : String(e);
        if (shortError.value?.includes("Rate limit")) {
            shortError.value = "Rate limit exceeded. Please try again later.";
        } else if (shortError.value?.includes("Failed to fetch") || shortError.value?.includes("414")) {
             shortError.value = "URL is too long for the shortener service. Please use the Long URL.";
        }
    } finally {
        isLoadingShort.value = false;
    }
};
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>Share Model</h3>
    </template>
    <template #body>
      <div class="share-layout">
          <!-- Tab Navigation -->
          <div class="share-tabs">
              <button 
                class="tab-btn" 
                :class="{ active: activeTab === 'current' }"
                @click="activeTab = 'current'"
              >
                  <i class="fas fa-file-alt"></i> Current Graph
              </button>
              <button 
                class="tab-btn" 
                :class="{ active: activeTab === 'project' }"
                @click="activeTab = 'project'"
              >
                  <i class="fas fa-folder"></i> Whole Project
              </button>
              <button 
                class="tab-btn" 
                :class="{ active: activeTab === 'custom' }"
                @click="activeTab = 'custom'"
              >
                  <i class="fas fa-check-square"></i> Select Graphs
              </button>
          </div>

          <!-- Custom Selection Area -->
          <div v-if="activeTab === 'custom'" class="selection-area">
              <div class="selection-header">Select graphs to include:</div>
              <div class="graph-list">
                  <div v-for="graph in projectGraphs" :key="graph.id" class="graph-item">
                      <label>
                          <input type="checkbox" :checked="selectedGraphs.has(graph.id)" @change="toggleGraphSelection(graph.id)">
                          <span class="graph-name">{{ graph.name }}</span>
                      </label>
                  </div>
              </div>
          </div>

          <div class="divider"></div>

          <!-- URL Result Area -->
          <div class="result-area">
              <div v-if="!url" class="empty-message">
                  Select graphs to generate a link.
              </div>
              <template v-else>
                  <label class="url-label">Share Link ({{ shortUrl ? 'Shortened' : 'Base64' }})</label>
                  <div class="url-row">
                      <BaseInput 
                          :model-value="displayUrl" 
                          readonly 
                          class="url-input"
                          :class="{ 'is-short': !!shortUrl }"
                          @focus="(e: FocusEvent) => (e.target as HTMLInputElement).select()"
                      />
                      <BaseButton @click="copyToClipboard" type="primary" class="icon-only-btn" title="Copy to Clipboard">
                          <i :class="copySuccess ? 'fas fa-check' : 'fas fa-copy'"></i>
                      </BaseButton>
                  </div>

                  <div class="actions-row">
                      <BaseButton 
                        v-if="!shortUrl"
                        @click="shortenUrl" 
                        type="secondary" 
                        size="small" 
                        :disabled="isLoadingShort"
                        class="shorten-btn"
                      >
                          <i v-if="isLoadingShort" class="fas fa-spinner fa-spin"></i>
                          <span v-else>Shorten URL (is.gd)</span>
                      </BaseButton>
                      
                      <div v-if="shortError" class="error-msg">
                          <i class="fas fa-exclamation-circle"></i> {{ shortError }}
                      </div>
                  </div>
                  
                  <div class="info-note">
                      <i class="fas fa-info-circle"></i>
                      <span>The model, data & inits are directly encoded as the base64 URL. Nothing is stored on our servers.</span>
                  </div>

                  <div class="disclaimer-box">
                      <i class="fas fa-exclamation-triangle"></i>
                      <small>
                          <strong>Note:</strong> <a href="https://is.gd" target="_blank" rel="noopener noreferrer" class="text-link">is.gd</a> is a third-party service. Please avoid generating short links excessively to prevent hitting rate limits. 
                          If generation fails, use the Long URL above.
                      </small>
                  </div>
              </template>
          </div>
      </div>
    </template>
  </BaseModal>
</template>

<style scoped>
.share-layout {
    display: flex;
    flex-direction: column;
    gap: 15px;
}

.share-tabs {
    display: flex;
    background-color: var(--theme-bg-hover);
    padding: 4px;
    border-radius: var(--radius-md);
    gap: 4px;
}

.tab-btn {
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

.tab-btn:hover {
    color: var(--theme-text-primary);
    background-color: rgba(0,0,0,0.05);
}

.tab-btn.active {
    background-color: var(--theme-bg-panel);
    color: var(--theme-primary);
    box-shadow: var(--shadow-sm);
    font-weight: 600;
}

.selection-area {
    border: 1px solid var(--theme-border);
    border-radius: var(--radius-md);
    padding: 10px;
    background-color: var(--theme-bg-canvas);
}

.selection-header {
    font-size: 0.85em;
    font-weight: 600;
    color: var(--theme-text-secondary);
    margin-bottom: 8px;
}

.graph-list {
    max-height: 120px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.graph-item label {
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
    padding: 4px;
    border-radius: 4px;
    transition: background 0.2s;
}

.graph-item label:hover {
    background-color: var(--theme-bg-hover);
}

.divider {
    height: 1px;
    background-color: var(--theme-border);
    width: 100%;
}

.result-area {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.url-label {
    font-size: 0.85em;
    font-weight: 600;
    color: var(--theme-text-secondary);
}

.url-row {
    display: flex;
    gap: 8px;
}

.url-input {
    flex-grow: 1;
    font-family: monospace;
    font-size: 0.85em;
}

.url-input.is-short {
    color: var(--theme-primary);
    font-weight: 600;
}

.icon-only-btn {
    width: 36px;
    padding: 0;
    display: flex;
    align-items: center;
    justify-content: center;
}

.actions-row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 32px;
}

.shorten-btn {
    min-width: 140px;
}

.error-msg {
    font-size: 0.8em;
    color: var(--theme-danger);
}

.info-note {
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

.disclaimer-box {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    font-size: 0.8em;
    color: var(--theme-text-secondary); /* Slightly different color to distinguish */
    background-color: rgba(245, 158, 11, 0.1); /* Amber tint for warning */
    padding: 8px;
    border-radius: var(--radius-sm);
}

.disclaimer-box i {
    color: var(--theme-warning);
    margin-top: 2px;
}

.text-link {
    color: var(--theme-primary);
    text-decoration: underline;
    font-weight: 500;
}

.text-link:hover {
    color: var(--theme-primary-hover);
}

.empty-message {
    text-align: center;
    color: var(--theme-text-secondary);
    font-style: italic;
    padding: 20px;
}
</style>
