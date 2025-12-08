<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, reactive } from 'vue'
import { storeToRefs } from 'pinia'
import Toast from 'primevue/toast'

import GraphEditor from './components/canvas/GraphEditor.vue'
import FloatingBottomToolbar from './components/canvas/FloatingBottomToolbar.vue'
import FloatingPanel from './components/common/FloatingPanel.vue'
import LeftSidebar from './components/layouts/LeftSidebar.vue'
import RightSidebar from './components/layouts/RightSidebar.vue'
import CodePreviewPanel from './components/panels/CodePreviewPanel.vue'
import DataInputPanel from './components/panels/DataInputPanel.vue'
import AboutModal from './components/layouts/AboutModal.vue'
import FaqModal from './components/layouts/FaqModal.vue'
import ExportModal from './components/layouts/ExportModal.vue'
import GraphStyleModal from './components/layouts/GraphStyleModal.vue'
import ShareModal from './components/layouts/ShareModal.vue'
import ValidationIssuesModal from './components/layouts/ValidationIssuesModal.vue'
import BaseModal from './components/common/BaseModal.vue'
import DebugPanel from './components/common/DebugPanel.vue'
import BaseButton from './components/ui/BaseButton.vue'
import BaseInput from './components/ui/BaseInput.vue'
import ScriptSettingsPanel from './components/panels/ScriptSettingsPanel.vue'

import { useProjectStore } from './stores/projectStore'
import { useGraphStore } from './stores/graphStore'
import { useUiStore } from './stores/uiStore'
import { useDataStore } from './stores/dataStore'
import { useScriptStore } from './stores/scriptStore'
import { useGraphElements } from './composables/useGraphElements'
import { useBugsCodeGenerator, generateStandaloneScript } from './composables/useBugsCodeGenerator'
import { useGraphValidator } from './composables/useGraphValidator'
import { useGraphInstance } from './composables/useGraphInstance'
import { useGraphLayout } from './composables/useGraphLayout'
import { usePersistence } from './composables/usePersistence'
import { useShareExport } from './composables/useShareExport'
import { useImportExport } from './composables/useImportExport'
import type { NodeType, GraphElement, ExampleModel } from './types'

const props = defineProps<{
  initialState?: string
}>()

const emit = defineEmits<{
  (e: 'state-update', payload: string): void
  (e: 'code-update', payload: string): void
}>()

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()

// Ensure sidebars are closed by default for the widget (before any rendering)
uiStore.isLeftSidebarOpen = false
uiStore.isRightSidebarOpen = false

// Widget-specific flag to prevent sidebar flash during initialization
const widgetInitialized = ref(false)

const currentMode = ref('select')
const currentNodeType = ref<NodeType>('stochastic')

const showAboutModal = ref(false)
const showFaqModal = ref(false)
const showExportModal = ref(false)
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null)
const showStyleModal = ref(false)
const showShareModal = ref(false)
const showValidationModal = ref(false)
const showScriptSettingsModal = ref(false)
const showNewProjectModal = ref(false)
const showNewGraphModal = ref(false)
const newProjectName = ref('')
const newGraphName = ref('')

// Panel positions and sizes (will be loaded from localStorage or use defaults)
const codePanelPos = reactive({ x: 0, y: 0 })
const codePanelSize = reactive({ width: 400, height: 300 })
const dataPanelPos = reactive({ x: 0, y: 0 })
const dataPanelSize = reactive({ width: 400, height: 300 })

// Import Graph State
const graphImportInput = ref<HTMLInputElement | null>(null)
const isDragOver = ref(false)

// UI Dragging State (for performance optimization)
const isDraggingUI = ref(false)

// Computed window width for responsive positioning
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 1920)

// Flag to prevent premature canvas rendering
const isInitialized = ref(false)

// LocalStorage key for widget UI state
const WIDGET_UI_STATE_KEY = 'doodlebugs-widget-ui-state'

const { loadUIState, saveUIState, getStoredGraphElements, getStoredDataContent } =
  usePersistence('doodlebugs')

const saveWidgetUIState = () => {
  saveUIState(WIDGET_UI_STATE_KEY, {
    leftSidebar: {
      open: uiStore.isLeftSidebarOpen,
      x: leftDrag.x.value,
      y: leftDrag.y.value,
    },
    rightSidebar: {
      open: uiStore.isRightSidebarOpen,
      x: rightDrag.x.value,
      y: rightDrag.y.value,
    },
    codePanel: {
      open: isCodePanelOpen.value,
      x: codePanelPos.x,
      y: codePanelPos.y,
      width: codePanelSize.width,
      height: codePanelSize.height,
    },
    dataPanel: {
      open: isDataPanelOpen.value,
      x: dataPanelPos.x,
      y: dataPanelPos.y,
      width: dataPanelSize.width,
      height: dataPanelSize.height,
    },
    currentGraphId: graphStore.currentGraphId || undefined,
  })
}

const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { parsedGraphData } = storeToRefs(dataStore)
const { generatedCode } = useBugsCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
const { smartFit, applyLayoutWithFit } = useGraphLayout()
const { shareUrl, minifyGraph, generateShareLink } = useShareExport()
const { importedGraphData, processGraphFile, clearImportedData } = useImportExport()

// CSS for teleported widget content - injected into document head
// This is needed because the widget's shadow DOM styles don't reach teleported elements
const WIDGET_STYLES_ID = 'doodlebugs-widget-teleport-styles'

