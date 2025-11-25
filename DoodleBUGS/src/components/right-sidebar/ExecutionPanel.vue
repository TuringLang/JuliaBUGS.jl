<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import { useExecutionStore } from '../../stores/executionStore';
import type { ExecutionPanelTab } from '../../stores/executionStore';
import BaseButton from '../ui/BaseButton.vue';

// CodeMirror for file viewing
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

const executionStore = useExecutionStore();
const {
  isExecuting,
  executionResults,
  executionLogs,
  executionError,
  generatedFiles,
  // New richer result slices
  summaryResults,
  quantileResults,
  executionPanelTab,
} = storeToRefs(executionStore);

const activeTab = computed<ExecutionPanelTab>({
  get: () => executionPanelTab.value,
  set: (val) => executionStore.setExecutionPanelTab(val),
});
const copySuccessStates = ref<{ [key: string]: boolean }>({});

// Results datasets
const hasSummary = computed(() => (summaryResults.value ?? executionResults.value ?? []).length > 0);
const hasQuantiles = computed(() => (quantileResults.value ?? []).length > 0);

// Collapsible sections
const showSummary = ref(true);
const showQuantiles = ref(true);

// Active file tab state
const activeFileName = ref<string | null>(null);
watch(generatedFiles, (files) => {
  if (files.length === 0) {
    activeFileName.value = null;
    return;
  }
  if (!activeFileName.value || !files.some(f => f.name === activeFileName.value)) {
    activeFileName.value = files[0].name;
  }
}, { immediate: true });

const activeFileContent = computed(() => {
  if (!activeFileName.value) return '';
  const f = generatedFiles.value.find(f => f.name === activeFileName.value);
  return f?.content ?? '';
});

// CodeMirror instance for file content
const fileEditorContainer = ref<HTMLDivElement | null>(null);
let cmInstance: Editor | null = null;
const editorReady = ref(false);

function pickModeByExt(name: string | null): string | undefined {
  if (!name) return undefined;
  const lower = name.toLowerCase();
  if (lower.endsWith('.jl')) return 'julia';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.csv') || lower.endsWith('.txt') || lower.endsWith('.log')) return undefined; // plain text
  return undefined;
}

function ensureEditor() {
  if (!fileEditorContainer.value) return;
  if (!cmInstance) {
    cmInstance = CodeMirror(fileEditorContainer.value, {
      value: activeFileContent.value,
      mode: pickModeByExt(activeFileName.value),
      theme: 'material-darker',
      lineNumbers: true,
      readOnly: true,
      tabSize: 2,
      scrollbarStyle: 'simple',
      foldGutter: true,
      gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter'],
    });
    editorReady.value = true;
  } else {
    // Update mode and value to match current file
    const cm = cmInstance as Editor & { setOption: (option: string, value: unknown) => void };
    cm.setOption('mode', pickModeByExt(activeFileName.value));
    if (cmInstance.getValue() !== activeFileContent.value) cmInstance.setValue(activeFileContent.value);
  }
  nextTick(() => cmInstance?.refresh());
}

onMounted(() => {
  if (activeTab.value === 'files') {
    nextTick(() => ensureEditor());
  }
});

onUnmounted(() => {
  if (cmInstance) {
    const el = cmInstance.getWrapperElement();
    el.parentNode?.removeChild(el);
    cmInstance = null;
  }
  editorReady.value = false;
});

watch([activeTab, activeFileName], ([tab]) => {
  if (tab === 'files') nextTick(() => ensureEditor());
});

// Ensure editor also initializes when files arrive or container appears
watch(generatedFiles, () => {
  if (activeTab.value === 'files') nextTick(() => ensureEditor());
});

watch(fileEditorContainer, () => {
  if (activeTab.value === 'files') nextTick(() => ensureEditor());
});

watch(activeFileContent, (content) => {
  if (cmInstance && activeTab.value === 'files') {
    if (cmInstance.getValue() !== content) cmInstance.setValue(content);
  }
});

