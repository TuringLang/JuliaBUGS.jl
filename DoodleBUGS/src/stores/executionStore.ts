import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

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
  const backendUrl = ref<string | null>(localStorage.getItem('doodlebugs-backendUrl') || null);
  const isConnected = ref(false);
  const isConnecting = ref(false);

  const isExecuting = ref(false);
  const LS_KEYS = {
    logs: 'doodlebugs-executionLogs',
    error: 'doodlebugs-executionError',
    files: 'doodlebugs-generatedFiles',
    results: 'doodlebugs-executionResults',
    summary: 'doodlebugs-summaryResults',
    quantiles: 'doodlebugs-quantileResults',
    panelTab: 'doodlebugs-executionPanelTab',
  } as const;

  const safeParse = <T>(key: string, fallback: T): T => {
    try {
      const raw = localStorage.getItem(key);
      if (raw == null) return fallback;
      return JSON.parse(raw) as T;
    } catch {
      return fallback;
    }
  };

  const isValidTab = (v: unknown): v is ExecutionPanelTab => v === 'logs' || v === 'files' || v === 'results';

  const executionResults = ref<ExecutionResult[] | null>(safeParse<ExecutionResult[] | null>(LS_KEYS.results, null));
  const executionLogs = ref<string[]>(safeParse<string[]>(LS_KEYS.logs, []));
  const executionError = ref<string | null>(safeParse<string | null>(LS_KEYS.error, null));
  const generatedFiles = ref<GeneratedFile[]>(safeParse<GeneratedFile[]>(LS_KEYS.files, []));
  const activeFileName = ref<string | null>(null);

  const summaryResults = ref<ExecutionResult[] | null>(safeParse<ExecutionResult[] | null>(LS_KEYS.summary, null));
  const quantileResults = ref<ExecutionResult[] | null>(safeParse<ExecutionResult[] | null>(LS_KEYS.quantiles, null));

  const executionPanelTab = ref<ExecutionPanelTab>(
    (() => {
      const persisted = safeParse<unknown>(LS_KEYS.panelTab, 'results');
      return isValidTab(persisted) ? persisted : 'results';
    })()
  );

  const samplerSettings = ref<SamplerSettings>({
      n_samples: 1000,
      n_adapts: 1000,
      n_chains: 1,
      seed: null,
      timeout_s: 0,
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
    activeFileName.value = null;
    executionPanelTab.value = 'logs';
  };

  const setExecutionPanelTab = (tab: ExecutionPanelTab) => {
    executionPanelTab.value = tab;
  };

  watch(executionLogs, (v) => localStorage.setItem(LS_KEYS.logs, JSON.stringify(v)), { deep: true });
  watch(executionError, (v) => localStorage.setItem(LS_KEYS.error, JSON.stringify(v)));
  watch(generatedFiles, (v) => localStorage.setItem(LS_KEYS.files, JSON.stringify(v)), { deep: true });
  watch(executionResults, (v) => localStorage.setItem(LS_KEYS.results, JSON.stringify(v)));
  watch(summaryResults, (v) => localStorage.setItem(LS_KEYS.summary, JSON.stringify(v)));
  watch(quantileResults, (v) => localStorage.setItem(LS_KEYS.quantiles, JSON.stringify(v)));
  watch(executionPanelTab, (v) => localStorage.setItem(LS_KEYS.panelTab, JSON.stringify(v)));

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
    activeFileName,
    samplerSettings,
    executionPanelTab,
    setBackendUrl,
    resetExecutionState,
    setExecutionPanelTab,
  };
});