const widgetTeleportCSS = `
/* DoodleBUGS Widget - Teleported Content Styles */
/* These styles override host page styles to maintain widget appearance */

/* Base styles for all teleported containers - prevents host page style leakage */
.db-ui-overlay,
.db-sidebar-wrapper,
.db-floating-panel,
.p-dialog,
.p-popover,
.p-toast {
  font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  font-size: 12px;
  line-height: 1.5;
  letter-spacing: normal;
  font-weight: 400;
  color: var(--theme-text-primary, #1f2937);
  box-sizing: border-box;
}

/* UI Overlay positioning */
.db-ui-overlay {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  z-index: 10;
  pointer-events: none;
}

/* Sidebar wrapper positioning */
.db-sidebar-wrapper {
  position: fixed;
  pointer-events: auto;
  z-index: 200;
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  gap: 4px;
  left: 0;
  top: 0;
}
`

const injectWidgetStyles = () => {
  // Check if styles are already injected
  if (document.getElementById(WIDGET_STYLES_ID)) return

  const styleElement = document.createElement('style')
  styleElement.id = WIDGET_STYLES_ID
  styleElement.textContent = widgetTeleportCSS
  document.head.appendChild(styleElement)
}

const removeWidgetStyles = () => {
  const styleElement = document.getElementById(WIDGET_STYLES_ID)
  if (styleElement) {
    styleElement.remove()
  }
}

const initGraph = () => {
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project')
  }

  if (!projectStore.currentProjectId && projectStore.projects.length > 0) {
    projectStore.selectProject(projectStore.projects[0].id)
  }

  const proj = projectStore.currentProject
  if (!proj) return

  if (proj.graphs.length === 0) {
    projectStore.addGraphToProject(proj.id, 'Model 1')
  }

  if (proj.graphs.length > 0 && !graphStore.currentGraphId) {
    graphStore.selectGraph(proj.graphs[0].id)
  }

  if (graphStore.currentGraphId && !graphStore.graphContents.has(graphStore.currentGraphId)) {
    graphStore.createNewGraphContent(graphStore.currentGraphId)
  }
}

onMounted(() => {
  graphStore.selectGraph(undefined as unknown as string)

  projectStore.loadProjects()

  if (props.initialState) {
    try {
      const state = JSON.parse(props.initialState)
      if (state.project) projectStore.importState(state.project)
      if (state.graphs)
        state.graphs.forEach(
          (g: {
            graphId: string
            elements: GraphElement[]
            lastLayout?: string
            zoom?: number
            pan?: { x: number; y: number }
          }) => graphStore.graphContents.set(g.graphId, g)
        )
      if (state.data)
        state.data.forEach((d: { graphId: string; content: string }) =>
          dataStore.updateGraphData(d.graphId, { content: d.content })
        )
    } catch (e) {
      console.error('DoodleBUGS: Failed to parse state', e)
    }
  }

  const savedUIState = loadUIState(WIDGET_UI_STATE_KEY)
  if (savedUIState) {
    if (savedUIState.leftSidebar) {
      leftDrag.x.value = savedUIState.leftSidebar.x
      leftDrag.y.value = savedUIState.leftSidebar.y
      uiStore.isLeftSidebarOpen = savedUIState.leftSidebar.open
    }
    if (savedUIState.rightSidebar) {
      rightDrag.x.value = savedUIState.rightSidebar.x
      rightDrag.y.value = savedUIState.rightSidebar.y
      uiStore.isRightSidebarOpen = savedUIState.rightSidebar.open
    }
    if (savedUIState.codePanel) {
      codePanelPos.x = savedUIState.codePanel.x
      codePanelPos.y = savedUIState.codePanel.y
      codePanelSize.width = savedUIState.codePanel.width
      codePanelSize.height = savedUIState.codePanel.height
      // Note: open state now managed per-graph, not from savedUIState
    }
    if (savedUIState.dataPanel) {
      dataPanelPos.x = savedUIState.dataPanel.x
      dataPanelPos.y = savedUIState.dataPanel.y
      dataPanelSize.width = savedUIState.dataPanel.width
      dataPanelSize.height = savedUIState.dataPanel.height
      // Note: open state now managed per-graph, not from savedUIState
    }
    if (savedUIState.currentGraphId) {
      graphStore.selectGraph(savedUIState.currentGraphId)
    }
  }

  initGraph()
  isInitialized.value = true
  widgetInitialized.value = true
  validateGraph()

  // Inject styles into document head for teleported content
  // This is necessary because custom element shadow DOM styles don't reach teleported content
  injectWidgetStyles()

  // Update window width on resize
  const handleResize = () => {
    windowWidth.value = window.innerWidth
    // Update right sidebar position on resize
    rightDrag.x.value = window.innerWidth - 320 - 20
  }
  window.addEventListener('resize', handleResize)

  onUnmounted(() => {
    window.removeEventListener('resize', handleResize)
  })
})

onUnmounted(() => {
  document.body.classList.remove('db-dark-mode')
  document.documentElement.classList.remove('db-dark-mode')
  removeWidgetStyles()
})

watch(
  [() => projectStore.projects, () => graphStore.graphContents, () => dataStore.dataContent],
  () => {
    const fullState = {
      project: projectStore.exportState(),
      graphs: Array.from(graphStore.graphContents.entries()).map(([, v]) => v),
      data: Array.from(graphStore.graphContents.keys()).map((gid) => ({
        graphId: gid,
        content: dataStore.getGraphData(gid).content,
      })),
    }
    emit('state-update', JSON.stringify(fullState))
  },
  { deep: true }
)

watch(generatedCode, (code) => {
  emit('code-update', code)
})

