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

// Flag to prevent premature canvas rendering
const isInitialized = ref(false)

const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { parsedGraphData } = storeToRefs(dataStore)
const { generatedCode } = useBugsCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()

const initGraph = () => {
  if (projectStore.projects.length === 0) {
    projectStore.createProject("Default Project")
  }
  
  if (!projectStore.currentProjectId && projectStore.projects.length > 0) {
    projectStore.selectProject(projectStore.projects[0].id)
  }
  
  const proj = projectStore.currentProject
  if (!proj) return
  
  if (proj.graphs.length === 0) {
    projectStore.addGraphToProject(proj.id, "Model 1")
  }
  
  if (proj.graphs.length > 0 && !graphStore.currentGraphId) {
    graphStore.selectGraph(proj.graphs[0].id)
  }
  
  if (graphStore.currentGraphId && !graphStore.graphContents.has(graphStore.currentGraphId)) {
    graphStore.createNewGraphContent(graphStore.currentGraphId)
  }
}

onMounted(() => {
  uiStore.isLeftSidebarOpen = true
  uiStore.isRightSidebarOpen = true
  
  graphStore.selectGraph(undefined as unknown as string)
  
  projectStore.loadProjects()

  if (props.initialState) {
    try {
      const state = JSON.parse(props.initialState)
      if (state.project) projectStore.importState(state.project)
      if (state.graphs) state.graphs.forEach((g: { graphId: string; elements: GraphElement[]; lastLayout?: string; zoom?: number; pan?: { x: number; y: number } }) => graphStore.graphContents.set(g.graphId, g))
      if (state.data) state.data.forEach((d: { graphId: string; content: string }) => dataStore.updateGraphData(d.graphId, { content: d.content }))
    } catch (e) {
      console.error('DoodleBUGS: Failed to parse state', e)
    }
  } 
  
  initGraph()
  isInitialized.value = true
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
      data: Array.from(graphStore.graphContents.keys()).map(gid => ({
          graphId: gid,
          content: dataStore.getGraphData(gid).content
      }))
    }
    emit('state-update', JSON.stringify(fullState))
  },
  { deep: true }
)

watch(generatedCode, (code) => {
  emit('code-update', code)
})

const toggleCodePanel = () => { showCodePanel.value = !showCodePanel.value }
const toggleDataPanel = () => { showDataPanel.value = !showDataPanel.value }

