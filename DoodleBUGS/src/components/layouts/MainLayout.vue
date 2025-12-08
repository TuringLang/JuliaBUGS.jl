<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, reactive } from 'vue'
import { storeToRefs } from 'pinia'
import type { LayoutOptions, Core } from 'cytoscape'
import GraphEditor from '../canvas/GraphEditor.vue'
import FloatingBottomToolbar from '../canvas/FloatingBottomToolbar.vue'
import FloatingPanel from '../common/FloatingPanel.vue'
import BaseModal from '../common/BaseModal.vue'
import BaseInput from '../ui/BaseInput.vue'
import BaseButton from '../ui/BaseButton.vue'
import LeftSidebar from './LeftSidebar.vue'
import RightSidebar from './RightSidebar.vue'
import AboutModal from './AboutModal.vue'
import FaqModal from './FaqModal.vue'
import ExportModal from './ExportModal.vue'
import GraphStyleModal from './GraphStyleModal.vue'
import ShareModal from './ShareModal.vue'
import ValidationIssuesModal from './ValidationIssuesModal.vue'
import DebugPanel from '../common/DebugPanel.vue'
import CodePreviewPanel from '../panels/CodePreviewPanel.vue'
import DataInputPanel from '../panels/DataInputPanel.vue'
import ScriptSettingsPanel from '../panels/ScriptSettingsPanel.vue'
import { useGraphElements } from '../../composables/useGraphElements'
import { useProjectStore } from '../../stores/projectStore'
import { useGraphStore } from '../../stores/graphStore'
import { useUiStore } from '../../stores/uiStore'
import { useDataStore } from '../../stores/dataStore'
import { useScriptStore } from '../../stores/scriptStore'
import { useGraphInstance } from '../../composables/useGraphInstance'
import { useGraphValidator } from '../../composables/useGraphValidator'
import {
  useBugsCodeGenerator,
  generateStandaloneScript,
} from '../../composables/useBugsCodeGenerator'
import type { GraphElement, NodeType, ExampleModel, GraphNode } from '../../types'

interface ExportOptions {
  bg: string
  full: boolean
  scale: number
  quality?: number
  maxWidth?: number
  maxHeight?: number
}

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()

const { parsedGraphData } = storeToRefs(dataStore)
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { generatedCode } = useBugsCodeGenerator(elements)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { samplerSettings, standaloneScript } = storeToRefs(scriptStore)
const {
  isLeftSidebarOpen,
  isRightSidebarOpen,
  canvasGridStyle,
  isDarkMode,
  activeRightTab,
  isGridEnabled,
  gridSize,
  showZoomControls,
  showDebugPanel,
  activeLeftAccordionTabs,
  isDetachModeActive,
  showDetachModeControl,
} = storeToRefs(uiStore)

const currentMode = ref<string>('select')
const currentNodeType = ref<NodeType>('stochastic')

// Modals State
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
const shareUrl = ref('')
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null)

// Data Import Ref
const dataImportInput = ref<HTMLInputElement | null>(null)
const graphImportInput = ref<HTMLInputElement | null>(null)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const importedGraphData = ref<any>(null)
const isDragOver = ref(false)

// Local viewport state for smooth UI updates
const viewportState = ref({ zoom: 1, pan: { x: 0, y: 0 } })

// Panel positions and sizes (reactive objects for FloatingPanel)
// Default positions: data panel on bottom-left, code panel on bottom-right
const codePanelPos = reactive({ 
  x: typeof window !== 'undefined' ? window.innerWidth - 420 : 0, 
  y: typeof window !== 'undefined' ? window.innerHeight - 380 : 0
})
const codePanelSize = reactive({ width: 400, height: 300 })
const dataPanelPos = reactive({ 
  x: 20, 
  y: typeof window !== 'undefined' ? window.innerHeight - 380 : 0
})
const dataPanelSize = reactive({ width: 400, height: 300 })

// Computed property for validation status
const isModelValid = computed(() => validationErrors.value.size === 0)