// Code Panel Visibility (Per-Graph State)
const isCodePanelOpen = computed(() => {
  if (!projectStore.currentProject || !graphStore.currentGraphId) return false
  const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
  return !!graph?.showCodePanel
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

// Data Panel Visibility (Per-Graph State)
const isDataPanelOpen = computed(() => {
  if (!projectStore.currentProject || !graphStore.currentGraphId) return false
  const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
  return !!graph?.showDataPanel
})

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
  if (graphStore.currentGraphId)
    getCyInstance(graphStore.currentGraphId)?.zoom(
      getCyInstance(graphStore.currentGraphId)!.zoom() * 1.2
    )
}
const handleZoomOut = () => {
  if (graphStore.currentGraphId)
    getCyInstance(graphStore.currentGraphId)?.zoom(
      getCyInstance(graphStore.currentGraphId)!.zoom() * 0.8
    )
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
  if (graphStore.currentGraphId) graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName)
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

const getScriptContent = () => {
  return generateStandaloneScript({
    modelCode: generatedCode.value,
    data: dataStore.parsedGraphData.data || {},
    inits: dataStore.parsedGraphData.inits || {},
    settings: {
      n_samples: scriptStore.samplerSettings.n_samples,
      n_adapts: scriptStore.samplerSettings.n_adapts,
      n_chains: scriptStore.samplerSettings.n_chains,
      seed: scriptStore.samplerSettings.seed ?? undefined,
    },
  })
}

const handleGenerateStandalone = () => {
  const script = getScriptContent()
  scriptStore.standaloneScript = script
  uiStore.setActiveRightTab('script')
  uiStore.isRightSidebarOpen = true
}

const handleDownloadBugs = () => {
  const content = generatedCode.value
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
  const fileName = 'model.bugs'
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = fileName
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

watch(
  [generatedCode, () => dataStore.parsedGraphData, () => scriptStore.samplerSettings],
  () => {
    if (scriptStore.standaloneScript || uiStore.activeRightTab === 'script') {
      scriptStore.standaloneScript = getScriptContent()
    }
  },
  { deep: true }
)

const handleNewProject = () => {
  newProjectName.value = `Project ${projectStore.projects.length + 1}`
  showNewProjectModal.value = true
}

const createNewProject = () => {
  if (newProjectName.value.trim()) {
    projectStore.createProject(newProjectName.value.trim())
    showNewProjectModal.value = false
    newProjectName.value = ''
  }
}

const handleNewGraph = () => {
  if (projectStore.currentProjectId && projectStore.currentProject) {
    newGraphName.value = `Graph ${projectStore.currentProject.graphs.length + 1}`
    showNewGraphModal.value = true
  }
}

const createNewGraph = () => {
  if (projectStore.currentProjectId && (newGraphName.value.trim() || importedGraphData.value)) {
    const name = newGraphName.value.trim() || importedGraphData.value?.name || 'New Graph'
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId!, name)

    if (newGraphMeta && importedGraphData.value) {
      // Populate with imported data
      graphStore.updateGraphElements(
        newGraphMeta.id,
        importedGraphData.value.elements as GraphElement[]
      )

      if (importedGraphData.value.dataContent) {
        dataStore.updateGraphData(newGraphMeta.id, { content: importedGraphData.value.dataContent })
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

const triggerGraphImport = () => {
  graphImportInput.value?.click()
}

const handleGraphImportFile = (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (file) {
    processGraphFile(file)
      .then((data) => {
        if (data && !newGraphName.value && data.name) {
          newGraphName.value = data.name + ' (Imported)'
        }
      })
      .catch((error) => {
        alert(error.message || 'Failed to process graph file.')
      })
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
      .catch((error) => {
        alert(error.message || 'Failed to process graph file.')
      })
  }
}

const handleLoadExample = async (exampleKey: string) => {
  if (!projectStore.currentProjectId) return
  try {
    const baseUrl = import.meta.env.BASE_URL
    const modelResponse = await fetch(`${baseUrl}examples/${exampleKey}/model.json`)
    if (!modelResponse.ok)
      throw new Error(`Could not fetch example model: ${modelResponse.statusText}`)

    const modelData: ExampleModel = await modelResponse.json()
    const newGraphMeta = projectStore.addGraphToProject(
      projectStore.currentProjectId,
      modelData.name
    )
    if (!newGraphMeta) return

    graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON)
    graphStore.updateGraphLayout(newGraphMeta.id, 'preset')

    const jsonDataResponse = await fetch(`${baseUrl}examples/${exampleKey}/data.json`)
    if (jsonDataResponse.ok) {
      const fullData = await jsonDataResponse.json()
      dataStore.dataContent = JSON.stringify(
        { data: fullData.data || {}, inits: fullData.inits || {} },
        null,
        2
      )
    }
    dataStore.updateGraphData(newGraphMeta.id, dataStore.getGraphData(newGraphMeta.id))
    graphStore.selectGraph(newGraphMeta.id)
  } catch (error) {
    console.error('Failed to load example model:', error)
  }
}

const handleShare = () => {
  if (!graphStore.currentGraphId) return
  shareUrl.value = ''
  showShareModal.value = true
}

const handleGenerateShareLink = async (options: {
  scope: 'current' | 'project' | 'custom'
  selectedGraphIds?: string[]
}) => {
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
  await generateShareLink(payload)
}

const handleShareGraph = () => {
  shareUrl.value = ''
  showShareModal.value = true
}

const handleShareProjectUrl = () => {
  shareUrl.value = ''
  showShareModal.value = true
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

const handleElementSelected = (element: GraphElement | null) => {
  graphStore.setSelectedElement(element)
  if (element) {
    uiStore.setActiveRightTab('properties')
    uiStore.isRightSidebarOpen = true
  } else {
    if (!uiStore.isRightTabPinned && uiStore.isRightSidebarOpen) {
      uiStore.isRightSidebarOpen = false
    }
  }
}

const handleSelectNodeFromModal = (nodeId: string) => {
  const el = elements.value.find((e) => e.id === nodeId)
  if (el) handleElementSelected(el)
}

const {
  isLeftSidebarOpen,
  isRightSidebarOpen,
  isGridEnabled,
  gridSize,
  showZoomControls,
  showDebugPanel,
  activeLeftAccordionTabs,
  isDetachModeActive,
  showDetachModeControl,
  isDarkMode,
  canvasGridStyle,
} = storeToRefs(uiStore)

const pinnedGraphTitle = computed(
  () =>
    projectStore.currentProject?.graphs.find((g) => g.id === graphStore.currentGraphId)?.name ||
    'Graph'
)
const isModelValid = computed(() => validationErrors.value.size === 0)

// Sync dark mode class to html element for global.css selectors (like MainLayout does)
// This makes html.db-dark-mode selectors work for teleported content
watch(
  isDarkMode,
  (val) => {
    const html = document.documentElement
    if (val) {
      html.classList.add('db-dark-mode')
      document.body.classList.add('db-dark-mode')
    } else {
      html.classList.remove('db-dark-mode')
      document.body.classList.remove('db-dark-mode')
    }
  },
  { immediate: true }
)

const useDrag = (initialX: number, initialY: number) => {
  const x = ref(initialX)
  const y = ref(initialY)
  const isDragging = ref(false)
  const startX = ref(0)
  const startY = ref(0)
  const dragThreshold = 3
  let initialDragX = 0
  let initialDragY = 0
  let animationFrameId: number | null = null

  const startDrag = (e: MouseEvent | TouchEvent) => {
    isDragging.value = true
    isDraggingUI.value = true // Disable canvas pointer events during drag
    const clientX = e instanceof MouseEvent ? e.clientX : e.touches[0].clientX
    const clientY = e instanceof MouseEvent ? e.clientY : e.touches[0].clientY

    startX.value = clientX - x.value
    startY.value = clientY - y.value
    initialDragX = clientX
    initialDragY = clientY

    if (e instanceof MouseEvent) {
      window.addEventListener('mousemove', onMouseMove)
      window.addEventListener('mouseup', onMouseUp)
    } else {
      window.addEventListener('touchmove', onTouchMove, { passive: false })
      window.addEventListener('touchend', onTouchEnd)
    }
  }

  const onMouseMove = (e: MouseEvent) => {
    if (!isDragging.value) return
    if (animationFrameId) cancelAnimationFrame(animationFrameId)

    animationFrameId = requestAnimationFrame(() => {
      x.value = e.clientX - startX.value
      y.value = e.clientY - startY.value
    })
  }

  const onTouchMove = (e: TouchEvent) => {
    if (!isDragging.value) return
    e.preventDefault()
    if (animationFrameId) cancelAnimationFrame(animationFrameId)

    animationFrameId = requestAnimationFrame(() => {
      x.value = e.touches[0].clientX - startX.value
      y.value = e.touches[0].clientY - startY.value
    })
  }

  const finishDrag = (clientX: number, clientY: number) => {
    isDragging.value = false
    isDraggingUI.value = false // Re-enable canvas pointer events
    if (animationFrameId) cancelAnimationFrame(animationFrameId)
    const dist = Math.hypot(clientX - initialDragX, clientY - initialDragY)
    return dist < dragThreshold
  }

  const onMouseUp = (e: MouseEvent) => {
    const isClick = finishDrag(e.clientX, e.clientY)
    window.removeEventListener('mousemove', onMouseMove)
    window.removeEventListener('mouseup', onMouseUp)
    return isClick
  }

  const onTouchEnd = (e: TouchEvent) => {
    const touch = e.changedTouches[0]
    finishDrag(touch.clientX, touch.clientY)
    window.removeEventListener('touchmove', onTouchMove)
    window.removeEventListener('touchend', onTouchEnd)
  }

  return {
    x,
    y,
    startDrag,
    onMouseUp,
    style: computed(() => ({
      // Use transform for smooth 60fps movement
      transform: `translate3d(${x.value}px, ${y.value}px, 0)`,
      // Force top/left to 0 so translate3d works from the origin
      // This assumes the sidebar wrappers have 'position: fixed'
      left: '0px',
      top: '0px',
    })),
  }
}

const leftDrag = useDrag(20, 20)
const rightDrag = useDrag(typeof window !== 'undefined' ? window.innerWidth - 320 - 20 : 1580, 20)

// Watch for changes to UI state and save to localStorage
watch(
  [
    () => leftDrag.x.value,
    () => leftDrag.y.value,
    () => rightDrag.x.value,
    () => rightDrag.y.value,
    () => uiStore.isLeftSidebarOpen,
    () => uiStore.isRightSidebarOpen,
    isCodePanelOpen,
    isDataPanelOpen,
    () => codePanelPos.x,
    () => codePanelPos.y,
    () => codePanelSize.width,
    () => codePanelSize.height,
    () => dataPanelPos.x,
    () => dataPanelPos.y,
    () => dataPanelSize.width,
    () => dataPanelSize.height,
    () => graphStore.currentGraphId,
  ],
  () => {
    saveWidgetUIState()
  },
  { deep: true }
)

const onLeftHeaderDragStart = (e: MouseEvent | TouchEvent) => {
  leftDrag.startDrag(e)
  if (e instanceof MouseEvent) {
    const originalMouseUp = leftDrag.onMouseUp
    // Hijack the mouse up to toggle if it was a click
    const handleUp = (upEvent: MouseEvent) => {
      const isClick = originalMouseUp(upEvent)
      if (isClick) {
        uiStore.toggleLeftSidebar()
      }
      window.removeEventListener('mouseup', handleUp)
    }
    window.addEventListener('mouseup', handleUp)
  }
}

const onRightHeaderDragStart = (e: MouseEvent | TouchEvent) => {
  rightDrag.startDrag(e)
  if (e instanceof MouseEvent) {
    const originalMouseUp = rightDrag.onMouseUp
    const handleUp = (upEvent: MouseEvent) => {
      const isClick = originalMouseUp(upEvent)
      if (isClick) {
        uiStore.toggleRightSidebar()
      }
      window.removeEventListener('mouseup', handleUp)
    }
    window.addEventListener('mouseup', handleUp)
  }
}

// Logic to handle toolbar navigation clicks
const handleToolbarNavigation = (view: string) => {
  if (view === 'project') {
    if (
      uiStore.isLeftSidebarOpen &&
      activeLeftAccordionTabs.value.includes('project') &&
      activeLeftAccordionTabs.value.length === 1
    ) {
      uiStore.isLeftSidebarOpen = false
    } else {
      uiStore.isLeftSidebarOpen = true
      activeLeftAccordionTabs.value = ['project']
    }
  } else if (view === 'view') {
    if (
      uiStore.isLeftSidebarOpen &&
      activeLeftAccordionTabs.value.includes('view') &&
      activeLeftAccordionTabs.value.length === 1
    ) {
      uiStore.isLeftSidebarOpen = false
    } else {
      uiStore.isLeftSidebarOpen = true
      activeLeftAccordionTabs.value = ['view']
    }
  } else if (view === 'help') {
    if (uiStore.isLeftSidebarOpen && activeLeftAccordionTabs.value.includes('help')) {
      uiStore.isLeftSidebarOpen = false
    } else {
      uiStore.isLeftSidebarOpen = true
      activeLeftAccordionTabs.value = ['help', 'devtools']
    }
  } else if (view === 'export') {
    // Open Right Sidebar Export tab
    if (uiStore.isRightSidebarOpen && uiStore.activeRightTab === 'export') {
      uiStore.isRightSidebarOpen = false
    } else {
      uiStore.isRightSidebarOpen = true
      uiStore.setActiveRightTab('export')
    }
  }
}

const handleUIInteractionStart = () => {
  isDraggingUI.value = true
}

const handleUIInteractionEnd = () => {
  isDraggingUI.value = false
}
</script>

<template>
  <div class="db-widget-root" :class="{ 'db-dark-mode': isDarkMode }"
    style="width: 100%; height: 100%; position: relative; overflow: hidden">
    <div class="db-canvas-layer" :style="{
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      width: '100%',
      height: '100%',
      pointerEvents: isDraggingUI ? 'none' : 'auto',
    }">
      <GraphEditor v-if="isInitialized && graphStore.currentGraphId" :key="graphStore.currentGraphId"
        :graph-id="graphStore.currentGraphId" :is-grid-enabled="isGridEnabled" :grid-size="gridSize"
        :grid-style="canvasGridStyle" :current-mode="currentMode" :elements="elements"
        :current-node-type="currentNodeType" :validation-errors="validationErrors" :show-zoom-controls="false"
        @update:current-mode="currentMode = $event" @update:current-node-type="currentNodeType = $event"
        @element-selected="handleElementSelected"
        @layout-updated="(name) => graphStore.updateGraphLayout(graphStore.currentGraphId!, name)" @viewport-changed="
          (v) => graphStore.updateGraphViewport(graphStore.currentGraphId!, v.zoom, v.pan)
        " @update:is-grid-enabled="isGridEnabled = $event" @update:grid-size="gridSize = $event" />
      <div v-else class="db-empty-placeholder">
        <div class="db-msg-box">
          <i class="fas fa-spinner fa-spin"></i>
          <p>Initializing...</p>
        </div>
      </div>
    </div>

    <Teleport to="body">
      <div class="db-ui-overlay" :class="{ 'db-dark-mode': isDarkMode, 'db-widget-ready': widgetInitialized }">
        <Toast position="top-center" />

        <!-- Left Sidebar (Floating) -->
        <div v-if="widgetInitialized && isLeftSidebarOpen" class="db-sidebar-wrapper db-left"
          :style="leftDrag.style.value">
          <LeftSidebar v-show="isLeftSidebarOpen" :activeAccordionTabs="activeLeftAccordionTabs"
            @update:activeAccordionTabs="activeLeftAccordionTabs = $event"
            :projectName="projectStore.currentProject?.name || 'Project'" :pinnedGraphTitle="pinnedGraphTitle"
            :isGridEnabled="isGridEnabled" :gridSize="gridSize" :showZoomControls="showZoomControls"
            :showDebugPanel="showDebugPanel" :isCodePanelOpen="isCodePanelOpen" :isDetachModeActive="isDetachModeActive"
            :showDetachModeControl="showDetachModeControl" :enableDrag="true"
            @toggle-left-sidebar="uiStore.toggleLeftSidebar" @new-project="handleNewProject" @new-graph="handleNewGraph"
            @update:currentMode="currentMode = $event" @update:currentNodeType="currentNodeType = $event"
            @update:isGridEnabled="isGridEnabled = $event" @update:gridSize="gridSize = $event"
            @update:showZoomControls="showZoomControls = $event" @update:showDebugPanel="showDebugPanel = $event"
            @update:isDetachModeActive="isDetachModeActive = $event"
            @update:show-detach-mode-control="showDetachModeControl = $event" @toggle-code-panel="toggleCodePanel"
            @load-example="handleLoadExample" @open-about-modal="showAboutModal = true"
            @open-faq-modal="showFaqModal = true" @toggle-dark-mode="uiStore.toggleDarkMode"
            @share-graph="handleShareGraph" @share-project-url="handleShareProjectUrl"
            @header-drag-start="onLeftHeaderDragStart" />
        </div>

        <div v-if="widgetInitialized && isRightSidebarOpen" class="db-sidebar-wrapper db-right"
          :style="rightDrag.style.value">
          <RightSidebar v-show="isRightSidebarOpen" :selectedElement="selectedElement"
            :validationErrors="validationErrors" :isModelValid="isModelValid" :enableDrag="true"
            @toggle-right-sidebar="uiStore.toggleRightSidebar" @update-element="updateElement"
            @delete-element="deleteElement" @show-validation-issues="showValidationModal = true"
            @open-script-settings="showScriptSettingsModal = true" @download-script="handleDownloadScript"
            @generate-script="handleGenerateStandalone" @share="handleShare" @open-export-modal="openExportModal"
            @export-json="handleExportJson" @header-drag-start="onRightHeaderDragStart" />
        </div>

        <FloatingBottomToolbar :current-mode="currentMode" :current-node-type="currentNodeType"
          :show-zoom-controls="showZoomControls" :show-code-panel="isCodePanelOpen" :show-data-panel="isDataPanelOpen"
          :is-detach-mode-active="isDetachModeActive" :show-detach-mode-control="showDetachModeControl"
          :is-widget="true" @update:current-mode="currentMode = $event"
          @update:current-node-type="currentNodeType = $event" @undo="handleUndo" @redo="handleRedo"
          @zoom-in="handleZoomIn" @zoom-out="handleZoomOut" @fit="handleFit" @layout-graph="handleGraphLayout"
          @toggle-code-panel="toggleCodePanel" @toggle-data-panel="toggleDataPanel"
          @toggle-detach-mode="uiStore.toggleDetachMode" @open-style-modal="showStyleModal = true" @share="handleShare"
          @nav="handleToolbarNavigation" @drag-start="handleUIInteractionStart" @drag-end="handleUIInteractionEnd" />

        <FloatingPanel title="BUGS Code Preview" icon="fas fa-code" :is-open="isCodePanelOpen"
          :default-width="codePanelSize.width" :default-height="codePanelSize.height" :default-x="codePanelPos.x"
          :default-y="codePanelPos.y" :show-download="true" @close="toggleCodePanel" @download="handleDownloadBugs"
          @drag-start="handleUIInteractionStart" @drag-end="
            (pos) => {
              codePanelPos.x = pos.x
              codePanelPos.y = pos.y
              handleUIInteractionEnd()
            }
          " @resize-start="handleUIInteractionStart" @resize-end="
            (size) => {
              codePanelSize.width = size.width
              codePanelSize.height = size.height
              handleUIInteractionEnd()
            }
          ">
          <CodePreviewPanel :is-active="isCodePanelOpen" />
        </FloatingPanel>

        <FloatingPanel title="Data & Inits" icon="fas fa-database" badge="JSON" :is-open="isDataPanelOpen"
          :default-width="dataPanelSize.width" :default-height="dataPanelSize.height"
          :default-x="dataPanelPos.x || windowWidth - 420" :default-y="dataPanelPos.y" @close="toggleDataPanel"
          @drag-start="handleUIInteractionStart" @drag-end="
            (pos) => {
              dataPanelPos.x = pos.x
              dataPanelPos.y = pos.y
              handleUIInteractionEnd()
            }
          " @resize-start="handleUIInteractionStart" @resize-end="
            (size) => {
              dataPanelSize.width = size.width
              dataPanelSize.height = size.height
              handleUIInteractionEnd()
            }
          ">
          <DataInputPanel :is-active="isDataPanelOpen" />
        </FloatingPanel>

        <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
        <FaqModal :is-open="showFaqModal" @close="showFaqModal = false" />
        <ExportModal :is-open="showExportModal" :export-type="currentExportType" @close="showExportModal = false"
          @confirm-export="handleConfirmExport" />
        <GraphStyleModal :is-open="showStyleModal" @close="showStyleModal = false" />
        <ShareModal :is-open="showShareModal" :url="shareUrl" :project="projectStore.currentProject"
          :current-graph-id="graphStore.currentGraphId" @close="showShareModal = false"
          @generate="handleGenerateShareLink" />
        <ValidationIssuesModal :is-open="showValidationModal" :validation-errors="validationErrors" :elements="elements"
          @close="showValidationModal = false" @select-node="handleSelectNodeFromModal" />
        <BaseModal :is-open="showScriptSettingsModal" @close="showScriptSettingsModal = false">
          <template #header>
            <h3>Script Settings</h3>
          </template>
          <template #body>
            <ScriptSettingsPanel />
          </template>
          <template #footer>
            <BaseButton @click="showScriptSettingsModal = false">Done</BaseButton>
          </template>
        </BaseModal>

        <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
          <template #header>
            <h3>Create New Project</h3>
          </template>
          <template #body>
            <div class="db-modal-form-row">
              <label>Project Name:</label>
              <BaseInput v-model="newProjectName" placeholder="Enter project name" @keyup.enter="createNewProject" />
            </div>
          </template>
          <template #footer>
            <BaseButton @click="createNewProject" type="primary">Create</BaseButton>
          </template>
        </BaseModal>

        <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
          <template #header>
            <h3>Create New Graph</h3>
          </template>
          <template #body>
            <div class="flex flex-col gap-2">
              <div class="db-form-group">
                <label for="new-graph-name">Graph Name</label>
                <BaseInput id="new-graph-name" v-model="newGraphName" placeholder="Enter a name for your graph"
                  @keyup.enter="createNewGraph" />
              </div>

              <div class="db-import-section">
                <label class="db-section-label">Import from JSON (Optional)</label>

                <div class="db-drop-zone" :class="{ 'db-loaded': importedGraphData, 'db-drag-over': isDragOver }"
                  @click="triggerGraphImport" @dragover.prevent="isDragOver = true"
                  @dragleave.prevent="isDragOver = false" @drop.prevent="handleDrop">
                  <input type="file" ref="graphImportInput" accept=".json" @change="handleGraphImportFile"
                    class="db-hidden-input" />

                  <div v-if="!importedGraphData" class="db-drop-zone-content">
                    <div class="db-icon-circle">
                      <i class="fas fa-file-import"></i>
                    </div>
                    <div class="db-text-content">
                      <span class="db-action-text">Click or Drag & Drop JSON file</span>
                      <small class="db-sub-text">Restore a previously exported graph</small>
                    </div>
                  </div>

                  <div v-else class="db-drop-zone-content db-success">
                    <div class="db-icon-circle db-success">
                      <i class="fas fa-check"></i>
                    </div>
                    <div class="db-text-content">
                      <span class="db-action-text">File Loaded Successfully</span>
                      <small class="db-sub-text">{{
                        importedGraphData.name || 'Untitled Graph'
                      }}</small>
                    </div>
                    <button class="db-remove-file-btn" @click.stop="clearImportedData" title="Remove file">
                      <i class="fas fa-times"></i>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </template>
          <template #footer>
            <BaseButton @click="createNewGraph" type="primary">Create Graph</BaseButton>
          </template>
        </BaseModal>

        <DebugPanel v-if="showDebugPanel" @close="showDebugPanel = false" />
      </div>
    </Teleport>
  </div>
</template>

<style>
.db-widget-root {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background: var(--theme-bg-canvas);
  z-index: 0;
  display: flex;
  flex-direction: column;

  --theme-bg-canvas: #f3f4f6;
  --theme-grid-line: #d1d5db;
  --theme-bg-panel: #ffffff;
  --theme-text-primary: #111827;
  --theme-text-secondary: #4b5563;
  --theme-text-muted: #9ca3af;
  --theme-text-inverse: #ffffff;
  --theme-border: #e5e7eb;
  --theme-border-hover: #d1d5db;
  --theme-primary: #10b981;
  --theme-primary-hover: #059669;
  --theme-danger: #ef4444;
  --theme-success: #10b981;
  --theme-warning: #f59e0b;
}

.db-widget-root.db-dark-mode {
  --theme-bg-canvas: #0f1115;
  --theme-grid-line: #3f3f46;
  --theme-bg-panel: #18181b;
  --theme-text-primary: #f3f4f6;
  --theme-text-secondary: #a1a1aa;
  --theme-border: #27272a;
}

.db-widget-root .db-canvas-layer {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
  z-index: 0;
  /* Base layer: Canvas */
}

.db-widget-root .db-graph-editor-container {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  overflow: hidden;
  position: relative;
}

.db-widget-root .db-cytoscape-container,
.db-cytoscape-container {
  flex: 1;
  display: block;
  width: 100%;
  height: 100%;
  min-height: 200px;
  position: relative !important;
  background-color: var(--theme-bg-canvas);
  background-position: 0 0;
  background-repeat: repeat;
}

.db-widget-root .db-cytoscape-container.db-grid-background.db-grid-lines,
.db-cytoscape-container.db-grid-background.db-grid-lines {
  background-image:
    linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px);
}

.db-widget-root .db-cytoscape-container.db-grid-background.db-grid-dots,
.db-cytoscape-container.db-grid-background.db-grid-dots {
  background-image: radial-gradient(circle, var(--theme-text-secondary) 1px, transparent 1px);
}

/* Dark mode grid styling for widget */
.db-widget-root.db-dark-mode .db-cytoscape-container.db-grid-background.db-grid-dots {
  background-image: radial-gradient(circle,
      rgba(255, 255, 255, 0.2) 1.2px,
      transparent 1px) !important;
}

.db-widget-root.db-dark-mode .db-cytoscape-container.db-grid-background.db-grid-lines {
  background-image:
    linear-gradient(to right, rgba(255, 255, 255, 0.08) 1px, transparent 1px),
    linear-gradient(to bottom, rgba(255, 255, 255, 0.08) 1px, transparent 1px) !important;
}

.cdnd-grabbed-node {
  background-color: #ffd700 !important;
  opacity: 0.7;
  border: 2px dashed #ffa500;
}

.cdnd-drop-target {
  border: 3px solid #32cd32 !important;
  background-color: rgba(50, 205, 50, 0.1) !important;
}

.db-widget-root .db-empty-placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--theme-bg-canvas);
}

.db-widget-root .db-empty-placeholder .db-msg-box {
  text-align: center;
  color: var(--theme-text-secondary);
}

.db-modal-form-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.db-modal-form-row label {
  min-width: 100px;
  font-weight: 500;
  color: var(--theme-text-primary);
}

/* Collapsed Sidebar Triggers Styles */
.db-collapsed-sidebar-trigger {
  position: absolute;
  top: 16px;
  z-index: 100;
  /* Layer 2: Collapsed sidebar triggers */
  padding: 8px 12px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  transition: all 0.2s ease;
  border: 1px solid var(--theme-border);
  background: var(--theme-bg-panel);
  cursor: pointer;
  min-width: 140px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  /* Ensure it pops out visually */
}

.db-collapsed-sidebar-trigger.db-left-trigger {
  left: 16px;
  min-width: 200px;
}

.db-collapsed-sidebar-trigger.db-right {
  left: auto;
  right: 16px;
}

.db-collapsed-sidebar-trigger:hover {
  box-shadow: var(--shadow-md);
  transform: scale(1.01);
  background: var(--theme-bg-hover);
}

.db-sidebar-trigger-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
}