// Per-table headers
const summaryHeaders = computed(() => {
  const rows = summaryResults.value ?? executionResults.value ?? [];
  return rows.length ? Object.keys(rows[0]) : ([] as string[]);
});
const quantileHeaders = computed(() => {
  const rows = quantileResults.value ?? [];
  return rows.length ? Object.keys(rows[0]) : ([] as string[]);
});

// Interactive results helpers
const filterText = ref('');
const rhatThreshold = 1.1;

// Independent sort state per table
const summarySortKey = ref<string | null>(null);
const summarySortDir = ref<'asc' | 'desc'>('asc');
const quantSortKey = ref<string | null>(null);
const quantSortDir = ref<'asc' | 'desc'>('asc');

const isRhatHeader = (h: string) => /(^rhat$|r_hat|rhat)/i.test(h);

const filteredSortedSummary = computed(() => {
  const rows = (summaryResults.value ?? executionResults.value ?? []) as Array<Record<string, unknown>>;
  const ft = filterText.value.trim().toLowerCase();
  const filtered = ft
    ? rows.filter(row => {
        const keys = Object.keys(row);
        const paramKey = keys.find(k => /^(param|parameter|parameters|name)$/i.test(k)) || keys[0];
        const str = String(row[paramKey] ?? '');
        return str.toLowerCase().includes(ft);
      })
    : rows.slice();

  if (summarySortKey.value) {
    const key = summarySortKey.value as string;
    const dir = summarySortDir.value === 'asc' ? 1 : -1;
    filtered.sort((a, b) => {
      const av = (a as Record<string, unknown>)[key];
      const bv = (b as Record<string, unknown>)[key];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
      return String(av).localeCompare(String(bv)) * dir;
    });
  }
  return filtered;
});

const filteredSortedQuantiles = computed(() => {
  const rows = (quantileResults.value ?? []) as Array<Record<string, unknown>>;
  const ft = filterText.value.trim().toLowerCase();
  const filtered = ft
    ? rows.filter(row => {
        const keys = Object.keys(row);
        const paramKey = keys.find(k => /^(param|parameter|parameters|name)$/i.test(k)) || keys[0];
        const str = String(row[paramKey] ?? '');
        return str.toLowerCase().includes(ft);
      })
    : rows.slice();

  if (quantSortKey.value) {
    const key = quantSortKey.value as string;
    const dir = quantSortDir.value === 'asc' ? 1 : -1;
    filtered.sort((a, b) => {
      const av = (a as Record<string, unknown>)[key];
      const bv = (b as Record<string, unknown>)[key];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
      return String(av).localeCompare(String(bv)) * dir;
    });
  }
  return filtered;
});

function toggleSummarySort(header: string) {
  if (summarySortKey.value === header) {
    summarySortDir.value = summarySortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    summarySortKey.value = header;
    summarySortDir.value = 'asc';
  }
}

function toggleQuantSort(header: string) {
  if (quantSortKey.value === header) {
    quantSortDir.value = quantSortDir.value === 'asc' ? 'desc' : 'asc';
  } else {
    quantSortKey.value = header;
    quantSortDir.value = 'asc';
  }
}

