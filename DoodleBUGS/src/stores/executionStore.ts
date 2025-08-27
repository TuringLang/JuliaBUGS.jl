import { defineStore } from 'pinia';
import { ref } from 'vue';

export interface ExecutionResult {
  [key: string]: string | number;
}

export interface GeneratedFile {
  name: string;
  content: string;
}

export interface SamplerSettings {
    n_samples: number;
    n_adapts: number;
    n_chains: number;
    seed?: number | null;
    timeout_s?: number | null;
}

export type ExecutionPanelTab = 'logs' | 'files' | 'results';

export const useExecutionStore = defineStore('execution', () => {
  // State for backend connection
  const backendUrl = ref<string | null>(localStorage.getItem('doodlebugs-backendUrl') || null);
  const isConnected = ref(false);
  const isConnecting = ref(false);

  // State for model execution
  const isExecuting = ref(false);
  const executionResults = ref<ExecutionResult[] | null>(null);
  const executionLogs = ref<string[]>([]);
  const executionError = ref<string | null>(null);
  const generatedFiles = ref<GeneratedFile[]>([]);

  // Separate fields for richer result types
  const summaryResults = ref<ExecutionResult[] | null>(null);
  const quantileResults = ref<ExecutionResult[] | null>(null);

  // UI state for ExecutionPanel tab selection (for auto-switching between Logs/Results/Files)
  const executionPanelTab = ref<ExecutionPanelTab>('results');

  // Sampler settings (backend uses fixed environment; no per-request dependencies)
  const samplerSettings = ref<SamplerSettings>({
      n_samples: 1000,
      n_adapts: 1000,
      n_chains: 1,
      seed: null,
      timeout_s: 0, // default to no frontend timeout; backend may ignore or enforce separately
  });

  const setBackendUrl = (url: string | null) => {
    if (url) {
      backendUrl.value = url;
      localStorage.setItem('doodlebugs-backendUrl', url);
    } else {
      backendUrl.value = null;
      localStorage.removeItem('doodlebugs-backendUrl');
    }
  };

  const resetExecutionState = () => {
    isExecuting.value = true;
    executionResults.value = null;
    summaryResults.value = null;
    quantileResults.value = null;
    executionLogs.value = [];
    executionError.value = null;
    generatedFiles.value = [];
    executionPanelTab.value = 'logs';
  };

  const setExecutionPanelTab = (tab: ExecutionPanelTab) => {
    executionPanelTab.value = tab;
  };

  return {
    backendUrl,
    isConnected,
    isConnecting,
    isExecuting,
    executionResults,
    summaryResults,
    quantileResults,
    executionLogs,
    executionError,
    generatedFiles,
    samplerSettings,
    executionPanelTab,
    setBackendUrl,
    resetExecutionState,
    setExecutionPanelTab,
  };
});