.db-logo-text-minimized {
  font-family: var(--font-family-sans);
  font-size: 14px;
  font-weight: 600;
  color: var(--theme-text-primary);
}

.db-sidebar-title-minimized {
  font-size: 13px;
  font-weight: 600;
  color: var(--theme-text-primary);
}

.db-theme-toggle-header {
  background: transparent;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 4px;
  color: var(--theme-text-secondary);
  font-size: 0.85rem;
  transition: color 0.2s;
  border-radius: 4px;
}

.db-theme-toggle-header:hover {
  color: var(--theme-text-primary);
  background: var(--theme-bg-hover);
}

.db-toggle-icon-wrapper {
  display: flex;
  align-items: center;
}

.db-toggle-icon {
  color: var(--theme-text-secondary);
}

.db-header-icon-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  font-size: 14px;
  padding: 6px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.db-header-icon-btn:hover {
  background-color: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.db-collapsed-share-btn {
  width: 24px;
  height: 24px;
  padding: 0;
}

.db-status-indicator {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  cursor: help;
}

.db-validation-status {
  font-size: 1.1em;
  margin: 0 5px;
}

.db-validation-status.db-valid {
  color: var(--theme-success);
}

.db-validation-status.db-invalid {
  color: var(--theme-warning);
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.db-desktop-text {
  display: inline;
}

.db-mobile-text {
  display: none;
}

/* Modal and Drop Zone Styles */
.db-form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.db-form-group label {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--theme-text-secondary);
}

.db-section-label {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--theme-text-secondary);
  margin-bottom: 8px;
  display: block;
}