const handleUndo = () => { if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.undo() }
const handleRedo = () => { if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.redo() }
const handleZoomIn = () => { if (graphStore.currentGraphId) getCyInstance(graphStore.currentGraphId)?.zoom(getCyInstance(graphStore.currentGraphId)!.zoom() * 1.2) }
const handleZoomOut = () => { if (graphStore.currentGraphId) getCyInstance(graphStore.currentGraphId)?.zoom(getCyInstance(graphStore.currentGraphId)!.zoom() * 0.8) }
const handleFit = () => { if (graphStore.currentGraphId) getCyInstance(graphStore.currentGraphId)?.fit(undefined, 50) }

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
  const targetPan = { x: (w - targetZoom * (bb.x1 + bb.x2)) / 2, y: (h - targetZoom * (bb.y1 + bb.y2)) / 2 }
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
    dagre: { name: 'dagre', animate: true, animationDuration: 500, fit: false, padding: 50 } as unknown as LayoutOptions,
    fcose: { name: 'fcose', animate: true, animationDuration: 500, fit: false, padding: 50, randomize: false, quality: 'proof' } as unknown as LayoutOptions,
    cola: { name: 'cola', animate: true, fit: false, padding: 50, refresh: 1, avoidOverlap: true, infinite: false, centerGraph: true, flow: { axis: 'y', minSeparation: 30 }, handleDisconnected: false, randomize: false } as unknown as LayoutOptions,
    klay: { name: 'klay', animate: true, animationDuration: 500, fit: false, padding: 50, klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' } } as unknown as LayoutOptions,
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

const handleConfirmExport = (options: { bg: string; full: boolean; scale: number; quality?: number }) => {
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
      blob = cy.jpg({ ...baseOptions, quality: options.quality || 0.9, output: 'blob' }) as unknown as Blob
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
    console.error("Export failed", err)
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
  if (projectStore.currentProjectId && newGraphName.value.trim()) {
    const newGraph = projectStore.addGraphToProject(projectStore.currentProjectId, newGraphName.value.trim())
    if (newGraph) {
      graphStore.selectGraph(newGraph.id)
    }
    showNewGraphModal.value = false
    newGraphName.value = ''
  }
}

const handleLoadExample = async (exampleKey: string) => {
  if (!projectStore.currentProjectId) return
  try {
    const baseUrl = import.meta.env.BASE_URL
    const modelResponse = await fetch(`${baseUrl}examples/${exampleKey}/model.json`)
    if (!modelResponse.ok) throw new Error(`Could not fetch example model: ${modelResponse.statusText}`)
    
    const modelData: ExampleModel = await modelResponse.json()
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId, modelData.name)
    if (!newGraphMeta) return

    graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON)
    graphStore.updateGraphLayout(newGraphMeta.id, 'preset')

    const jsonDataResponse = await fetch(`${baseUrl}examples/${exampleKey}/data.json`)
    if (jsonDataResponse.ok) {
      const fullData = await jsonDataResponse.json()
      dataStore.dataContent = JSON.stringify({ data: fullData.data || {}, inits: fullData.inits || {} }, null, 2)
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

const keyMap: Record<string, string> = { id: 'i', name: 'n', type: 't', nodeType: 'nt', position: 'p', parent: 'pa', distribution: 'di', equation: 'eq', observed: 'ob', indices: 'id', loopVariable: 'lv', loopRange: 'lr', param1: 'p1', param2: 'p2', param3: 'p3', source: 's', target: 'tg' }
const nodeTypeMap: Record<string, number> = { stochastic: 1, deterministic: 2, constant: 3, observed: 4, plate: 5 }

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

const handleGenerateShareLink = async (options: { scope: 'current' | 'project' | 'custom'; selectedGraphIds?: string[] }) => {
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
      if (storedGraph) try { graphElements = JSON.parse(storedGraph).elements } catch {}
      if (storedData) try { dataContent = JSON.parse(storedData).content || '{}' } catch {}
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
    const targetIds = options.scope === 'project' 
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
    name: projectStore.currentProject?.graphs.find(g => g.id === graphStore.currentGraphId)?.name || 'Graph',
    elements: graphStore.currentGraphElements,
    data: dataStore.dataContent
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

const handleSelectNodeFromModal = (nodeId: string) => {
  const el = elements.value.find(e => e.id === nodeId)
  if (el) graphStore.setSelectedElement(el)
}

const { 
  isLeftSidebarOpen, isRightSidebarOpen, isGridEnabled, gridSize, 
  showZoomControls, showDebugPanel, activeLeftAccordionTabs, isDetachModeActive,
  showDetachModeControl, isDarkMode, canvasGridStyle 
} = storeToRefs(uiStore)

const pinnedGraphTitle = computed(() => projectStore.currentProject?.graphs.find(g => g.id === graphStore.currentGraphId)?.name || 'Graph')
const isModelValid = computed(() => validationErrors.value.size === 0)

const useDrag = (initialX: number, initialY: number) => {
  const x = ref(initialX)
  const y = ref(initialY)
  const isDragging = ref(false)
  const startX = ref(0)
  const startY = ref(0)

  const onMouseDown = (e: MouseEvent) => {
    if ((e.target as HTMLElement).closest('button, input, select, textarea, .p-accordion, .p-toggleswitch')) return
    isDragging.value = true
    startX.value = e.clientX - x.value
    startY.value = e.clientY - y.value
    window.addEventListener('mousemove', onMouseMove)
    window.addEventListener('mouseup', onMouseUp)
  }

  const onMouseMove = (e: MouseEvent) => {
    if (!isDragging.value) return
    x.value = e.clientX - startX.value
    y.value = e.clientY - startY.value
  }

  const onMouseUp = () => {
    isDragging.value = false
    window.removeEventListener('mousemove', onMouseMove)
    window.removeEventListener('mouseup', onMouseUp)
  }

  return { x, y, onMouseDown, style: computed(() => ({ left: `${x.value}px`, top: `${y.value}px` })) }
}

const leftDrag = useDrag(20, 20)
const rightDrag = useDrag(window.innerWidth - 340, 20)
</script>

<template>
  <div class="doodle-widget-root" :class="{ 'dark-mode': isDarkMode }" style="width: 100%; height: 100%; position: relative; overflow: hidden;">
    
    <div class="canvas-layer" style="position: absolute; top: 0; left: 0; right: 0; bottom: 0; width: 100%; height: 100%;">
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
        @element-selected="graphStore.setSelectedElement"
        @layout-updated="(name) => graphStore.updateGraphLayout(graphStore.currentGraphId!, name)"
        @viewport-changed="(v) => graphStore.updateGraphViewport(graphStore.currentGraphId!, v.zoom, v.pan)"
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
      <div class="doodle-bugs-ui-overlay" :class="{ 'dark-mode': isDarkMode }">
        <Toast position="top-center" />

        <!-- Left Sidebar -->
        <div v-if="isLeftSidebarOpen" class="sidebar-wrapper left" :style="leftDrag.style.value">
          <div class="drag-handle left" @mousedown="leftDrag.onMouseDown" title="Drag to move">
            <span></span><span></span><span></span>
          </div>
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
            @update:showDetachModeControl="showDetachModeControl = $event"
            @toggle-code-panel="toggleCodePanel"
            @load-example="handleLoadExample"
            @open-about-modal="showAboutModal = true"
            @open-faq-modal="showFaqModal = true"
            @toggle-dark-mode="uiStore.toggleDarkMode"
            @share-graph="handleShareGraph"
            @share-project-url="handleShareProjectUrl"
          />
        </div>
        <div v-else class="collapsed-sidebar-trigger left" @click="uiStore.toggleLeftSidebar" title="Open left sidebar">
          <span></span><span></span><span></span>
        </div>

        <div v-if="isRightSidebarOpen" class="sidebar-wrapper right" :style="rightDrag.style.value">
          <RightSidebar
            v-show="isRightSidebarOpen"
            :selectedElement="selectedElement"
            :validationErrors="validationErrors"
            :isModelValid="isModelValid"
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
          />
          <div class="drag-handle right" @mousedown="rightDrag.onMouseDown" title="Drag to move">
            <span></span><span></span><span></span>
          </div>
        </div>
        <div v-else class="collapsed-sidebar-trigger right" @click="uiStore.toggleRightSidebar" title="Open right sidebar">
          <span></span><span></span><span></span>
        </div>

        <FloatingBottomToolbar
          :current-mode="currentMode"
          :current-node-type="currentNodeType"
          :show-zoom-controls="showZoomControls"
          :show-code-panel="showCodePanel"
          :show-data-panel="showDataPanel"
          :is-detach-mode-active="isDetachModeActive"
          :show-detach-mode-control="showDetachModeControl"
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
          <template #footer><BaseButton @click="showScriptSettingsModal = false">Done</BaseButton></template>
        </BaseModal>
        
        <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
          <template #header><h3>Create New Project</h3></template>
          <template #body>
            <div class="modal-form-row">
              <label>Project Name:</label>
              <BaseInput v-model="newProjectName" placeholder="Enter project name" @keyup.enter="createNewProject" />
            </div>
          </template>
          <template #footer><BaseButton @click="createNewProject" type="primary">Create</BaseButton></template>
        </BaseModal>
        
        <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
          <template #header><h3>Create New Graph</h3></template>
          <template #body>
            <div class="modal-form-row">
              <label>Graph Name:</label>
              <BaseInput v-model="newGraphName" placeholder="Enter graph name" @keyup.enter="createNewGraph" />
            </div>
          </template>
          <template #footer><BaseButton @click="createNewGraph" type="primary">Create</BaseButton></template>
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
  top: 0; left: 0; right: 0; bottom: 0;
  width: 100%; height: 100%;
}

.doodle-widget-root .graph-editor-container {
  display: flex;
  flex-direction: column;
  width: 100%; height: 100%;
  overflow: hidden;
  position: relative;
}

.doodle-widget-root .cytoscape-container,
.cytoscape-container {
  flex: 1;
  display: block;
  width: 100%; height: 100%;
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
  width: 100%; height: 100%;
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
</style>

<style>
.doodle-bugs-ui-overlay {
  position: fixed;
  top: 0; left: 0;
  width: 100vw; height: 100vh;
  z-index: 9999;
  pointer-events: none;
  
  --font-family-sans: -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
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
}

.sidebar-wrapper.left {
  flex-direction: row;
}

.sidebar-wrapper.right {
  flex-direction: row-reverse;
}

.drag-handle {
  width: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  padding: 8px 0;
  cursor: grab;
  opacity: 0.5;
  transition: opacity 0.2s;
}

.drag-handle span {
  display: block;
  width: 4px;
  height: 4px;
  background: var(--theme-text-secondary);
  border-radius: 50%;
}

.drag-handle:hover {
  opacity: 1;
}

.drag-handle:active {
  cursor: grabbing;
}

.drag-handle.left {
  margin-right: 4px;
}

.drag-handle.right {
  margin-left: 4px;
}

.collapsed-sidebar-trigger {
  position: fixed;
  top: 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 32px;
  height: 32px;
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  border-radius: 6px;
  cursor: pointer;
  box-shadow: var(--shadow-floating);
  transition: background 0.2s, transform 0.2s;
  z-index: 10001;
}

.collapsed-sidebar-trigger.left {
  left: 16px;
}

.collapsed-sidebar-trigger.right {
  right: 16px;
}

.collapsed-sidebar-trigger span {
  display: block;
  width: 16px;
  height: 2px;
  background: var(--theme-text-secondary);
  border-radius: 1px;
  transition: background 0.2s;
}

.collapsed-sidebar-trigger:hover {
  background: var(--theme-bg-hover);
}

.collapsed-sidebar-trigger:hover span {
  background: var(--theme-primary);
}

.sidebar-wrapper .floating-sidebar .sidebar-header {
  cursor: grab;
}

.sidebar-wrapper .floating-sidebar .sidebar-header:active {
  cursor: grabbing;
}

.doodle-bugs-ui-overlay .toolbar-container {
  pointer-events: auto;
}

.floating-panel {
  position: fixed;
  pointer-events: auto;
  z-index: 10001;
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

/* Debug border for sidebar wrapper */
.sidebar-wrapper {
  outline: 2px dashed rgba(255, 0, 0, 0.3);
}
</style>
