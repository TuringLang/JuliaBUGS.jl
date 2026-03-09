import { ref, watch } from 'vue'
import type { Ref } from 'vue'
import { useToast } from 'primevue/usetoast'
import { useGraphStore } from '../stores/graphStore'
import { useProjectStore } from '../stores/projectStore'
import { useDataStore } from '../stores/dataStore'
import { useScriptStore } from '../stores/scriptStore'
import { useGraphInstance } from './useGraphInstance'
import { generateStandaloneScript } from './useBugsCodeGenerator'
import {
  generateStanStandaloneScript,
  generateStanDataJson,
  generateStanInitsJson,
  extractCensoredFields,
} from './useStanCodeGenerator'
import { downloadBlob } from '../utils/downloadBlob'

export function useFileExport(generatedCode: Ref<string>, stanCode?: Ref<string>) {
  const graphStore = useGraphStore()
  const projectStore = useProjectStore()
  const dataStore = useDataStore()
  const scriptStore = useScriptStore()
  const toast = useToast()
  const { getCyInstance } = useGraphInstance()

  const showExportModal = ref(false)
  const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null)

  const getScriptContent = () => {
    const { parsedGraphData } = dataStore
    const data = parsedGraphData?.data || {}
    const inits = parsedGraphData?.inits || {}
    return generateStandaloneScript({
      modelCode: generatedCode.value,
      data,
      inits,
      settings: {
        n_samples: scriptStore.samplerSettings.n_samples,
        n_adapts: scriptStore.samplerSettings.n_adapts,
        n_chains: scriptStore.samplerSettings.n_chains,
        seed: scriptStore.samplerSettings.seed ?? undefined,
      },
    })
  }

  const handleDownloadBugs = () => {
    const blob = new Blob([generatedCode.value], { type: 'text/plain;charset=utf-8' })
    downloadBlob(blob, 'model.bugs')
  }

  const handleDownloadStan = () => {
    const code = stanCode?.value || ''
    if (!code) return
    const blob = new Blob([code], { type: 'text/plain;charset=utf-8' })
    downloadBlob(blob, 'model.stan')
  }

  const getStanScriptContent = () => {
    const { parsedGraphData } = dataStore
    const data = parsedGraphData?.data || {}
    const inits = parsedGraphData?.inits || {}
    const code = stanCode?.value || ''
    const censoredFields = extractCensoredFields(graphStore.currentGraphElements)
    return generateStanStandaloneScript({
      modelCode: code,
      data,
      inits,
      elements: graphStore.currentGraphElements,
      censoredFields,
      settings: {
        n_samples: scriptStore.samplerSettings.n_samples,
        n_adapts: scriptStore.samplerSettings.n_adapts,
        n_chains: scriptStore.samplerSettings.n_chains,
        seed: scriptStore.samplerSettings.seed ?? undefined,
      },
    })
  }

  const handleGenerateStanScript = () => {
    scriptStore.standaloneStanScript = getStanScriptContent()
  }

  const handleDownloadStanScript = () => {
    const content = scriptStore.standaloneStanScript || getStanScriptContent()
    if (!content) return
    const blob = new Blob([content], { type: 'text/plain' })
    downloadBlob(blob, 'run_stan_model.py')
  }

  const handleDownloadStanData = () => {
    const { parsedGraphData } = dataStore
    const data = parsedGraphData?.data || {}
    const censoredFields = extractCensoredFields(graphStore.currentGraphElements)
    const json = generateStanDataJson(data, censoredFields)
    const blob = new Blob([json], { type: 'application/json' })
    downloadBlob(blob, 'data.json')
  }

  const handleDownloadStanInits = () => {
    const { parsedGraphData } = dataStore
    const inits = parsedGraphData?.inits || {}
    const json = generateStanInitsJson(inits, graphStore.currentGraphElements)
    const blob = new Blob([json], { type: 'application/json' })
    downloadBlob(blob, 'inits.json')
  }

  const handleDownloadScript = () => {
    const content = scriptStore.standaloneScript || getScriptContent()
    if (!content) return
    const blob = new Blob([content], { type: 'text/plain' })
    downloadBlob(blob, 'model_script.jl')
  }

  const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
    currentExportType.value = format
    showExportModal.value = true
  }

  const handleConfirmExport = (options: {
    bg: string
    full: boolean
    scale: number
    quality?: number
  }) => {
    const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
    if (!cy || !currentExportType.value) return
    try {
      let blob: Blob
      const baseOptions = { bg: options.bg, full: options.full, scale: options.scale }
      if (currentExportType.value === 'svg') {
        blob = new Blob([cy.svg(baseOptions)], { type: 'image/svg+xml;charset=utf-8' })
      } else if (currentExportType.value === 'png') {
        blob = cy.png({ ...baseOptions, output: 'blob' }) as unknown as Blob
      } else {
        blob = cy.jpg({
          ...baseOptions,
          quality: options.quality || 0.9,
          output: 'blob',
        }) as unknown as Blob
      }
      downloadBlob(blob, `graph.${currentExportType.value}`)
    } catch (err) {
      console.error('Export failed', err)
      toast.add({
        severity: 'error',
        summary: 'Export Failed',
        detail: err instanceof Error ? err.message : 'Could not export the graph.',
        life: 3000,
      })
    }
  }

  const handleExportJson = () => {
    if (!graphStore.currentGraphId || !projectStore.currentProject) return
    const graphMeta = projectStore.currentProject.graphs.find(
      (g) => g.id === graphStore.currentGraphId
    )
    if (!graphMeta) return
    const exportData = {
      name: graphMeta.name,
      elements: graphStore.currentGraphElements,
      dataContent: dataStore.dataContent,
      version: 1,
    }
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' })
    downloadBlob(blob, `${graphMeta.name.replace(/[^a-z0-9]/gi, '_').toLowerCase()}.json`)
  }

  if (stanCode) {
    watch(stanCode, () => {
      if (scriptStore.standaloneStanScript) {
        scriptStore.standaloneStanScript = getStanScriptContent()
      }
    })
  }

  watch(generatedCode, () => {
    if (scriptStore.standaloneScript) {
      scriptStore.standaloneScript = getScriptContent()
    }
  })

  return {
    showExportModal,
    currentExportType,
    getScriptContent,
    getStanScriptContent,
    handleDownloadBugs,
    handleDownloadStan,
    handleDownloadScript,
    handleGenerateStanScript,
    handleDownloadStanScript,
    handleDownloadStanData,
    handleDownloadStanInits,
    openExportModal,
    handleConfirmExport,
    handleExportJson,
  }
}
