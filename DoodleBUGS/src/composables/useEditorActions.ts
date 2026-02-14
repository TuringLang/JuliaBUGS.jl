import { ref, computed, reactive } from 'vue'
import type { Ref } from 'vue'
import { useToast } from 'primevue/usetoast'
import { useProjectStore } from '../stores/projectStore'
import { useGraphStore } from '../stores/graphStore'
import { useUiStore } from '../stores/uiStore'
import { useDataStore } from '../stores/dataStore'
import { useScriptStore } from '../stores/scriptStore'
import { useGraphInstance } from './useGraphInstance'
import { useGraphLayout } from './useGraphLayout'
import { useShareExport } from './useShareExport'
import { useImportExport } from './useImportExport'
import { usePersistence } from './usePersistence'
import { generateStandaloneScript } from './useBugsCodeGenerator'
import type { GraphElement, NodeType, UnifiedModelData } from '../types'
import { examples, isUrl } from '../config/examples'

export interface PanelLayout {
  pos: { x: number; y: number }
  size: { width: number; height: number }
}

export function useEditorActions(
  elements: Ref<GraphElement[]>,
  generatedCode: Ref<string>,
  persistencePrefix?: string
) {
  const projectStore = useProjectStore()
  const graphStore = useGraphStore()
  const uiStore = useUiStore()
  const dataStore = useDataStore()
  const scriptStore = useScriptStore()
  const toast = useToast()

  const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
  const { smartFit, applyLayoutWithFit } = useGraphLayout()
  const { shareUrl, minifyGraph, generateShareLink } = useShareExport()
  const { importedGraphData, processGraphFile, clearImportedData } = useImportExport()
  const { getStoredGraphElements, getStoredDataContent } = usePersistence(persistencePrefix)

  const currentMode = ref<string>('select')
  const currentNodeType = ref<NodeType>('stochastic')

  const showNewProjectModal = ref(false)
  const newProjectName = ref('')
  const showNewGraphModal = ref(false)
  const newGraphName = ref('')
  const showAboutModal = ref(false)
  const showFaqModal = ref(false)
  const showValidationModal = ref(false)
  const showScriptSettingsModal = ref(false)
  const showExportModal = ref(false)
  const showStyleModal = ref(false)
  const showShareModal = ref(false)
  const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null)
  const graphImportInput = ref<HTMLInputElement | null>(null)
  const isDragOver = ref(false)

  const codePanelPos = reactive({ x: 0, y: 0 })
  const codePanelSize = reactive({ width: 400, height: 300 })
  const dataPanelPos = reactive({ x: 0, y: 0 })
  const dataPanelSize = reactive({ width: 400, height: 300 })

  const pinnedGraphTitle = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return null
    const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
    return graph ? graph.name : null
  })

  const isCodePanelOpen = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return false
    const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
    return !!graph?.showCodePanel
  })

  const isDataPanelOpen = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return false
    const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
    return !!graph?.showDataPanel
  })

  const toggleCodePanel = () => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return
    const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
    if (graph) {
      projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
        showCodePanel: !graph.showCodePanel,
      })
    }
  }

  const toggleDataPanel = () => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return
    const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
    if (graph) {
      projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
        showDataPanel: !graph.showDataPanel,
      })
    }
  }

  const handleUndo = () => {
    if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.undo()
  }

  const handleRedo = () => {
    if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.redo()
  }

  const handleZoomIn = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.zoom(cy.zoom() * 1.2)
    }
  }

  const handleZoomOut = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.zoom(cy.zoom() * 0.8)
    }
  }

  const handleFit = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) smartFit(cy, true)
    }
  }

  const handleGraphLayout = (layoutName: string) => {
    const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
    if (!cy) return
    applyLayoutWithFit(cy, layoutName)
    if (graphStore.currentGraphId)
      graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName)
  }

  const loadModelData = async (
    data: UnifiedModelData | Record<string, unknown>,
    name: string,
    sourceKey?: string,
    sourceMap?: {
      get: () => Record<string, string>
      set: (source: string, graphId: string) => void
    }
  ) => {
    if (!projectStore.currentProjectId) return

    const newGraphMeta = projectStore.addGraphToProject(
      projectStore.currentProjectId,
      (data as UnifiedModelData).name || name
    )
    if (!newGraphMeta) return

    if ((data as UnifiedModelData).elements) {
      graphStore.updateGraphElements(
        newGraphMeta.id,
        (data as UnifiedModelData).elements as GraphElement[]
      )
    } else if ((data as UnifiedModelData).graphJSON) {
      graphStore.updateGraphElements(
        newGraphMeta.id,
        (data as UnifiedModelData).graphJSON as GraphElement[]
      )
    }

    if ((data as UnifiedModelData).dataContent) {
      dataStore.updateGraphData(newGraphMeta.id, {
        content: (data as UnifiedModelData).dataContent || '',
      })
    } else if ((data as UnifiedModelData).data || (data as UnifiedModelData).inits) {
      const content = JSON.stringify(
        {
          data: (data as UnifiedModelData).data || {},
          inits: (data as UnifiedModelData).inits || {},
        },
        null,
        2
      )
      dataStore.updateGraphData(newGraphMeta.id, { content })
    }

    graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
    if ((data as UnifiedModelData).layout) {
      projectStore.updateGraphLayout(
        projectStore.currentProjectId,
        newGraphMeta.id,
        (data as UnifiedModelData).layout
      )
    }

    if (sourceKey && sourceMap) {
      sourceMap.set(sourceKey, newGraphMeta.id)
    }
    graphStore.selectGraph(newGraphMeta.id)

    return newGraphMeta.id
  }

  const handleLoadExample = async (
    exampleIdOrUrl: string,
    type: 'local' | 'prop' | 'standard' = 'standard',
    sourceMap?: {
      get: () => Record<string, string>
      set: (source: string, graphId: string) => void
    }
  ) => {
    if (!projectStore.currentProjectId) return

    toast.add({
      severity: 'info',
      summary: 'Loading...',
      detail: `Loading model: ${exampleIdOrUrl}`,
      life: 2000,
    })

    try {
      let modelData = null
      let modelName = 'Imported Model'
      let sourceDescription = ''

      if (type === 'local') {
        sourceDescription = 'Local File'
        const response = await fetch(exampleIdOrUrl)
        if (!response.ok) throw new Error(`Failed to load local file. Status: ${response.status}`)
        modelData = await response.json()
        modelName = modelData.name || exampleIdOrUrl
      } else if (isUrl(exampleIdOrUrl)) {
        sourceDescription = exampleIdOrUrl.toLowerCase().includes('github')
          ? 'GitHub Source'
          : 'External URL'
        const response = await fetch(exampleIdOrUrl)
        if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`)
        modelData = await response.json()
        modelName = modelData.name || 'Remote Model'
      } else {
        const config = examples.find((e) => e.id === exampleIdOrUrl)
        const turingUrl = `https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/examples/${exampleIdOrUrl}/model.json`

        if (config) {
          modelName = config.name
          try {
            const localUrl = `${import.meta.env.BASE_URL}examples/${config.id}/model.json`
            const response = await fetch(localUrl)
            if (response.ok) {
              modelData = await response.json()
              sourceDescription = 'Local Path'
            }
          } catch {
            /* fallthrough */
          }

          if (!modelData && config.url) {
            try {
              const response = await fetch(config.url)
              if (response.ok) {
                modelData = await response.json()
                sourceDescription = config.url.includes('github')
                  ? 'GitHub Source'
                  : 'Remote Source'
              }
            } catch {
              /* fallthrough */
            }
          }
        }

        if (!modelData) {
          try {
            const response = await fetch(turingUrl)
            if (response.ok) {
              modelData = await response.json()
              modelName = modelData.name || exampleIdOrUrl
              sourceDescription = 'Turing Repository'
            }
          } catch {
            /* fallthrough */
          }
        }

        if (!modelData) {
          throw new Error(`Model "${exampleIdOrUrl}" not found in any source.`)
        }
      }

      if (modelData) {
        await loadModelData(modelData, modelName, exampleIdOrUrl, sourceMap)
        toast.add({
          severity: 'success',
          summary: 'Loaded',
          detail: `${modelName} loaded from ${sourceDescription}`,
          life: 3000,
        })
      }
    } catch (error) {
      console.error('[DoodleBUGS] Load error:', error)
      toast.add({
        severity: 'error',
        summary: 'Load Failed',
        detail: error instanceof Error ? error.message : 'An unexpected error occurred.',
        life: 5000,
      })
      throw error
    }
  }

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

  const handleGenerateStandalone = () => {
    scriptStore.standaloneScript = getScriptContent()
    uiStore.setActiveRightTab('script')
    uiStore.isRightSidebarOpen = true
  }

  const handleDownloadBugs = () => {
    const blob = new Blob([generatedCode.value], { type: 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'model.bugs'
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  const handleDownloadScript = () => {
    const content = scriptStore.standaloneScript || getScriptContent()
    if (!content) return
    const blob = new Blob([content], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'model_script.jl'
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
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
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `graph.${currentExportType.value}`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    } catch (err) {
      console.error('Export failed', err)
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
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${graphMeta.name.replace(/[^a-z0-9]/gi, '_').toLowerCase()}.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  const handleElementSelected = (element: GraphElement | null, isEditMode = true) => {
    graphStore.setSelectedElement(element)
    if (element) {
      uiStore.setActiveRightTab('properties')
      if (isEditMode) {
        uiStore.isRightSidebarOpen = true
      }
    } else {
      if (!uiStore.isRightTabPinned && uiStore.isRightSidebarOpen) {
        uiStore.isRightSidebarOpen = false
      }
    }
  }

  const handleSelectNodeFromModal = (nodeId: string) => {
    const el = elements.value.find((e) => e.id === nodeId)
    if (el) {
      handleElementSelected(el)
      const cy = getCyInstance(graphStore.currentGraphId!)
      if (cy) {
        cy.elements().removeClass('cy-selected')
        const cyNode = cy.getElementById(nodeId)
        cyNode.addClass('cy-selected')
        cy.animate({ fit: { eles: cyNode, padding: 50 }, duration: 500 })
      }
    }
  }

  const handleShare = () => {
    if (!graphStore.currentGraphId) return
    shareUrl.value = ''
    showShareModal.value = true
  }

  const handleGenerateShareLink = async (
    options: { scope: 'current' | 'project' | 'custom'; selectedGraphIds?: string[] },
    baseUrlOverride?: string
  ) => {
    if (!projectStore.currentProject) return

    const getGraphDataForShare = (graphId: string) => {
      let graphElements: GraphElement[] = []
      let dataContent = '{}'
      let name = 'Graph'
      const graphMeta = projectStore.currentProject?.graphs.find((g) => g.id === graphId)
      if (graphMeta) name = graphMeta.name
      if (graphId === graphStore.currentGraphId) {
        graphElements = graphStore.currentGraphElements
        dataContent = dataStore.dataContent
      } else {
        graphElements = getStoredGraphElements(graphId) as GraphElement[]
        dataContent = getStoredDataContent(graphId)
      }
      return { name, elements: graphElements, dataContent }
    }

    let payload = {}
    if (options.scope === 'current') {
      const targetId = options.selectedGraphIds?.[0] || graphStore.currentGraphId
      if (!targetId) return
      const { name, elements: graphElements, dataContent } = getGraphDataForShare(targetId)
      payload = { v: 2, n: name, e: minifyGraph(graphElements), d: dataContent }
    } else {
      const targetIds =
        options.scope === 'project'
          ? projectStore.currentProject.graphs.map((g) => g.id)
          : options.selectedGraphIds || []
      const graphsData = targetIds.map((id) => {
        const { name, elements: graphElements, dataContent } = getGraphDataForShare(id)
        return { n: name, e: minifyGraph(graphElements), d: dataContent }
      })
      payload = { v: 3, pn: projectStore.currentProject.name, g: graphsData }
    }

    await generateShareLink(
      payload,
      baseUrlOverride ||
        (typeof window !== 'undefined'
          ? `${window.location.origin}${window.location.pathname}`
          : undefined)
    )
  }

  const createNewProject = () => {
    if (newProjectName.value.trim()) {
      projectStore.createProject(newProjectName.value.trim())
      showNewProjectModal.value = false
      newProjectName.value = ''
    }
  }

  const createNewGraph = () => {
    if (projectStore.currentProjectId && (newGraphName.value.trim() || importedGraphData.value)) {
      const name = newGraphName.value.trim() || importedGraphData.value?.name || 'New Graph'
      const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId, name)
      if (newGraphMeta && importedGraphData.value) {
        graphStore.updateGraphElements(
          newGraphMeta.id,
          importedGraphData.value.elements as GraphElement[]
        )
        if (importedGraphData.value.dataContent) {
          dataStore.updateGraphData(newGraphMeta.id, {
            content: importedGraphData.value.dataContent,
          })
        }
        graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
      } else if (newGraphMeta) {
        graphStore.selectGraph(newGraphMeta.id)
      }
      showNewGraphModal.value = false
      newGraphName.value = ''
      clearImportedData()
      if (graphImportInput.value) graphImportInput.value.value = ''
    }
  }

  const triggerGraphImport = () => graphImportInput.value?.click()

  const handleGraphImportFile = (event: Event) => {
    const file = (event.target as HTMLInputElement).files?.[0]
    if (file) {
      processGraphFile(file)
        .then((data) => {
          if (data && !newGraphName.value && data.name) {
            newGraphName.value = data.name + ' (Imported)'
          }
        })
        .catch((error) => alert(error.message || 'Failed to process graph file.'))
    }
  }

  const handleDrop = (event: DragEvent) => {
    isDragOver.value = false
    const file = event.dataTransfer?.files?.[0]
    if (file) {
      processGraphFile(file)
        .then((data) => {
          if (data && !newGraphName.value && data.name) {
            newGraphName.value = data.name + ' (Imported)'
          }
        })
        .catch((error) => alert(error.message || 'Failed to process graph file.'))
    }
  }

  return {
    currentMode,
    currentNodeType,
    showNewProjectModal,
    newProjectName,
    showNewGraphModal,
    newGraphName,
    showAboutModal,
    showFaqModal,
    showValidationModal,
    showScriptSettingsModal,
    showExportModal,
    showStyleModal,
    showShareModal,
    currentExportType,
    graphImportInput,
    isDragOver,
    codePanelPos,
    codePanelSize,
    dataPanelPos,
    dataPanelSize,
    pinnedGraphTitle,
    isCodePanelOpen,
    isDataPanelOpen,
    shareUrl,
    importedGraphData,

    toggleCodePanel,
    toggleDataPanel,
    handleUndo,
    handleRedo,
    handleZoomIn,
    handleZoomOut,
    handleFit,
    handleGraphLayout,
    loadModelData,
    handleLoadExample,
    getScriptContent,
    handleGenerateStandalone,
    handleDownloadBugs,
    handleDownloadScript,
    openExportModal,
    handleConfirmExport,
    handleExportJson,
    handleElementSelected,
    handleSelectNodeFromModal,
    handleShare,
    handleGenerateShareLink,
    createNewProject,
    createNewGraph,
    triggerGraphImport,
    handleGraphImportFile,
    handleDrop,
    clearImportedData,
    getCyInstance,
    getUndoRedoInstance,
    smartFit,
  }
}
