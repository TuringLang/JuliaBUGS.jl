<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import { storeToRefs } from 'pinia'
import Toast from 'primevue/toast'

import GraphEditor from './components/canvas/GraphEditor.vue'
import FloatingBottomToolbar from './components/canvas/FloatingBottomToolbar.vue'
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
import type { NodeType, GraphElement, ExampleModel, GraphNode } from './types'
import type { Core, LayoutOptions } from 'cytoscape'

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
const shareUrl = ref('')
const showValidationModal = ref(false)
const showScriptSettingsModal = ref(false)
const showCodePanel = ref(false)
const showDataPanel = ref(false)
const showNewProjectModal = ref(false)
const showNewGraphModal = ref(false)
const newProjectName = ref('')
const newGraphName = ref('')

// Import Graph State
const graphImportInput = ref<HTMLInputElement | null>(null)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const importedGraphData = ref<any>(null)
const isDragOver = ref(false)

// UI Dragging State (for performance optimization)
const isDraggingUI = ref(false)

// Flag to prevent premature canvas rendering
const isInitialized = ref(false)

const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { parsedGraphData } = storeToRefs(dataStore)
const { generatedCode } = useBugsCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()

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

  initGraph()
  isInitialized.value = true
  widgetInitialized.value = true
  validateGraph()
  document.body.classList.add('doodle-bugs-host')
})

onUnmounted(() => {
  document.body.classList.remove('doodle-bugs-host')
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

const toggleCodePanel = () => {
  showCodePanel.value = !showCodePanel.value
}
const toggleDataPanel = () => {
  showDataPanel.value = !showDataPanel.value
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
    if (cy) smartFit(cy, true) // Use smartFit for smooth animation
  }
}

const smartFit = (cy: Core, animate: boolean = true) => {
  const eles = cy.elements()
  if (eles.length === 0) return
  const padding = 50
  const w = cy.width()
  const h = cy.height()
  const bb = eles.boundingBox()
  if (bb.w === 0 || bb.h === 0) return
  const zoomX = (w - 2 * padding) / bb.w
  const zoomY = (h - 2 * padding) / bb.h
  let targetZoom = Math.min(zoomX, zoomY)
  targetZoom = Math.min(targetZoom, 0.8)
  const targetPan = {
    x: (w - targetZoom * (bb.x1 + bb.x2)) / 2,
    y: (h - targetZoom * (bb.y1 + bb.y2)) / 2,
  }
  if (animate) {
    cy.animate({ zoom: targetZoom, pan: targetPan, duration: 500, easing: 'ease-in-out-cubic' })
  } else {
    cy.viewport({ zoom: targetZoom, pan: targetPan })
  }
}

const handleGraphLayout = (layoutName: string) => {
  const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
  if (!cy) return
  const layoutOptionsMap: Record<string, LayoutOptions> = {
    dagre: {
      name: 'dagre',
      animate: true,
      animationDuration: 500,
      fit: false,
      padding: 50,
    } as unknown as LayoutOptions,
    fcose: {
      name: 'fcose',
      animate: true,
      animationDuration: 500,
      fit: false,
      padding: 50,
      randomize: false,
      quality: 'proof',
    } as unknown as LayoutOptions,
    cola: {
      name: 'cola',
      animate: true,
      fit: false,
      padding: 50,
      refresh: 1,
      avoidOverlap: true,
      infinite: false,
      centerGraph: true,
      flow: { axis: 'y', minSeparation: 30 },
      handleDisconnected: false,
      randomize: false,
    } as unknown as LayoutOptions,
    klay: {
      name: 'klay',
      animate: true,
      animationDuration: 500,
      fit: false,
      padding: 50,
      klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' },
    } as unknown as LayoutOptions,
    preset: { name: 'preset', fit: false, padding: 50 } as unknown as LayoutOptions,
  }
  const options = layoutOptionsMap[layoutName] || layoutOptionsMap.preset
  cy.one('layoutstop', () => smartFit(cy, true))
  cy.layout(options).run()
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
      graphStore.updateGraphElements(newGraphMeta.id, importedGraphData.value.elements)

      if (importedGraphData.value.dataContent) {
        dataStore.updateGraphData(newGraphMeta.id, { content: importedGraphData.value.dataContent })
      }

      // Restore layout settings if available
      if (importedGraphData.value.layout && projectStore.currentProject) {
        projectStore.updateGraphLayout(
          projectStore.currentProject.id,
          newGraphMeta.id,
          importedGraphData.value.layout
        )
      }

      graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
    } else if (newGraphMeta) {
      graphStore.selectGraph(newGraphMeta.id)
    }

    showNewGraphModal.value = false
    newGraphName.value = ''
    importedGraphData.value = null
    if (graphImportInput.value) graphImportInput.value.value = ''
  }
}