.db-drop-zone {
  border: 2px dashed var(--theme-border);
  border-radius: var(--radius-md);
  padding: 24px;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  background-color: var(--theme-bg-hover);
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 160px;
}

.db-drop-zone:hover {
  border-color: var(--theme-text-muted);
  background-color: var(--theme-bg-active);
}

.db-drop-zone.db-drag-over {
  border-color: var(--theme-primary);
  background-color: rgba(16, 185, 129, 0.1);
  transform: scale(1.02);
  box-shadow: 0 4px 12px rgba(16, 185, 129, 0.15);
}

.db-drop-zone.db-loaded {
  border-style: solid;
  border-color: var(--theme-success);
  background-color: rgba(16, 185, 129, 0.05);
}

.db-drop-zone-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  pointer-events: none;
  width: 100%;
}

.db-drop-zone-content.db-success {
  pointer-events: auto;
}

.db-icon-circle {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background-color: var(--theme-bg-panel);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--shadow-sm);
  color: var(--theme-text-muted);
  font-size: 24px;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.db-drop-zone:hover .db-icon-circle {
  transform: scale(1.1);
  color: var(--theme-primary);
}

.db-drop-zone.db-drag-over .db-icon-circle {
  transform: scale(1.2);
  background-color: var(--theme-primary);
  color: white;
}

