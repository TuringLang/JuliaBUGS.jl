// src/stores/executionStore.ts

import { defineStore } from 'pinia';
import { ref } from 'vue';

export interface ExecutionResult {
  [key: string]: string | number;
}

export interface GeneratedFile {
  name: string;
  content: string;
}

export interface Dependency {
    name: string;
    version: string;
}

export interface SamplerSettings {
    n_samples: number;
    n_adapts: number;
    n_chains: number;
}

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

  // State for settings
  const dependencies = ref<Dependency[]>([
      { name: 'JuliaBUGS', version: '' },
      { name: 'LogDensityProblemsAD', version: '' },
      { name: 'AdvancedHMC', version: '' },
      { name: 'MCMCChains', version: '' },
      { name: 'ReverseDiff', version: '' },
      { name: 'JSON3', version: '' }, // Added to ensure the sandbox can write results
  ]);
  const samplerSettings = ref<SamplerSettings>({
      n_samples: 1000,
      n_adapts: 1000,
      n_chains: 1
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
    executionLogs.value = [];
    executionError.value = null;
    generatedFiles.value = [];
  };

  return {
    backendUrl,
    isConnected,
    isConnecting,
    isExecuting,
    executionResults,
    executionLogs,
    executionError,
    generatedFiles,
    dependencies,
    samplerSettings,
    setBackendUrl,
    resetExecutionState,
  };
});