function downloadSummaryCsv() {
  const rows = filteredSortedSummary.value;
  if (!rows || rows.length === 0) return;
  const headers = summaryHeaders.value;
  const esc = (v: unknown) => {
    const s = typeof v === 'number' ? v.toString() : String(v ?? '');
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const csv = [headers.join(','), ...rows.map(r => headers.map(h => esc((r as Record<string, unknown>)[h])).join(','))].join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'summary.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function downloadQuantilesCsv() {
  const rows = filteredSortedQuantiles.value;
  if (!rows || rows.length === 0) return;
  const headers = quantileHeaders.value;
  const esc = (v: unknown) => {
    const s = typeof v === 'number' ? v.toString() : String(v ?? '');
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const csv = [headers.join(','), ...rows.map(r => headers.map(h => esc((r as Record<string, unknown>)[h])).join(','))].join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'quantiles.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

const copyFileContent = (fileName: string, content: string) => {
  navigator.clipboard.writeText(content).then(() => {
    copySuccessStates.value[fileName] = true;
    setTimeout(() => {
      copySuccessStates.value[fileName] = false;
    }, 2000);
  }).catch(err => {
    console.error(`Failed to copy ${fileName}:`, err);
    alert('Failed to copy content to clipboard.');
  });
};

const downloadFileContent = (fileName: string, content: string) => {
  try {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  } catch (err) {
    console.error(`Failed to download ${fileName}:`, err);
    alert('Failed to trigger download.');
  }
};
</script>

<template>
  <div class="execution-panel">
    <div v-if="isExecuting" class="loading-overlay">
      <div class="spinner"></div>
      <p>Executing model on backend...</p>
    </div>

    <div class="panel-tabs">
      <BaseButton
        :class="{ active: activeTab === 'logs' }"
        @click="activeTab = 'logs'"
        size="small"
      >
        Logs
      </BaseButton>
      <BaseButton
        :class="{ active: activeTab === 'files' }"
        @click="activeTab = 'files'"
        size="small"
      >
        Files
      </BaseButton>
      <BaseButton
        :class="{ active: activeTab === 'results' }"
        @click="activeTab = 'results'"
        size="small"
      >
        Results
      </BaseButton>
    </div>

    <div class="panel-content">
      <div v-if="executionError" class="error-display">
        <h4>Execution Failed</h4>
        <pre>{{ executionError }}</pre>
      </div>

      <div v-show="activeTab === 'results'" class="tab-pane">
        <div v-if="!hasSummary && !hasQuantiles" class="placeholder">
          <p>Execution results will appear here.</p>
        </div>
        <div v-else class="results-table-container">
          <div class="results-toolbar">
            <input class="filter-input" v-model="filterText" type="text" placeholder="Filter parameters..." />
          </div>

          <div>
            <div class="table-header" @click="showSummary = !showSummary" style="cursor: pointer;">
              <div class="table-title"><strong>Summary</strong> <span style="opacity:.7; margin-left:6px;">{{ showSummary ? 'â–¾' : 'â–¸' }}</span></div>
              <div class="table-actions">
                <BaseButton size="small" type="secondary" @click.stop="downloadSummaryCsv" :disabled="!hasSummary">Download CSV</BaseButton>
              </div>
            </div>
            <div v-if="!hasSummary" class="placeholder"><p>No summary available.</p></div>
            <div v-else v-show="showSummary">
              <table class="results-table">
                <thead>
                  <tr>
                    <th v-for="header in summaryHeaders" :key="header"
                        @click="toggleSummarySort(header)"
                        :class="['sortable', { sorted: summarySortKey === header, desc: summarySortKey === header && summarySortDir === 'desc' }]">
                      {{ header }}
                      <span class="sort-indicator" v-if="summarySortKey === header">{{ summarySortDir === 'asc' ? 'â–²' : 'â–¼' }}</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(row, index) in filteredSortedSummary" :key="index">
                    <td v-for="header in summaryHeaders" :key="header"
                        :class="{ 'rhat-bad': isRhatHeader(header) && typeof row[header] === 'number' && row[header] > rhatThreshold }">
                      {{ typeof row[header] === 'number' ? row[header].toFixed(4) : row[header] }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div style="margin-top: 16px;">
            <div class="table-header" @click="showQuantiles = !showQuantiles" style="cursor: pointer;">
              <div class="table-title"><strong>Quantiles</strong> <span style="opacity:.7; margin-left:6px;">{{ showQuantiles ? 'â–¾' : 'â–¸' }}</span></div>
              <div class="table-actions">
                <BaseButton size="small" type="secondary" @click.stop="downloadQuantilesCsv" :disabled="!hasQuantiles">Download CSV</BaseButton>
              </div>
            </div>
            <div v-if="!hasQuantiles" class="placeholder"><p>No quantiles available.</p></div>
            <div v-else v-show="showQuantiles">
              <table class="results-table">
                <thead>
                  <tr>
                    <th v-for="header in quantileHeaders" :key="header"
                        @click="toggleQuantSort(header)"
                        :class="['sortable', { sorted: quantSortKey === header, desc: quantSortKey === header && quantSortDir === 'desc' }]">
                      {{ header }}
                      <span class="sort-indicator" v-if="quantSortKey === header">{{ quantSortDir === 'asc' ? 'â–²' : 'â–¼' }}</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(row, index) in filteredSortedQuantiles" :key="index">
                    <td v-for="header in quantileHeaders" :key="header">
                      {{ typeof row[header] === 'number' ? row[header].toFixed(4) : row[header] }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <div v-show="activeTab === 'logs'" class="tab-pane">
        <pre class="logs-display">{{ executionLogs.join('\n') }}</pre>
      </div>

      <div v-show="activeTab === 'files'" class="tab-pane">
        <div v-if="generatedFiles.length === 0" class="placeholder">
          <p>Generated files from the sandbox will appear here.</p>
        </div>
        <div v-else class="files-tabbed">
          <div class="file-tabs">
            <button v-for="file in generatedFiles" :key="file.name"
                    class="file-tab"
                    :class="{ active: file.name === activeFileName }"
                    @click="activeFileName = file.name">
              {{ file.name }}
            </button>
          </div>
          <div class="file-view" v-if="activeFileName">
            <div class="file-header">
              <strong>{{ activeFileName }}</strong>
              <BaseButton @click="downloadFileContent(activeFileName, activeFileContent)" size="small" type="secondary">
                Download
              </BaseButton>
            </div>
            <div class="editor-wrapper">
              <div ref="fileEditorContainer" class="editor-container"></div>
              <!-- Use native button for reliable touch events -->
              <button
                @click.stop="copyFileContent(activeFileName, activeFileContent)"
                @touchend.stop.prevent="copyFileContent(activeFileName, activeFileContent)"
                class="native-copy-button"
                type="button"
                title="Copy Code"
              >
                <i v-if="copySuccessStates[activeFileName]" class="fas fa-check"></i>
                <i v-else class="fas fa-copy"></i>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.execution-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  position: relative;
}

.loading-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(255, 255, 255, 0.8);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  z-index: 10;
  color: var(--color-heading);
}

.spinner {
  border: 4px solid var(--color-border-light);
  border-top: 4px solid var(--color-primary);
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
  margin-bottom: 15px;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.panel-tabs {
  display: flex;
  gap: 5px;
  border-bottom: 1px solid var(--color-border);
  padding-bottom: 10px;
  margin-bottom: 10px;
  flex-shrink: 0;
}

.panel-tabs .base-button {
  flex-grow: 1;
  background-color: var(--color-background-mute);
}

.panel-tabs .base-button.active {
  background-color: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}

.panel-content {
  flex-grow: 1;
  overflow-y: auto;
}

.error-display {
  background-color: #fffbe6;
  border: 1px solid #ffe58f;
  border-left: 4px solid var(--color-danger);
  padding: 15px;
  border-radius: 4px;
  margin-bottom: 15px;
}

.error-display h4 {
  margin: 0 0 10px 0;
  color: var(--color-danger);
}

.error-display pre, .logs-display, .file-content {
  white-space: pre-wrap;
  word-break: break-all;
  background-color: var(--color-background-dark);
  color: var(--color-text-light);
  padding: 10px;
  border-radius: 4px;
  font-family: 'Fira Code', monospace;
  font-size: 0.8em;
}

.placeholder {
  text-align: center;
  padding: 40px 20px;
  color: var(--color-secondary);
  font-style: italic;
}

.results-table-container {
  overflow-x: auto;
}

.results-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.85em;
}

.results-table th, .results-table td {
  border: 1px solid var(--color-border);
  padding: 8px;
  text-align: left;
}

.results-table th {
  background-color: var(--color-background-mute);
  font-weight: 600;
}

.results-table tbody tr:nth-child(even) {
  background-color: var(--color-background-soft);
}

.files-tabbed {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.file-tabs {
  display: flex;
  gap: 4px;
  border-bottom: 1px solid var(--color-border);
  overflow-x: auto;
  overflow-y: hidden;
  white-space: nowrap;
  flex-wrap: nowrap;
  padding-bottom: 2px;
  scrollbar-width: thin;
  overscroll-behavior-x: contain; /* prevent horizontal scroll chaining to content */
}

.file-tab {
  padding: 3px 8px;
  font-size: 12px;
  line-height: 1.2;
  border: 1px solid var(--color-border);
  border-bottom: none;
  background: var(--color-background-mute);
  color: var(--color-text);
  border-top-left-radius: 4px;
  border-top-right-radius: 4px;
  cursor: pointer;
  flex: 0 0 auto; /* prevent tabs from stretching */
}

.file-tab.active {
  background: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}

.file-view {
  border: 1px solid var(--color-border);
  border-radius: 4px;
  position: relative;
  display: flex;
  flex-direction: column;
}

.file-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background-color: var(--color-background-mute);
  padding: 8px 12px;
  border-bottom: 1px solid var(--color-border);
  color: var(--color-heading);
}

.file-content {
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}

.results-toolbar {
  display: flex;
  gap: 8px;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.results-toolbar .toolbar-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}

.filter-input {
  flex: 1;
  padding: 6px 8px;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  font-size: 0.9em;
}

.results-table th.sortable { cursor: pointer; user-select: none; }
.results-table th.sorted { color: var(--color-primary); }
.results-table th.desc .sort-indicator { transform: rotate(180deg); }
.sort-indicator { margin-left: 4px; font-size: 0.8em; }

.rhat-bad {
  background: rgba(255, 99, 71, 0.15);
  color: #b00020;
  font-weight: 600;
}

.table-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin: 6px 0;
}

.table-title { font-size: 0.95em; }
.table-actions { display: flex; gap: 8px; }

.editor-wrapper {
  position: relative;
  flex-grow: 1;
  background-color: #282c34;
  border-radius: 8px;
  overflow: hidden;
  height: 67vh; /* provide a consistent viewer height like a panel */
}

.editor-container {
  width: 100%;
  height: 100%;
}

/* Ensure CodeMirror fills the editor container so the internal scrollbar shows */
.editor-container .CodeMirror { height: 100% !important; }
.editor-container .CodeMirror-scroll { height: 100% !important; }

.native-copy-button {
  position: absolute;
  bottom: 12px;
  right: 12px;
  z-index: 1000;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background-color: var(--color-secondary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  cursor: pointer;
  opacity: 0.9;
  transition: background-color 0.2s, opacity 0.2s;
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

<style>
/* Make CodeMirror read-only look consistent */
.execution-panel .CodeMirror,
.execution-panel .CodeMirror-scroll,
.execution-panel .CodeMirror-gutters,
.execution-panel .CodeMirror textarea,
.execution-panel .CodeMirror pre,
.execution-panel .CodeMirror-line,
.execution-panel .CodeMirror-code {
  cursor: not-allowed !important;
}

.execution-panel .CodeMirror-readonly .CodeMirror-cursors { display: none !important; }
.execution-panel .CodeMirror-scroll { overflow: auto !important; white-space: pre !important; }
.execution-panel .CodeMirror-simplescroll-horizontal div,
.execution-panel .CodeMirror-simplescroll-vertical div { background: #666; border-radius: 3px; }
.execution-panel .CodeMirror-foldgutter-open,
.execution-panel .CodeMirror-foldgutter-folded { color: #999; }
</style>
