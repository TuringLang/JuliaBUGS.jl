import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export interface SamplerSettings {
    n_samples: number;
    n_adapts: number;
    n_chains: number;
    seed?: number | null;
}

export const useScriptStore = defineStore('script', () => {
  const LS_KEYS = {
    standaloneScript: 'doodlebugs-standaloneScript',
  } as const;

  const standaloneScript = ref<string>(localStorage.getItem(LS_KEYS.standaloneScript) || '');

  const samplerSettings = ref<SamplerSettings>({
      n_samples: 1000,
      n_adapts: 1000,
      n_chains: 1,
      seed: null,
  });

  watch(standaloneScript, (v) => localStorage.setItem(LS_KEYS.standaloneScript, v));

  return {
    standaloneScript,
    samplerSettings,
  };
});