.db-icon-circle.db-success {
  background-color: var(--theme-success);
  color: white;
}

.db-text-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
}

.db-action-text {
  font-weight: 600;
  color: var(--theme-text-primary);
  font-size: 1rem;
}

.db-sub-text {
  color: var(--theme-text-secondary);
  font-size: 0.85em;
}

.db-hidden-input {
  display: none;
}

.db-remove-file-btn {
  position: absolute;
  top: 10px;
  right: 10px;
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  color: var(--theme-text-secondary);
  cursor: pointer;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
  box-shadow: var(--shadow-sm);
}

.db-remove-file-btn:hover {
  background-color: var(--theme-danger);
  border-color: var(--theme-danger);
  color: white;
}

@media (max-width: 768px) {
  .db-desktop-text {
    display: none;
  }

  .db-mobile-text {
    display: inline;
  }

  .db-collapsed-sidebar-trigger {
    min-width: auto !important;
    max-width: 42%;
    padding: 8px;
  }

  .db-collapsed-sidebar-trigger.db-left-trigger {
    min-width: auto !important;
  }

  .db-logo-text-minimized {
    font-size: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: block;
  }

  .db-sidebar-trigger-content {
    gap: 4px;
  }
}
</style>

<style>
/* Widget UI Layer Positioning (non-scoped for teleported content) */
/* CSS variables are inherited from global.css */