// Pinned Graph Title Computation
const pinnedGraphTitle = computed(() => {
  if (!projectStore.currentProject || !graphStore.currentGraphId) return null
  const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
  return graph ? graph.name : null
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

const toggleJsonPanel = () => {
  showDebugPanel.value = true
}

// Dark Mode Handling
watch(
  isDarkMode,
  (val) => {
    const element = document.querySelector('html')
    if (val) element?.classList.add('dark-mode')
    else element?.classList.remove('dark-mode')
  },
  { immediate: true }
)

// Viewport Persistence Logic
let saveViewportTimeout: ReturnType<typeof setTimeout> | null = null

const persistViewport = () => {
  if (saveViewportTimeout) {
    clearTimeout(saveViewportTimeout)
    saveViewportTimeout = null
  }
  if (graphStore.currentGraphId) {
    graphStore.updateGraphViewport(
      graphStore.currentGraphId,
      viewportState.value.zoom,
      viewportState.value.pan
    )
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
    cy.animate({
      zoom: targetZoom,
      pan: targetPan,
      duration: 500,
      easing: 'ease-in-out-cubic',
    })
  } else {
    cy.viewport({ zoom: targetZoom, pan: targetPan })
  }
}

// Minification Helpers
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
  x: 'x',
  y: 'y',
}

const nodeTypeMap: Record<string, number> = {
  stochastic: 1,
  deterministic: 2,
  constant: 3,
  observed: 4,
  plate: 5,
}
const revNodeTypeMap = {
  1: 'stochastic',
  2: 'deterministic',
  3: 'constant',
  4: 'observed',
  5: 'plate',
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const minifyGraph = (elements: GraphElement[]): any[] => {
  return elements.map((el) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const min: any = {}
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
      const edge = el
      min[keyMap.id] = edge.id.replace('edge_', '')
      min[keyMap.type] = 1
      min[keyMap.source] = edge.source.replace('node_', '').replace('plate_', '')
      min[keyMap.target] = edge.target.replace('node_', '').replace('plate_', '')
    }
    return min
  })
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const expandGraph = (minElements: any[]): GraphElement[] => {
  return minElements.map((min) => {
    if (min[keyMap.type] === 0) {
      // Node
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const node: any = {
        id:
          min[keyMap.id].startsWith('node_') || min[keyMap.id].startsWith('plate_')
            ? min[keyMap.id]
            : (min[keyMap.nodeType] === 5 ? 'plate_' : 'node_') + min[keyMap.id],
        name: min[keyMap.name],
        type: 'node',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        nodeType: (revNodeTypeMap as any)[min[keyMap.nodeType]],
        position: {
          x: min[keyMap.position] && !isNaN(min[keyMap.position][0]) ? min[keyMap.position][0] : 0,
          y: min[keyMap.position] && !isNaN(min[keyMap.position][1]) ? min[keyMap.position][1] : 0,
        },
      }
      if (min[keyMap.parent]) {
        const pid = min[keyMap.parent]
        node.parent = pid.startsWith('plate_') || pid.startsWith('node_') ? pid : 'plate_' + pid
      }
      if (min[keyMap.distribution]) node.distribution = min[keyMap.distribution]
      if (min[keyMap.equation]) node.equation = min[keyMap.equation]
      if (min[keyMap.observed]) node.observed = true
      if (min[keyMap.indices]) node.indices = min[keyMap.indices]
      if (min[keyMap.loopVariable]) node.loopVariable = min[keyMap.loopVariable]
      if (min[keyMap.loopRange]) node.loopRange = min[keyMap.loopRange]
      if (min[keyMap.param1]) node.param1 = min[keyMap.param1]
      if (min[keyMap.param2]) node.param2 = min[keyMap.param2]
      if (min[keyMap.param3]) node.param3 = min[keyMap.param3]
      return node as GraphNode
    } else {
      // Edge
      return {
        id: min[keyMap.id].startsWith('edge_') ? min[keyMap.id] : 'edge_' + min[keyMap.id],
        type: 'edge',
        source:
          min[keyMap.source].startsWith('node_') || min[keyMap.source].startsWith('plate_')
            ? min[keyMap.source]
            : 'node_' + min[keyMap.source],
        target:
          min[keyMap.target].startsWith('node_') || min[keyMap.target].startsWith('plate_')
            ? min[keyMap.target]
            : 'node_' + min[keyMap.target],
      }
    }
  })
}

// Compression Helpers
const compressAndEncode = async (jsonStr: string): Promise<string> => {
  try {
    if (!window.CompressionStream) throw new Error('CompressionStream not supported')
    // Create a stream from the string
    const stream = new Blob([jsonStr]).stream()
    // Pipe through gzip compressor
    const compressedStream = stream.pipeThrough(new CompressionStream('gzip'))
    // Read response
    const response = new Response(compressedStream)
    const blob = await response.blob()
    const buffer = await blob.arrayBuffer()

    // Convert to binary string safely
    const bytes = new Uint8Array(buffer)
    let binaryStr = ''
    const len = bytes.byteLength
    for (let i = 0; i < len; i++) {
      binaryStr += String.fromCharCode(bytes[i])
    }

    // Return with prefix to identify compressed data
    return 'gz_' + btoa(binaryStr)
  } catch (e) {
    console.warn('Compression failed or not supported, falling back to legacy encoding', e)
    // Fallback to old method if compression API is missing or fails
    return btoa(unescape(encodeURIComponent(jsonStr)))
  }
}

const decodeAndDecompress = async (input: string): Promise<string> => {
  // Check for compressed prefix
  if (input.startsWith('gz_')) {
    try {
      if (!window.DecompressionStream) throw new Error('DecompressionStream not supported')
      const base64 = input.slice(3)
      const binaryStr = atob(base64)
      const bytes = new Uint8Array(binaryStr.length)
      for (let i = 0; i < binaryStr.length; i++) {
        bytes[i] = binaryStr.charCodeAt(i)
      }

      const stream = new Blob([bytes]).stream()
      const decompressedStream = stream.pipeThrough(new DecompressionStream('gzip'))
      const response = new Response(decompressedStream)
      return await response.text()
    } catch (e) {
      console.error('Decompression failed', e)
      throw e
    }
  } else {
    // Legacy decoding
    return decodeURIComponent(escape(atob(input)))
  }
}

const generateShareLink = async (payload: object) => {
  try {
    const jsonStr = JSON.stringify(payload)
    const base64 = await compressAndEncode(jsonStr)

    const baseUrl = window.location.origin + window.location.pathname
    shareUrl.value = `${baseUrl}?share=${encodeURIComponent(base64)}`
  } catch (e) {
    console.error('Failed to generate share link:', e)
    alert('Failed to generate share link. Model might be too large.')
  }
}

const handleShare = () => {
  if (!graphStore.currentGraphId) return
  shareUrl.value = '' // Reset
  showShareModal.value = true
}

const handleGenerateShareLink = async (options: {
  scope: 'current' | 'project' | 'custom'
  selectedGraphIds?: string[]
}) => {
  if (!projectStore.currentProject) return

  let payload = {}

  // Helper to get graph data (from memory or storage)
  const getGraphDataForShare = (graphId: string) => {
    let elements: GraphElement[] = []
    let dataContent = '{}'
    let name = 'Graph'

    const graphMeta = projectStore.currentProject?.graphs.find((g) => g.id === graphId)
    if (graphMeta) name = graphMeta.name

    if (graphId === graphStore.currentGraphId) {
      elements = graphStore.currentGraphElements
      dataContent = dataStore.dataContent
    } else {
      const storedGraph = localStorage.getItem(`doodlebugs-graph-${graphId}`)
      const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`)

      if (storedGraph) {
        try {
          elements = JSON.parse(storedGraph).elements
        } catch {}
      }
      if (storedData) {
        try {
          const parsed = JSON.parse(storedData)
          dataContent =
            parsed.content ||
            (parsed.jsonData
              ? JSON.stringify({
                  data: JSON.parse(parsed.jsonData || '{}'),
                  inits: JSON.parse(parsed.jsonInits || '{}'),
                })
              : '{}')
        } catch {}
      }
    }

    // Minify Data
    try {
      const d = JSON.parse(dataContent)
      dataContent = JSON.stringify(d)
    } catch {
      /* ignore */
    }

    return { name, elements, dataContent }
  }

  if (options.scope === 'current') {
    const targetId = options.selectedGraphIds?.[0] || graphStore.currentGraphId
    if (!targetId) return

    const { name, elements, dataContent } = getGraphDataForShare(targetId)
    // Use v2 format for single graph for backward compatibility / simplicity
    payload = {
      v: 2,
      n: name,
      e: minifyGraph(elements),
      d: dataContent,
    }
  } else {
    // Project or Custom Scope - Use v3 format
    const targetIds =
      options.scope === 'project'
        ? projectStore.currentProject.graphs.map((g) => g.id)
        : options.selectedGraphIds || []

    const graphsData = targetIds.map((id) => {
      const { name, elements, dataContent } = getGraphDataForShare(id)
      return {
        n: name,
        e: minifyGraph(elements),
        d: dataContent,
      }
    })

    payload = {
      v: 3,
      pn: projectStore.currentProject.name,
      g: graphsData,
    }
  }

  await generateShareLink(payload)
}

// Data Import Logic
const handleDataImport = (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return

  const reader = new FileReader()
  reader.onload = (e) => {
    const content = e.target?.result as string
    try {
      // Validate JSON
      JSON.parse(content)
      dataStore.dataContent = content
    } catch {
      alert('Invalid JSON file format.')
    }
    // Reset file input
    if (dataImportInput.value) dataImportInput.value.value = ''
  }
  reader.readAsText(file)
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

const handleLoadShared = async () => {
  const params = new URLSearchParams(window.location.search)
  const shareParam = params.get('share')

  let jsonStr: string | null = null

  if (shareParam) {
    try {
      jsonStr = await decodeAndDecompress(shareParam)
    } catch {
      console.error('Failed to decode base64 share')
    }
  }

  if (jsonStr) {
    try {
      const payload = JSON.parse(jsonStr)

      // Handle V3 (Project)
      if (payload.v === 3 && payload.pn && payload.g) {
        projectStore.createProject(payload.pn + ' (Shared)')
        if (projectStore.currentProjectId) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          payload.g.forEach((graphData: any) => {
            const newGraph = projectStore.addGraphToProject(
              projectStore.currentProjectId!,
              graphData.n
            )
            if (newGraph) {
              try {
                const elements = expandGraph(graphData.e)
                graphStore.updateGraphElements(newGraph.id, elements)
                graphStore.updateGraphLayout(newGraph.id, 'preset')

                if (graphData.d) {
                  try {
                    const dObj = JSON.parse(graphData.d)
                    dataStore.updateGraphData(newGraph.id, {
                      content: JSON.stringify(dObj, null, 2),
                    })
                  } catch {
                    dataStore.updateGraphData(newGraph.id, { content: graphData.d })
                  }
                }
              } catch (e) {
                console.error(`Error loading graph ${graphData.n}:`, e)
              }
            }
          })

          // Force save the project list to ensure persistence across reloads
          projectStore.saveProjects()

          // Select first graph
          if (projectStore.currentProject?.graphs.length) {
            graphStore.selectGraph(projectStore.currentProject.graphs[0].id)
          }
        }
      }
      // Handle V2 (Single Graph)
      else if (payload && payload.n && payload.e) {
        projectStore.createProject('Shared Project')
        if (projectStore.currentProjectId) {
          const newGraph = projectStore.addGraphToProject(projectStore.currentProjectId, payload.n)
          if (newGraph) {
            let elements = payload.e
            // Check if version 2 (minified)
            if (payload.v === 2) {
              elements = expandGraph(payload.e)
            }

            graphStore.updateGraphElements(newGraph.id, elements)
            graphStore.updateGraphLayout(newGraph.id, 'preset')

            if (payload.d) {
              try {
                const dObj = JSON.parse(payload.d)
                dataStore.updateGraphData(newGraph.id, { content: JSON.stringify(dObj, null, 2) })
              } catch {
                dataStore.updateGraphData(newGraph.id, { content: payload.d })
              }
            }
            projectStore.saveProjects()
            graphStore.selectGraph(newGraph.id)
          }
        }
      }

      // Clean URL without reloading
      const newUrl = window.location.origin + window.location.pathname
      window.history.replaceState({}, document.title, newUrl)

      // Force fit graph to viewport to ensure visibility
      setTimeout(() => {
        handleFit()
      }, 500)
    } catch (e) {
      console.error('Failed to load shared model:', e)
      alert('Invalid or corrupted share link.')
    }
  }
}

onMounted(async () => {
  projectStore.loadProjects()

  // Check for shared model
  if (window.location.search.includes('share=')) {
    await handleLoadShared()
  }

  // Default init if no shared model loaded or no projects exist
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project')
    if (projectStore.currentProjectId) await handleLoadExample('rats')
  } else {
    // If not a fresh shared load, restore last session
    if (!window.location.search.includes('share=')) {
      const lastGraphId = localStorage.getItem('doodlebugs-currentGraphId')
      if (lastGraphId && projectStore.currentProject?.graphs.some((g) => g.id === lastGraphId)) {
        graphStore.selectGraph(lastGraphId)
      } else if (projectStore.currentProject?.graphs.length) {
        graphStore.selectGraph(projectStore.currentProject.graphs[0].id)
      }
    }
  }
  validateGraph()

  // Mobile: hide zoom controls by default on small screens
  if (window.innerWidth < 768) {
    showZoomControls.value = false
  }

  // Force save on page reload/close
  window.addEventListener('beforeunload', persistViewport)
})

onUnmounted(() => {
  window.removeEventListener('beforeunload', persistViewport)
  persistViewport()
})

// Sync viewport state when graph changes
watch(
  () => graphStore.currentGraphId,
  (newId) => {
    if (newId) {
      const content = graphStore.graphContents.get(newId)
      if (content) {
        viewportState.value = {
          zoom: content.zoom ?? 1,
          pan: content.pan ?? { x: 0, y: 0 },
        }
      }
    }
  },
  { immediate: true }
)

// Initialize Code Panel Position if missing
watch(
  [isCodePanelOpen, () => graphStore.currentGraphId],
  ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === graphId)

      if (graph) {
        const needsInit = graph.codePanelX === undefined || graph.codePanelY === undefined
        if (needsInit) {
          // Simple default dimensions
          const panelW = 400
          const panelH = 300

          // Position on the RIGHT side relative to the graph view
          const viewportW = window.innerWidth
          // Sidebar is ~320px + 16px margin = 336px.
          const rightSidebarOffset = isRightSidebarOpen.value ? 340 : 20

          let targetScreenX = viewportW - rightSidebarOffset - panelW - 10
          if (targetScreenX < 20) targetScreenX = 20 // Safety check

          // Top offset
          const targetScreenY = 90

          projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
            codePanelX: targetScreenX,
            codePanelY: targetScreenY,
            codePanelWidth: panelW,
            codePanelHeight: panelH,
          })
        }
      }
    }
  },
  { immediate: true }
)

// Initialize Data Panel Position if missing
watch(
  [isDataPanelOpen, () => graphStore.currentGraphId],
  ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === graphId)

      if (graph) {
        const needsInit = graph.dataPanelX === undefined || graph.dataPanelY === undefined
        if (needsInit) {
          // Simple default dimensions
          const panelW = 400
          const panelH = 300

          // Position on the LEFT side relative to the graph view
          // Sidebar is ~300px + 16px margin.
          const leftSidebarOffset = isLeftSidebarOpen.value ? 320 : 20

          const targetScreenX = leftSidebarOffset + 20

          // Top offset
          const targetScreenY = 90

          projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
            dataPanelX: targetScreenX,
            dataPanelY: targetScreenY,
            dataPanelWidth: panelW,
            dataPanelHeight: panelH,
          })
        }
      }
    }
  },
  { immediate: true }
)

const handleLayoutUpdated = (layoutName: string) => {
  if (graphStore.currentGraphId) {
    graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName)
  }
}

const handleViewportChanged = (v: { zoom: number; pan: { x: number; y: number } }) => {
  // Update local state immediately for smooth UI
  viewportState.value = v

  // Debounce persistence
  if (saveViewportTimeout) clearTimeout(saveViewportTimeout)
  saveViewportTimeout = setTimeout(persistViewport, 200)
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

  cy.one('layoutstop', () => {
    smartFit(cy, true)
  })

  cy.layout(options).run()
  handleLayoutUpdated(layoutName)
}

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element
  if (element) {
    if (!uiStore.isRightTabPinned) {
      uiStore.setActiveRightTab('properties')
      const isMobile = window.innerWidth < 768
      if (isMobile && isLeftSidebarOpen.value) {
        isLeftSidebarOpen.value = false
      }
      if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true
    }
  } else {
    if (!uiStore.isRightTabPinned && isRightSidebarOpen.value) {
      isRightSidebarOpen.value = false
    }
  }
}

const handleSelectNodeFromModal = (nodeId: string) => {
  const targetNode = elements.value.find((el) => el.id === nodeId)
  if (targetNode) {
    handleElementSelected(targetNode)
    const cy = getCyInstance(graphStore.currentGraphId!)
    if (cy) {
      // Programmatically select node in Cytoscape for visual feedback
      cy.elements().removeClass('cy-selected')
      const cyNode = cy.getElementById(nodeId)
      cyNode.addClass('cy-selected')

      cy.animate({
        fit: { eles: cyNode, padding: 50 },
        duration: 500,
      })
    }
  }
}

const createNewProject = () => {
  if (newProjectName.value.trim()) {
    projectStore.createProject(newProjectName.value.trim())
    showNewProjectModal.value = false
    newProjectName.value = ''
    activeLeftAccordionTabs.value = [...new Set([...activeLeftAccordionTabs.value, 'project'])]
    isLeftSidebarOpen.value = true
  }
}

const createNewGraph = () => {
  if (projectStore.currentProject && (newGraphName.value.trim() || importedGraphData.value)) {
    const name = newGraphName.value.trim() || importedGraphData.value?.name || 'New Graph'
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId!, name)

    if (newGraphMeta && importedGraphData.value) {
      // Populate with imported data
      graphStore.updateGraphElements(newGraphMeta.id, importedGraphData.value.elements)

      if (importedGraphData.value.dataContent) {
        dataStore.updateGraphData(newGraphMeta.id, { content: importedGraphData.value.dataContent })
      }

      // Restore layout settings if available
      if (importedGraphData.value.layout) {
        projectStore.updateGraphLayout(
          projectStore.currentProject.id,
          newGraphMeta.id,
          importedGraphData.value.layout
        )
      }

      graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
    }

    showNewGraphModal.value = false
    newGraphName.value = ''
    importedGraphData.value = null
    if (graphImportInput.value) graphImportInput.value.value = ''
  }
}

const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
  if (!graphStore.currentGraphId) return
  currentExportType.value = format
  showExportModal.value = true
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

const handleConfirmExport = (options: ExportOptions) => {
  const cy = (
    graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
  ) as Core | null
  if (!cy || !currentExportType.value) return

  const fileName = `graph.${currentExportType.value}`

  try {
    let blob: Blob

    if (currentExportType.value === 'svg') {
      const svgOptions = { bg: options.bg, full: options.full, scale: options.scale }
      blob = new Blob([cy.svg(svgOptions)], { type: 'image/svg+xml;charset=utf-8' })
    } else {
      const baseOptions = {
        bg: options.bg,
        full: options.full,
        scale: options.scale,
        maxWidth: options.maxWidth,
        maxHeight: options.maxHeight,
        output: 'blob' as const,
      }

      if (currentExportType.value === 'png') {
        blob = cy.png(baseOptions) as unknown as Blob
      } else {
        blob = cy.jpg({ ...baseOptions, quality: options.quality }) as unknown as Blob
      }
    }

    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = fileName
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  } catch (err) {
    console.error(`Failed to export ${currentExportType.value}:`, err)
  }
}

const handleExportGraphJson = () => {
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
    layout: {
      showCodePanel: graphMeta.showCodePanel,
      codePanelX: graphMeta.codePanelX,
      codePanelY: graphMeta.codePanelY,
      codePanelWidth: graphMeta.codePanelWidth,
      codePanelHeight: graphMeta.codePanelHeight,
      showDataPanel: graphMeta.showDataPanel,
      dataPanelX: graphMeta.dataPanelX,
      dataPanelY: graphMeta.dataPanelY,
      dataPanelWidth: graphMeta.dataPanelWidth,
      dataPanelHeight: graphMeta.dataPanelHeight,
      gridEnabled: graphMeta.gridEnabled,
      gridSize: graphMeta.gridSize,
      gridStyle: graphMeta.gridStyle,
    },
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

const getScriptContent = () => {
  const dataPayload = parsedGraphData.value.data || {}
  const initsPayload = parsedGraphData.value.inits || {}
  return generateStandaloneScript({
    modelCode: generatedCode.value,
    data: dataPayload,
    inits: initsPayload,
    settings: {
      n_samples: samplerSettings.value.n_samples,
      n_adapts: samplerSettings.value.n_adapts,
      n_chains: samplerSettings.value.n_chains,
      seed: samplerSettings.value.seed ?? undefined,
    },
  })
}

const handleGenerateStandalone = () => {
  const script = getScriptContent()
  scriptStore.standaloneScript = script
  uiStore.setActiveRightTab('script')
  uiStore.isRightSidebarOpen = true
}

// Auto-update script if it exists or script panel is open
watch(
  [generatedCode, parsedGraphData, samplerSettings],
  () => {
    // Update if script already exists OR if the panel is open
    if (standaloneScript.value || (activeRightTab.value === 'script' && isRightSidebarOpen.value)) {
      scriptStore.standaloneScript = getScriptContent()
    }
  },
  { deep: true }
)

const handleScriptSettingsDone = () => {
  // Also regenerate immediately on settings close
  const script = getScriptContent()
  scriptStore.standaloneScript = script
  showScriptSettingsModal.value = false
}

const handleDownloadScript = () => {
  const content = standaloneScript.value
  if (!content) return
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
  const fileName = 'DoodleBUGS-Julia-Script.jl'
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = fileName
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

const handleOpenScriptSettings = () => {
  showScriptSettingsModal.value = true
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

    projectStore.updateGraphLayout(projectStore.currentProject!.id, newGraphMeta.id, {})
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
  } catch (error) {
    console.error('Failed to load example model:', error)
  }
}

const toggleLeftSidebar = () => {
  const isMobile = window.innerWidth < 768
  if (!isLeftSidebarOpen.value && isMobile) {
    isRightSidebarOpen.value = false
  }
  isLeftSidebarOpen.value = !isLeftSidebarOpen.value
}

const toggleRightSidebar = () => {
  const isMobile = window.innerWidth < 768
  if (!isRightSidebarOpen.value && isMobile) {
    isLeftSidebarOpen.value = false
  }
  isRightSidebarOpen.value = !isRightSidebarOpen.value
}

const handleUndo = () => {
  if (graphStore.currentGraphId) {
    getUndoRedoInstance(graphStore.currentGraphId)?.undo()
  }
}

const handleRedo = () => {
  if (graphStore.currentGraphId) {
    getUndoRedoInstance(graphStore.currentGraphId)?.redo()
  }
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

// Panel event handlers for FloatingPanel component
const handleCodePanelDragEnd = (pos: { x: number; y: number }) => {
  codePanelPos.x = pos.x
  codePanelPos.y = pos.y
  if (projectStore.currentProject && graphStore.currentGraphId) {
    projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
      codePanelX: pos.x,
      codePanelY: pos.y,
    })
  }
}

const handleCodePanelResizeEnd = (size: { width: number; height: number }) => {
  codePanelSize.width = size.width
  codePanelSize.height = size.height
  if (projectStore.currentProject && graphStore.currentGraphId) {
    projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
      codePanelWidth: size.width,
      codePanelHeight: size.height,
    })
  }
}

const handleDataPanelDragEnd = (pos: { x: number; y: number }) => {
  dataPanelPos.x = pos.x
  dataPanelPos.y = pos.y
  if (projectStore.currentProject && graphStore.currentGraphId) {
    projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
      dataPanelX: pos.x,
      dataPanelY: pos.y,
    })
  }
}

const handleDataPanelResizeEnd = (size: { width: number; height: number }) => {
  dataPanelSize.width = size.width
  dataPanelSize.height = size.height
  if (projectStore.currentProject && graphStore.currentGraphId) {
    projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
      dataPanelWidth: size.width,
      dataPanelHeight: size.height,
    })
  }
}

// Load panel positions and sizes from graph state
watch(
  [() => graphStore.currentGraphId, () => projectStore.currentProject?.graphs],
  () => {
    const currentGraphId = graphStore.currentGraphId
    if (currentGraphId && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === currentGraphId)
      if (graph) {
        // Use saved positions or defaults: data panel on bottom-left, code panel on bottom-right
        const defaultCodeX = typeof window !== 'undefined' ? window.innerWidth - 420 : 0
        const defaultY = typeof window !== 'undefined' ? window.innerHeight - 380 : 0
        codePanelPos.x = graph.codePanelX ?? defaultCodeX
        codePanelPos.y = graph.codePanelY ?? defaultY
        codePanelSize.width = graph.codePanelWidth ?? 400
        codePanelSize.height = graph.codePanelHeight ?? 300
        dataPanelPos.x = graph.dataPanelX ?? 20
        dataPanelPos.y = graph.dataPanelY ?? defaultY
        dataPanelSize.width = graph.dataPanelWidth ?? 400
        dataPanelSize.height = graph.dataPanelHeight ?? 300
      }
    }
  },
  { immediate: true, deep: true }
)

const handleSidebarContainerClick = (e: MouseEvent) => {
  if ((e.target as HTMLElement).closest('.theme-toggle-header')) return
  if (!isLeftSidebarOpen.value) {
    toggleLeftSidebar()
  }
}

watch(showNewGraphModal, (val) => {
  if (!val) {
    importedGraphData.value = null
    newGraphName.value = ''
    if (graphImportInput.value) graphImportInput.value.value = ''
    isDragOver.value = false
  }
})

// Update the Left Sidebar Accordion model from the store
const updateActiveAccordionTabs = (val: string | string[]) => {
  // PrimeVue might emit single value or array depending on config, but multiple=true implies array
  const newVal = Array.isArray(val) ? val : [val]
  activeLeftAccordionTabs.value = newVal
}

const clearImportedData = () => {
  importedGraphData.value = null
  if (graphImportInput.value) {
    graphImportInput.value.value = ''
  }
}
</script>
<template>
  <div class="app-layout">
    <main class="canvas-area">
      <GraphEditor
        v-if="graphStore.currentGraphId"
        :key="graphStore.currentGraphId"
        :graph-id="graphStore.currentGraphId"
        :is-grid-enabled="isGridEnabled"
        @update:is-grid-enabled="isGridEnabled = $event"
        :grid-size="gridSize"
        @update:grid-size="gridSize = $event"
        :grid-style="canvasGridStyle"
        :current-mode="currentMode"
        :elements="elements"
        :current-node-type="currentNodeType"
        :validation-errors="validationErrors"
        :show-zoom-controls="false"
        @update:current-mode="currentMode = $event"
        @update:current-node-type="currentNodeType = $event"
        @element-selected="handleElementSelected"
        @layout-updated="handleLayoutUpdated"
        @viewport-changed="handleViewportChanged"
      />
      <div v-else class="empty-state">
        <p>No graph selected. Create or select a graph to start.</p>
        <BaseButton @click="showNewGraphModal = true" type="primary">Create New Graph</BaseButton>
      </div>
    </main>

    <!-- Left Sidebar -->
    <LeftSidebar
      :activeAccordionTabs="activeLeftAccordionTabs"
      @update:activeAccordionTabs="updateActiveAccordionTabs"
      :projectName="projectStore.currentProject?.name || null"
      :pinnedGraphTitle="pinnedGraphTitle"
      :isGridEnabled="isGridEnabled"
      :gridSize="gridSize"
      :showZoomControls="showZoomControls"
      :showDebugPanel="showDebugPanel"
      :isCodePanelOpen="isCodePanelOpen"
      :isDetachModeActive="isDetachModeActive"
      :showDetachModeControl="showDetachModeControl"
      @toggle-left-sidebar="toggleLeftSidebar"
      @new-project="showNewProjectModal = true"
      @new-graph="showNewGraphModal = true"
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
    />

    <Transition name="fade">
      <div
        v-if="!isLeftSidebarOpen"
        class="collapsed-sidebar-trigger left-trigger"
        @click="handleSidebarContainerClick"
      >
        <div class="sidebar-trigger-content gap-1">
          <div
            class="flex-grow flex items-center gap-2 overflow-hidden"
            style="flex-grow: 1; overflow: hidden"
          >
            <span class="logo-text-minimized">
              <span class="desktop-text">{{
                pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS'
              }}</span>
              <span class="mobile-text">DoodleBUGS</span>
            </span>
          </div>
          <div class="flex items-center flex-shrink-0" style="flex-shrink: 0">
            <button
              @click.stop="uiStore.toggleDarkMode()"
              class="theme-toggle-header"
              :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'"
            >
              <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
            </button>
            <div class="toggle-icon-wrapper">
              <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon">
                <path
                  fill="currentColor"
                  fill-rule="evenodd"
                  d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"
                  clip-rule="evenodd"
                ></path>
              </svg>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Right Sidebar -->
    <RightSidebar
      :selectedElement="selectedElement"
      :validationErrors="validationErrors"
      :isModelValid="isModelValid"
      @toggle-right-sidebar="toggleRightSidebar"
      @update-element="updateElement"
      @delete-element="deleteElement"
      @show-validation-issues="showValidationModal = true"
      @open-script-settings="handleOpenScriptSettings"
      @download-script="handleDownloadScript"
      @generate-script="handleGenerateStandalone"
      @share="handleShare"
      @open-export-modal="openExportModal"
      @export-json="handleExportGraphJson"
    />

    <Transition name="fade">
      <div
        v-if="!isRightSidebarOpen"
        class="collapsed-sidebar-trigger right"
        @click="toggleRightSidebar"
      >
        <div class="sidebar-trigger-content gap-2">
          <span class="sidebar-title-minimized">Inspector</span>
          <div class="flex items-center">
            <div
              class="status-indicator validation-status"
              @click.stop="showValidationModal = true"
              :class="isModelValid ? 'valid' : 'invalid'"
            >
              <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
            </div>
            <button
              class="header-icon-btn collapsed-share-btn"
              @click.stop="handleShare"
              title="Share via URL"
            >
              <i class="fas fa-share-alt"></i>
            </button>
            <div class="toggle-icon-wrapper">
              <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon">
                <path
                  fill="currentColor"
                  fill-rule="evenodd"
                  d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"
                  clip-rule="evenodd"
                ></path>
              </svg>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Code Panel using FloatingPanel -->
    <FloatingPanel
      v-if="isCodePanelOpen && graphStore.currentGraphId"
      title="BUGS Code Preview"
      icon="fas fa-code"
      :is-open="isCodePanelOpen"
      :default-width="codePanelSize.width"
      :default-height="codePanelSize.height"
      :default-x="codePanelPos.x"
      :default-y="codePanelPos.y"
      :show-download="true"
      @close="toggleCodePanel"
      @download="handleDownloadBugs"
      @drag-end="handleCodePanelDragEnd"
      @resize-end="handleCodePanelResizeEnd"
    >
      <CodePreviewPanel :is-active="true" />
    </FloatingPanel>

    <!-- Data Panel using FloatingPanel -->
    <FloatingPanel
      v-if="isDataPanelOpen && graphStore.currentGraphId"
      title="Data & Inits"
      icon="fas fa-database"
      badge="JSON"
      :is-open="isDataPanelOpen"
      :default-width="dataPanelSize.width"
      :default-height="dataPanelSize.height"
      :default-x="dataPanelPos.x"
      :default-y="dataPanelPos.y"
      :show-import="true"
      @close="toggleDataPanel"
      @import="dataImportInput?.click()"
      @drag-end="handleDataPanelDragEnd"
      @resize-end="handleDataPanelResizeEnd"
    >
      <DataInputPanel :is-active="true" />
      <!-- Hidden file input for Data Import -->
      <input
        type="file"
        ref="dataImportInput"
        accept=".json"
        style="display: none"
        @change="handleDataImport"
      />
    </FloatingPanel>

    <FloatingBottomToolbar
      :current-mode="currentMode"
      :current-node-type="currentNodeType"
      :show-code-panel="isCodePanelOpen"
      :show-data-panel="isDataPanelOpen"
      :show-json-panel="false"
      :show-zoom-controls="showZoomControls"
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
      @toggle-json-panel="toggleJsonPanel"
      @toggle-detach-mode="uiStore.toggleDetachMode"
      @open-style-modal="showStyleModal = true"
      @share="handleShare"
    />

    <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
      <template #header><h3>Create New Project</h3></template>
      <template #body>
        <div class="flex items-center gap-3">
          <label style="min-width: 100px; font-weight: 500">Project Name:</label>
          <BaseInput
            v-model="newProjectName"
            placeholder="Enter project name"
            @keyup.enter="createNewProject"
          />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="createNewProject" type="primary">Create</BaseButton>
      </template>
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
                  <small class="sub-text">{{ importedGraphData.name || 'Untitled Graph' }}</small>
                </div>
                <button class="remove-file-btn" @click.stop="clearImportedData" title="Remove file">
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

    <BaseModal :is-open="showScriptSettingsModal" @close="showScriptSettingsModal = false">
      <template #header><h3>Script Configuration</h3></template>
      <template #body>
        <ScriptSettingsPanel />
      </template>
      <template #footer>
        <BaseButton @click="handleScriptSettingsDone">Done</BaseButton>
      </template>
    </BaseModal>

    <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
    <FaqModal :is-open="showFaqModal" @close="showFaqModal = false" />
    <ExportModal
      :is-open="showExportModal"
      :export-type="currentExportType"
      @close="showExportModal = false"
      @confirm-export="handleConfirmExport"
    />
    <ValidationIssuesModal
      :is-open="showValidationModal"
      :validation-errors="validationErrors"
      :elements="elements"
      @select-node="handleSelectNodeFromModal"
      @close="showValidationModal = false"
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
    <DebugPanel v-if="showDebugPanel" @close="showDebugPanel = false" />
  </div>
</template>

<style scoped>
.app-layout {
  position: relative;
  width: 100vw;
  height: 100dvh;
  height: 100vh;
  overflow: hidden;
  background-color: var(--theme-bg-canvas);
}

.canvas-area {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  bottom: 0;
  z-index: 0;
  transition: bottom 0.1s ease;
}

.collapsed-sidebar-trigger {
  position: absolute;
  top: 16px;
  z-index: 49;
  padding: 8px 12px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  transition: all 0.2s ease;
  border: 1px solid var(--theme-border);
  background: var(--theme-bg-panel);
  cursor: pointer;
  min-width: 140px;
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

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--theme-text-secondary);
  gap: 1rem;
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
  margin: 0;
}
.validation-status.valid {
  color: var(--theme-success);
}
.validation-status.invalid {
  color: var(--theme-warning);
}

.instant-tooltip {
  position: absolute;
  top: 100%;
  right: 0;
  transform: none;
  background: var(--color-background-dark);
  color: var(--color-text-light);
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 0.75rem;
  white-space: nowrap;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.1s;
  margin-top: 6px;
  z-index: 100;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.status-indicator:hover .instant-tooltip {
  opacity: 1;
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

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.json-textarea {
  width: 100%;
  height: 120px;
  padding: 8px;
  font-family: monospace;
  font-size: 0.85em;
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-sm);
  background-color: var(--theme-bg-hover);
  color: var(--theme-text-primary);
  resize: vertical;
}

.file-upload-wrapper {
  margin-top: 5px;
}

.desktop-text {
  display: inline;
}
.mobile-text {
  display: none;
}

.divider {
  height: 1px;
  background: var(--theme-border);
  width: 100%;
}

.text-green-500 {
  color: var(--theme-success);
}
.font-bold {
  font-weight: bold;
}
.text-xs {
  font-size: 0.75rem;
}

/* New Graph Modal Styles */
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