const triggerGraphImport = () => {
  graphImportInput.value?.click()
}

const processGraphFile = (file: File) => {
  const reader = new FileReader()
  reader.onload = (e) => {
    try {
      const content = e.target?.result as string
      const data = JSON.parse(content)
      // Basic validation
      if (data.elements && Array.isArray(data.elements)) {
        importedGraphData.value = data
        if (!newGraphName.value && data.name) {
          newGraphName.value = data.name + ' (Imported)'
        }
      } else {
        alert('Invalid graph JSON file.')
      }
    } catch (err) {
      console.error(err)
      alert('Failed to parse file.')
    }
  }
  reader.readAsText(file)
}

const handleGraphImportFile = (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (file) processGraphFile(file)
}

const handleDrop = (event: DragEvent) => {
  isDragOver.value = false
  const file = event.dataTransfer?.files?.[0]
  if (file) {
    processGraphFile(file)
  }
}

const clearImportedData = () => {
  importedGraphData.value = null
  if (graphImportInput.value) {
    graphImportInput.value.value = ''
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

const compressAndEncode = async (jsonStr: string): Promise<string> => {
  try {
    if (!window.CompressionStream) throw new Error('CompressionStream not supported')
    const stream = new Blob([jsonStr]).stream()
    const compressedStream = stream.pipeThrough(new CompressionStream('gzip'))
    const response = new Response(compressedStream)
    const blob = await response.blob()
    const buffer = await blob.arrayBuffer()
    const bytes = new Uint8Array(buffer)
    let binaryStr = ''
    for (let i = 0; i < bytes.byteLength; i++) {
      binaryStr += String.fromCharCode(bytes[i])
    }
    return 'gz_' + btoa(binaryStr)
  } catch {
    return btoa(unescape(encodeURIComponent(jsonStr)))
  }
}

const keyMap: Record<string, string> = {
  id: 'i',
  name: 'n',
  type: 't',
  nodeType: 'nt',
  position: 'p',
  parent: 'pa',
  distribution: 'di',
  equation: 'eq',
  observed: 'ob',
  indices: 'id',
  loopVariable: 'lv',
  loopRange: 'lr',
  param1: 'p1',
  param2: 'p2',
  param3: 'p3',
  source: 's',
  target: 'tg',
}
const nodeTypeMap: Record<string, number> = {
  stochastic: 1,
  deterministic: 2,
  constant: 3,
  observed: 4,
  plate: 5,
}

const minifyGraph = (elems: GraphElement[]): Record<string, unknown>[] => {
  return elems.map((el) => {
    const min: Record<string, unknown> = {}
    if (el.type === 'node') {
      const node = el as GraphNode
      min[keyMap.id] = node.id.replace('node_', '')
      min[keyMap.name] = node.name
      min[keyMap.type] = 0
      min[keyMap.nodeType] = nodeTypeMap[node.nodeType]
      min[keyMap.position] = [Math.round(node.position.x), Math.round(node.position.y)]
      if (node.parent) min[keyMap.parent] = node.parent.replace('node_', '').replace('plate_', '')
      if (node.distribution) min[keyMap.distribution] = node.distribution
      if (node.equation) min[keyMap.equation] = node.equation
      if (node.observed) min[keyMap.observed] = 1
      if (node.indices) min[keyMap.indices] = node.indices
      if (node.loopVariable) min[keyMap.loopVariable] = node.loopVariable
      if (node.loopRange) min[keyMap.loopRange] = node.loopRange
      if (node.param1) min[keyMap.param1] = node.param1
      if (node.param2) min[keyMap.param2] = node.param2
      if (node.param3) min[keyMap.param3] = node.param3
    } else {
      min[keyMap.id] = el.id.replace('edge_', '')
      min[keyMap.type] = 1
      min[keyMap.source] = el.source.replace('node_', '').replace('plate_', '')
      min[keyMap.target] = el.target.replace('node_', '').replace('plate_', '')
    }
    return min
  })
}

const generateShareLink = async (payload: object) => {
  try {
    const base64 = await compressAndEncode(JSON.stringify(payload))
    const baseUrl = window.location.origin + window.location.pathname
    shareUrl.value = `${baseUrl}?share=${encodeURIComponent(base64)}`
  } catch (e) {
    console.error('Failed to generate share link:', e)
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
      const storedGraph = localStorage.getItem(`doodlebugs-graph-${graphId}`)
      const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`)
      if (storedGraph)
        try {
          graphElements = JSON.parse(storedGraph).elements
        } catch {}
      if (storedData)
        try {
          dataContent = JSON.parse(storedData).content || '{}'
        } catch {}
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
  if (!graphStore.currentGraphId) return
  const data = {
    name:
      projectStore.currentProject?.graphs.find((g) => g.id === graphStore.currentGraphId)?.name ||
      'Graph',
    elements: graphStore.currentGraphElements,
    data: dataStore.dataContent,
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${data.name.replace(/\s+/g, '_')}.json`
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
const rightDrag = useDrag(window.innerWidth - 340, 20)

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
  <div
    class="doodle-widget-root"
    :class="{ 'dark-mode': isDarkMode }"
    style="width: 100%; height: 100%; position: relative; overflow: hidden"
  >
    <div
      class="canvas-layer"
      :style="{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        width: '100%',
        height: '100%',
        pointerEvents: isDraggingUI ? 'none' : 'auto',
      }"
    >
      <GraphEditor
        v-if="isInitialized && graphStore.currentGraphId"
        :key="graphStore.currentGraphId"
        :graph-id="graphStore.currentGraphId"
        :is-grid-enabled="isGridEnabled"
        :grid-size="gridSize"
        :grid-style="canvasGridStyle"
        :current-mode="currentMode"
        :elements="elements"
        :current-node-type="currentNodeType"
        :validation-errors="validationErrors"
        :show-zoom-controls="false"
        @update:current-mode="currentMode = $event"
        @update:current-node-type="currentNodeType = $event"
        @element-selected="handleElementSelected"
        @layout-updated="(name) => graphStore.updateGraphLayout(graphStore.currentGraphId!, name)"
        @viewport-changed="
          (v) => graphStore.updateGraphViewport(graphStore.currentGraphId!, v.zoom, v.pan)
        "
        @update:is-grid-enabled="isGridEnabled = $event"
        @update:grid-size="gridSize = $event"
      />
      <div v-else class="empty-placeholder">
        <div class="msg-box">
          <i class="fas fa-spinner fa-spin"></i>
          <p>Initializing...</p>
        </div>
      </div>
    </div>

    <Teleport to="body">
      <div class="doodle-bugs-ui-overlay" :class="{ 'dark-mode': isDarkMode, 'widget-ready': widgetInitialized }">
        <Toast position="top-center" />

        <!-- Left Sidebar (Floating) -->
        <div v-if="widgetInitialized && isLeftSidebarOpen" class="sidebar-wrapper left" :style="leftDrag.style.value">
          <LeftSidebar
            v-show="isLeftSidebarOpen"
            :activeAccordionTabs="activeLeftAccordionTabs"
            @update:activeAccordionTabs="activeLeftAccordionTabs = $event"
            :projectName="projectStore.currentProject?.name || 'Project'"
            :pinnedGraphTitle="pinnedGraphTitle"
            :isGridEnabled="isGridEnabled"
            :gridSize="gridSize"
            :showZoomControls="showZoomControls"
            :showDebugPanel="showDebugPanel"
            :isCodePanelOpen="showCodePanel"
            :isDetachModeActive="isDetachModeActive"
            :showDetachModeControl="showDetachModeControl"
            :enableDrag="true"
            @toggle-left-sidebar="uiStore.toggleLeftSidebar"
            @new-project="handleNewProject"
            @new-graph="handleNewGraph"
            @update:currentMode="currentMode = $event"
            @update:currentNodeType="currentNodeType = $event"
            @update:isGridEnabled="isGridEnabled = $event"
            @update:gridSize="gridSize = $event"
            @update:showZoomControls="showZoomControls = $event"
            @update:showDebugPanel="showDebugPanel = $event"
            @update:isDetachModeActive="isDetachModeActive = $event"
            @update:show-detach-mode-control="showDetachModeControl = $event"
            @toggle-code-panel="toggleCodePanel"
            @load-example="handleLoadExample"
            @open-about-modal="showAboutModal = true"
            @open-faq-modal="showFaqModal = true"
            @toggle-dark-mode="uiStore.toggleDarkMode"
            @share-graph="handleShareGraph"
            @share-project-url="handleShareProjectUrl"
            @header-drag-start="onLeftHeaderDragStart"
          />
        </div>

        <div v-if="widgetInitialized && isRightSidebarOpen" class="sidebar-wrapper right" :style="rightDrag.style.value">
          <RightSidebar
            v-show="isRightSidebarOpen"
            :selectedElement="selectedElement"
            :validationErrors="validationErrors"
            :isModelValid="isModelValid"
            :enableDrag="true"
            @toggle-right-sidebar="uiStore.toggleRightSidebar"
            @update-element="updateElement"
            @delete-element="deleteElement"
            @show-validation-issues="showValidationModal = true"
            @open-script-settings="showScriptSettingsModal = true"
            @download-script="handleDownloadScript"
            @generate-script="handleGenerateStandalone"
            @share="handleShare"
            @open-export-modal="openExportModal"
            @export-json="handleExportJson"
            @header-drag-start="onRightHeaderDragStart"
          />
        </div>

        <FloatingBottomToolbar
          :current-mode="currentMode"
          :current-node-type="currentNodeType"
          :show-zoom-controls="showZoomControls"
          :show-code-panel="showCodePanel"
          :show-data-panel="showDataPanel"
          :is-detach-mode-active="isDetachModeActive"
          :show-detach-mode-control="showDetachModeControl"
          :is-widget="true"
          @update:current-mode="currentMode = $event"
          @update:current-node-type="currentNodeType = $event"
          @undo="handleUndo"
          @redo="handleRedo"
          @zoom-in="handleZoomIn"
          @zoom-out="handleZoomOut"
          @fit="handleFit"
          @layout-graph="handleGraphLayout"
          @toggle-code-panel="toggleCodePanel"
          @toggle-data-panel="toggleDataPanel"
          @toggle-detach-mode="uiStore.toggleDetachMode"
          @open-style-modal="showStyleModal = true"
          @share="handleShare"
          @nav="handleToolbarNavigation"
          @drag-start="handleUIInteractionStart"
          @drag-end="handleUIInteractionEnd"
        />

        <div v-if="showCodePanel" class="floating-panel code-panel">
          <div class="panel-header">
            <span>BUGS Code</span>
            <button class="close-btn" @click="showCodePanel = false">
              <i class="fas fa-times"></i>
            </button>
          </div>
          <div class="panel-content">
            <CodePreviewPanel :is-active="showCodePanel" />
          </div>
        </div>

        <div v-if="showDataPanel" class="floating-panel data-panel">
          <div class="panel-header">
            <span>Data Input</span>
            <button class="close-btn" @click="showDataPanel = false">
              <i class="fas fa-times"></i>
            </button>
          </div>
          <div class="panel-content">
            <DataInputPanel :is-active="showDataPanel" />
          </div>
        </div>

        <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
        <FaqModal :is-open="showFaqModal" @close="showFaqModal = false" />
        <ExportModal
          :is-open="showExportModal"
          :export-type="currentExportType"
          @close="showExportModal = false"
          @confirm-export="handleConfirmExport"
        />
        <GraphStyleModal :is-open="showStyleModal" @close="showStyleModal = false" />
        <ShareModal
          :is-open="showShareModal"
          :url="shareUrl"
          :project="projectStore.currentProject"
          :current-graph-id="graphStore.currentGraphId"
          @close="showShareModal = false"
          @generate="handleGenerateShareLink"
        />
        <ValidationIssuesModal
          :is-open="showValidationModal"
          :validation-errors="validationErrors"
          :elements="elements"
          @close="showValidationModal = false"
          @select-node="handleSelectNodeFromModal"
        />
        <BaseModal :is-open="showScriptSettingsModal" @close="showScriptSettingsModal = false">
          <template #header><h3>Script Settings</h3></template>
          <template #body><ScriptSettingsPanel /></template>
          <template #footer
            ><BaseButton @click="showScriptSettingsModal = false">Done</BaseButton></template
          >
        </BaseModal>

        <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
          <template #header><h3>Create New Project</h3></template>
          <template #body>
            <div class="modal-form-row">
              <label>Project Name:</label>
              <BaseInput
                v-model="newProjectName"
                placeholder="Enter project name"
                @keyup.enter="createNewProject"
              />
            </div>
          </template>
          <template #footer
            ><BaseButton @click="createNewProject" type="primary">Create</BaseButton></template
          >
        </BaseModal>

        <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
          <template #header><h3>Create New Graph</h3></template>
          <template #body>
            <div class="flex flex-col gap-2">
              <div class="form-group">
                <label for="new-graph-name">Graph Name</label>
                <BaseInput
                  id="new-graph-name"
                  v-model="newGraphName"
                  placeholder="Enter a name for your graph"
                  @keyup.enter="createNewGraph"
                />
              </div>

              <div class="import-section">
                <label class="section-label">Import from JSON (Optional)</label>

                <div
                  class="drop-zone"
                  :class="{ loaded: importedGraphData, 'drag-over': isDragOver }"
                  @click="triggerGraphImport"
                  @dragover.prevent="isDragOver = true"
                  @dragleave.prevent="isDragOver = false"
                  @drop.prevent="handleDrop"
                >
                  <input
                    type="file"
                    ref="graphImportInput"
                    accept=".json"
                    @change="handleGraphImportFile"
                    class="hidden-input"
                  />

                  <div v-if="!importedGraphData" class="drop-zone-content">
                    <div class="icon-circle">
                      <i class="fas fa-file-import"></i>
                    </div>
                    <div class="text-content">
                      <span class="action-text">Click or Drag & Drop JSON file</span>
                      <small class="sub-text">Restore a previously exported graph</small>
                    </div>
                  </div>

                  <div v-else class="drop-zone-content success">
                    <div class="icon-circle success">
                      <i class="fas fa-check"></i>
                    </div>
                    <div class="text-content">
                      <span class="action-text">File Loaded Successfully</span>
                      <small class="sub-text"
                        >{{ importedGraphData.name || 'Untitled Graph' }}</small
                      >
                    </div>
                    <button
                      class="remove-file-btn"
                      @click.stop="clearImportedData"
                      title="Remove file"
                    >
                      <i class="fas fa-times"></i>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </template>
          <template #footer
            ><BaseButton @click="createNewGraph" type="primary">Create Graph</BaseButton></template
          >
        </BaseModal>

        <DebugPanel v-if="showDebugPanel" @close="showDebugPanel = false" />
      </div>
    </Teleport>
  </div>
</template>

<style>
.doodle-widget-root {
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

.doodle-widget-root.dark-mode {
  --theme-bg-canvas: #0f1115;
  --theme-grid-line: #3f3f46;
  --theme-bg-panel: #18181b;
  --theme-text-primary: #f3f4f6;
  --theme-text-secondary: #a1a1aa;
  --theme-border: #27272a;
}

.doodle-widget-root .canvas-layer {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
}

.doodle-widget-root .graph-editor-container {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  overflow: hidden;
  position: relative;
}

.doodle-widget-root .cytoscape-container,
.cytoscape-container {
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

.doodle-widget-root .cytoscape-container.grid-background.grid-lines,
.cytoscape-container.grid-background.grid-lines {
  background-image:
    linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px);
}

.doodle-widget-root .cytoscape-container.grid-background.grid-dots,
.cytoscape-container.grid-background.grid-dots {
  background-image: radial-gradient(circle, var(--theme-text-secondary) 1px, transparent 1px);
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

.doodle-widget-root .empty-placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--theme-bg-canvas);
}

.doodle-widget-root .empty-placeholder .msg-box {
  text-align: center;
  color: var(--theme-text-secondary);
}

.modal-form-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.modal-form-row label {
  min-width: 100px;
  font-weight: 500;
  color: var(--theme-text-primary);
}

/* Collapsed Sidebar Triggers Styles */
.collapsed-sidebar-trigger {
  position: absolute;
  top: 16px;
  z-index: 9000; /* Increased z-index to ensure visibility above canvas layers */
  padding: 8px 12px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  transition: all 0.2s ease;
  border: 1px solid var(--theme-border);
  background: var(--theme-bg-panel);
  cursor: pointer;
  min-width: 140px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1); /* Ensure it pops out visually */
}

.collapsed-sidebar-trigger.left-trigger {
  left: 16px;
  min-width: 200px;
}

.collapsed-sidebar-trigger.right {
  left: auto;
  right: 16px;
}

.collapsed-sidebar-trigger:hover {
  box-shadow: var(--shadow-md);
  transform: scale(1.01);
  background: var(--theme-bg-hover);
}

.sidebar-trigger-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
}

.logo-text-minimized {
  font-family: var(--font-family-sans);
  font-size: 14px;
  font-weight: 600;
  color: var(--theme-text-primary);
}

.sidebar-title-minimized {
  font-size: 13px;
  font-weight: 600;
  color: var(--theme-text-primary);
}

.theme-toggle-header {
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
.theme-toggle-header:hover {
  color: var(--theme-text-primary);
  background: var(--theme-bg-hover);
}

.toggle-icon-wrapper {
  display: flex;
  align-items: center;
}

.toggle-icon {
  color: var(--theme-text-secondary);
}

.header-icon-btn {
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

.header-icon-btn:hover {
  background-color: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.collapsed-share-btn {
  width: 24px;
  height: 24px;
  padding: 0;
}

.status-indicator {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  cursor: help;
}

.validation-status {
  font-size: 1.1em;
  margin: 0 5px;
}
.validation-status.valid {
  color: var(--theme-success);
}
.validation-status.invalid {
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

.desktop-text {
  display: inline;
}
.mobile-text {
  display: none;
}

/* Modal and Drop Zone Styles */
.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--theme-text-secondary);
}

.section-label {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--theme-text-secondary);
  margin-bottom: 8px;
  display: block;
}

.drop-zone {
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

.drop-zone:hover {
  border-color: var(--theme-text-muted);
  background-color: var(--theme-bg-active);
}

.drop-zone.drag-over {
  border-color: var(--theme-primary);
  background-color: rgba(16, 185, 129, 0.1);
  transform: scale(1.02);
  box-shadow: 0 4px 12px rgba(16, 185, 129, 0.15);
}

.drop-zone.loaded {
  border-style: solid;
  border-color: var(--theme-success);
  background-color: rgba(16, 185, 129, 0.05);
}

.drop-zone-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  pointer-events: none;
  width: 100%;
}

.drop-zone-content.success {
  pointer-events: auto;
}

.icon-circle {
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

.drop-zone:hover .icon-circle {
  transform: scale(1.1);
  color: var(--theme-primary);
}

.drop-zone.drag-over .icon-circle {
  transform: scale(1.2);
  background-color: var(--theme-primary);
  color: white;
}

.icon-circle.success {
  background-color: var(--theme-success);
  color: white;
}

.text-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
}

.action-text {
  font-weight: 600;
  color: var(--theme-text-primary);
  font-size: 1rem;
}

.sub-text {
  color: var(--theme-text-secondary);
  font-size: 0.85em;
}

.hidden-input {
  display: none;
}

.remove-file-btn {
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

.remove-file-btn:hover {
  background-color: var(--theme-danger);
  border-color: var(--theme-danger);
  color: white;
}

@media (max-width: 768px) {
  .desktop-text {
    display: none;
  }
  .mobile-text {
    display: inline;
  }

  .collapsed-sidebar-trigger {
    min-width: auto !important;
    max-width: 42%;
    padding: 8px;
  }

  .collapsed-sidebar-trigger.left-trigger {
    min-width: auto !important;
  }

  .logo-text-minimized {
    font-size: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: block;
  }

  .sidebar-trigger-content {
    gap: 4px;
  }
}
</style>

<style>
.doodle-bugs-ui-overlay {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  z-index: 9999;
  pointer-events: none;

  --font-family-sans:
    -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  --theme-bg-canvas: #f3f4f6;
  --theme-bg-panel: #ffffff;
  --theme-bg-panel-transparent: rgba(255, 255, 255, 0.95);
  --theme-bg-hover: #f3f4f6;
  --theme-bg-active: #e5e7eb;
  --theme-text-primary: #111827;
  --theme-text-secondary: #4b5563;
  --theme-text-muted: #9ca3af;
  --theme-text-inverse: #ffffff;
  --theme-border: #e5e7eb;
  --theme-primary: #10b981;
  --theme-primary-hover: #059669;
  --theme-danger: #ef4444;
  --theme-success: #10b981;
  --theme-warning: #f59e0b;
  --radius-sm: 6px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-pill: 9999px;
  --shadow-floating: 0 8px 24px -4px rgba(0, 0, 0, 0.12), 0 4px 12px -2px rgba(0, 0, 0, 0.08);
}

.doodle-bugs-ui-overlay.dark-mode {
  --theme-bg-canvas: #0f1115;
  --theme-bg-panel: #18181b;
  --theme-bg-panel-transparent: rgba(24, 24, 27, 0.9);
  --theme-bg-hover: #27272a;
  --theme-bg-active: #3f3f46;
  --theme-text-primary: #f3f4f6;
  --theme-text-secondary: #a1a1aa;
  --theme-border: #27272a;
  --theme-primary: #10b981;
  --shadow-floating: 0 10px 30px -4px rgba(0, 0, 0, 0.6);
}

.sidebar-wrapper {
  position: fixed;
  pointer-events: auto;
  z-index: 10000;
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  gap: 4px;
  /* Will be positioned by transform */
  left: 0;
  top: 0;
  /* Hide sidebars until widget is initialized */
  opacity: 0;
  visibility: hidden;
}

.doodle-bugs-ui-overlay.widget-ready .sidebar-wrapper {
  opacity: 1;
  visibility: visible;
}

.sidebar-wrapper.left {
  flex-direction: row;
}

.sidebar-wrapper.right {
  flex-direction: row-reverse;
}

/* Removed separate drag-handle styles */

.doodle-bugs-ui-overlay .toolbar-container {
  pointer-events: auto;
}

.floating-panel {
  position: fixed;
  pointer-events: auto;
  z-index: 30000;
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-floating);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.floating-panel.code-panel {
  bottom: 100px;
  left: 50%;
  transform: translateX(-50%);
  width: 600px;
  max-width: 90vw;
  height: 350px;
}

.floating-panel.data-panel {
  bottom: 100px;
  right: 20px;
  width: 450px;
  max-width: 90vw;
  height: 350px;
}

.floating-panel .panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 15px;
  background: var(--theme-bg-hover);
  border-bottom: 1px solid var(--theme-border);
  font-weight: 600;
  color: var(--theme-text-primary);
  font-size: 14px;
}

.floating-panel .close-btn {
  background: none;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  font-size: 14px;
  padding: 4px 8px;
  border-radius: 4px;
  transition: all 0.2s;
}

.floating-panel .close-btn:hover {
  background: var(--theme-bg-active);
  color: var(--theme-danger);
}

.floating-panel .panel-content {
  flex: 1;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.floating-panel .panel-content > * {
  flex: 1;
  height: 100%;
}

/* PrimeVue Popover/Portal Styles for Widget */
.p-popover {
  pointer-events: auto !important;
  z-index: 100000 !important;
}

.p-popover-content {
  pointer-events: auto !important;
}

/* Ensure BaseSelect dropdown works */
.p-select-overlay {
  pointer-events: auto !important;
  z-index: 100000 !important;
}

/* Ensure all PrimeVue modals appear above sidebars and toolbars */
.p-dialog {
  z-index: 50000 !important;
}

.p-dialog-mask {
  z-index: 49999 !important;
  pointer-events: auto !important;
}
</style>