.db-ui-overlay {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  z-index: 10;
  pointer-events: none;
}

.db-sidebar-wrapper {
  position: fixed;
  pointer-events: auto;
  z-index: 200;
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  gap: 4px;
  left: 0;
  top: 0;
  /* Hide sidebars until widget is initialized */
  opacity: 0;
  visibility: hidden;
}

.db-ui-overlay.db-widget-ready .db-sidebar-wrapper {
  opacity: 1;
  visibility: visible;
}

.db-sidebar-wrapper.db-left {
  flex-direction: row;
}

.db-sidebar-wrapper.db-right {
  flex-direction: row-reverse;
}

/* Override RightSidebar positioning for widget mode */
.db-sidebar-wrapper.db-right .db-floating-sidebar.db-right {
  right: auto !important;
  left: 0 !important;
}

.db-ui-overlay .db-toolbar-container {
  pointer-events: auto;
}

/* PrimeVue z-index overrides for widget */
.p-popover {
  pointer-events: auto !important;
  z-index: 500 !important;
}

.p-popover-content {
  pointer-events: auto !important;
}

.p-select-overlay {
  pointer-events: auto !important;
  z-index: 500 !important;
}

.p-dialog {
  z-index: 550 !important;
}

.p-dialog-mask {
  z-index: 549 !important;
  pointer-events: auto !important;
}

/* PrimeVue dark mode styles for teleported components */
body.db-dark-mode .p-dialog {
  background: var(--theme-bg-panel);
  color: var(--theme-text-primary);
  border: 1px solid var(--theme-border);
}

body.db-dark-mode .p-dialog .p-dialog-header {
  background: var(--theme-bg-panel);
  color: var(--theme-text-primary);
  border-bottom: 1px solid var(--theme-border);
}

body.db-dark-mode .p-dialog .p-dialog-content {
  background: var(--theme-bg-panel);
  color: var(--theme-text-primary);
}

body.db-dark-mode .p-dialog .p-dialog-footer {
  background: var(--theme-bg-panel);
  border-top: 1px solid var(--theme-border);
}

body.db-dark-mode .p-select-overlay {
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
}

body.db-dark-mode .p-select-option {
  color: var(--theme-text-primary);
}

body.db-dark-mode .p-select-option:hover {
  background: var(--theme-bg-hover);
}

body.db-dark-mode .p-popover {
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
}

body.db-dark-mode .p-popover-content {
  color: var(--theme-text-primary);
}
</style>
