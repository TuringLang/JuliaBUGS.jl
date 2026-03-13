import { ref, computed, reactive } from 'vue'
import type { Ref } from 'vue'
import { useToast } from 'primevue/usetoast'
import { useProjectStore } from '../stores/projectStore'
import { useGraphStore } from '../stores/graphStore'
import { useUiStore } from '../stores/uiStore'
import { useDataStore } from '../stores/dataStore'
import { useScriptStore } from '../stores/scriptStore'
import { useShareExport } from './useShareExport'
import { useImportExport } from './useImportExport'
import { usePersistence } from './usePersistence'
import { useViewportActions } from './useViewportActions'
import { useFileExport } from './useFileExport'
import type { GraphElement, NodeType, UnifiedModelData } from '../types'
import { examples, isUrl } from '../config/examples'

const RESPONSIVE_BREAKPOINT = 768
const NODE_FOCUS_PADDING = 50
const NODE_FOCUS_DURATION = 500

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

  const {
    handleUndo,
    handleRedo,
    handleZoomIn,
    handleZoomOut,
    handleFit,
    handleGraphLayout,
    getCyInstance,
    getUndoRedoInstance,
    smartFit,
  } = useViewportActions()

  const {
    showExportModal,
    currentExportType,
    getScriptContent,
    handleDownloadBugs,
    handleDownloadScript,
    openExportModal,
    handleConfirmExport,
    handleExportJson,
  } = useFileExport(generatedCode)

  const { shareUrl, minifyGraph, generateShareLink } = useShareExport()
  const { importedGraphData, processGraphFile, clearImportedData } = useImportExport()
  const { getStoredGraphElements, getStoredDataContent, saveLastGraphId } =
    usePersistence(persistencePrefix)

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
  const showStyleModal = ref(false)
  const showShareModal = ref(false)
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

    const modelData = data as UnifiedModelData
    const newGraphMeta = projectStore.addGraphToProject(
      projectStore.currentProjectId,
      modelData.name || name
    )
    if (!newGraphMeta) return

    if (modelData.elements) {
      graphStore.updateGraphElements(newGraphMeta.id, modelData.elements as GraphElement[])
    } else if (modelData.graphJSON) {
      graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON as GraphElement[])
    }

    if (modelData.dataContent) {
      dataStore.updateGraphData(newGraphMeta.id, { content: modelData.dataContent || '' })
    } else if (modelData.data || modelData.inits) {
      const content = JSON.stringify(
        { data: modelData.data || {}, inits: modelData.inits || {} },
        null,
        2
      )
      dataStore.updateGraphData(newGraphMeta.id, { content })
    }

    graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
    if (modelData.layout) {
      projectStore.updateGraphLayout(
        projectStore.currentProjectId,
        newGraphMeta.id,
        modelData.layout
      )
    }

    if (sourceKey && sourceMap) {
      sourceMap.set(sourceKey, newGraphMeta.id)
    }
    graphStore.selectGraph(newGraphMeta.id)
    saveLastGraphId(newGraphMeta.id)

    return newGraphMeta.id
  }

  const handleLoadExample = async (
    exampleIdOrUrl: string,
    type: 'local' | 'standard' = 'standard',
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

  const handleGenerateStandalone = () => {
    scriptStore.standaloneScript = getScriptContent()
    uiStore.setActiveRightTab('script')
    uiStore.isRightSidebarOpen = true
  }

  const handleElementSelected = (element: GraphElement | null, isEditMode = true) => {
    graphStore.setSelectedElement(element)
    if (element) {
      if (!uiStore.isRightTabPinned) {
        uiStore.setActiveRightTab('properties')
        if (isEditMode && window.innerWidth >= RESPONSIVE_BREAKPOINT) {
          uiStore.isRightSidebarOpen = true
        }
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
      const graphId = graphStore.currentGraphId
      if (!graphId) return
      const cy = getCyInstance(graphId)
      if (cy) {
        cy.elements().removeClass('cy-selected')
        const cyNode = cy.getElementById(nodeId)
        cyNode.addClass('cy-selected')
        cy.animate({
          fit: { eles: cyNode, padding: NODE_FOCUS_PADDING },
          duration: NODE_FOCUS_DURATION,
        })
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
      // Minify data content to reduce share URL size
      try {
        dataContent = JSON.stringify(JSON.parse(dataContent))
      } catch {
        /* keep original if not valid JSON */
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
