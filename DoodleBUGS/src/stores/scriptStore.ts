import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

export interface SamplerSettings {
  n_samples: number
  n_adapts: number
  n_chains: number
  seed?: number | null
}

export const useScriptStore = defineStore('script', () => {
  let prefix = 'doodlebugs'
  let suppressWatch = false

  const setPrefix = (p: string) => {
    suppressWatch = true
    prefix = p
    const stored = localStorage.getItem(`${prefix}-standaloneScript`)
    standaloneScript.value = stored ?? ''
    const storedStan = localStorage.getItem(`${prefix}-standaloneStanScript`)
    standaloneStanScript.value = storedStan ?? ''
    suppressWatch = false
  }

  const standaloneScript = ref<string>(localStorage.getItem(`${prefix}-standaloneScript`) || '')
  const standaloneStanScript = ref<string>(
    localStorage.getItem(`${prefix}-standaloneStanScript`) || ''
  )

  const samplerSettings = ref<SamplerSettings>({
    n_samples: 1000,
    n_adapts: 1000,
    n_chains: 1,
    seed: null,
  })

  watch(standaloneScript, (v) => {
    if (!suppressWatch) localStorage.setItem(`${prefix}-standaloneScript`, v)
  })

  watch(standaloneStanScript, (v) => {
    if (!suppressWatch) localStorage.setItem(`${prefix}-standaloneStanScript`, v)
  })

  return {
    standaloneScript,
    standaloneStanScript,
    samplerSettings,
    setPrefix,
  }
})
