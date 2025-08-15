<!-- src/components/right-sidebar/ExecutionPanel.vue -->
<script setup lang="ts">
import { ref, computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useExecutionStore } from '../../stores/executionStore';
import BaseButton from '../ui/BaseButton.vue';

const executionStore = useExecutionStore();
const {
  isExecuting,
  executionResults,
  executionLogs,
  executionError,
  generatedFiles
} = storeToRefs(executionStore);

const activeTab = ref<'results' | 'logs' | 'files'>('results');
const copySuccessStates = ref<{ [key: string]: boolean }>({});

const resultHeaders = computed(() => {
  if (!executionResults.value || executionResults.value.length === 0) {
    return [];
  }
  // All objects should have the same keys, so we can take them from the first object.
  return Object.keys(executionResults.value[0]);
});

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
</script>

<template>
  <div class="execution-panel">
    <div v-if="isExecuting" class="loading-overlay">
      <div class="spinner"></div>
      <p>Executing model on backend...</p>
    </div>

    <div class="panel-tabs">
      <BaseButton
        :class="{ active: activeTab === 'results' }"
        @click="activeTab = 'results'"
        size="small"
      >
        Results
      </BaseButton>
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
    </div>

    <div class="panel-content">
      <div v-if="executionError" class="error-display">
        <h4>Execution Failed</h4>
        <pre>{{ executionError }}</pre>
      </div>

      <div v-show="activeTab === 'results'" class="tab-pane">
        <div v-if="!executionResults" class="placeholder">
          <p>Execution results will appear here.</p>
        </div>
        <div v-else class="results-table-container">
          <table class="results-table">
            <thead>
              <tr>
                <th v-for="header in resultHeaders" :key="header">{{ header }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, index) in executionResults" :key="index">
                <td v-for="header in resultHeaders" :key="header">
                  {{ typeof row[header] === 'number' ? row[header].toFixed(4) : row[header] }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div v-show="activeTab === 'logs'" class="tab-pane">
        <pre class="logs-display">{{ executionLogs.join('\n') }}</pre>
      </div>

      <div v-show="activeTab === 'files'" class="tab-pane">
        <div v-if="generatedFiles.length === 0" class="placeholder">
          <p>Generated files from the sandbox will appear here.</p>
        </div>
        <div v-else class="files-container">
          <div v-for="file in generatedFiles" :key="file.name" class="file-item">
            <div class="file-header">
              <strong>{{ file.name }}</strong>
              <BaseButton @click="copyFileContent(file.name, file.content)" size="small">
                <i v-if="copySuccessStates[file.name]" class="fas fa-check"></i>
                <span v-else>Copy</span>
              </BaseButton>
            </div>
            <pre class="file-content">{{ file.content }}</pre>
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

.files-container {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.file-item {
  border: 1px solid var(--color-border);
  border-radius: 4px;
}

.file-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background-color: var(--color-background-mute);
  padding: 8px 12px;
  border-bottom: 1px solid var(--color-border);
}

.file-content {
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}
</style>
