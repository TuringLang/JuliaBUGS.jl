<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, reactive } from 'vue'
import { storeToRefs } from 'pinia'
import { useToast } from 'primevue/usetoast'
import type { Core } from 'cytoscape'
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
import { useGraphLayout } from '../../composables/useGraphLayout'
import { usePersistence } from '../../composables/usePersistence'
import {
  useBugsCodeGenerator,
  generateStandaloneScript,
} from '../../composables/useBugsCodeGenerator'
import { useShareExport } from '../../composables/useShareExport'
import { useImportExport } from '../../composables/useImportExport'
import type { GraphElement, NodeType, UnifiedModelData } from '../../types'
import { examples, isUrl } from '../../config/examples'

interface ExportOptions {
  bg: string
  full: boolean
  scale: number
  quality?: number
  maxWidth?: number
  maxHeight?: number
}

const props = defineProps<{
  defaultModel?: string
}>()

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()
const toast = useToast()

const { parsedGraphData } = storeToRefs(dataStore)
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { generatedCode } = useBugsCodeGenerator(elements)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { samplerSettings, standaloneScript } = storeToRefs(scriptStore)
const { smartFit, applyLayoutWithFit } = useGraphLayout()
const { loadLastGraphId, getStoredGraphElements, getStoredDataContent } = usePersistence()
const { shareUrl, decodeAndDecompress, minifyGraph, expandGraph, generateShareLink } =
  useShareExport()
const { importedGraphData, processGraphFile, clearImportedData } = useImportExport()
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
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null)

// Data Import Ref
const dataImportInput = ref<HTMLInputElement | null>(null)
const graphImportInput = ref<HTMLInputElement | null>(null)
const isDragOver = ref(false)

// Local viewport state for smooth UI updates.
// Initialized to null to prevent saving default (0,0) values during rapid reloads.
const viewportState = ref<{ zoom: number; pan: { x: number; y: number } } | null>(null)

// Panel positions and sizes
const codePanelPos = reactive({
  x: typeof window !== 'undefined' ? window.innerWidth - 420 : 0,
  y: typeof window !== 'undefined' ? window.innerHeight - 380 : 0,
})
const codePanelSize = reactive({ width: 400, height: 300 })
const dataPanelPos = reactive({
  x: 20,
  y: typeof window !== 'undefined' ? window.innerHeight - 380 : 0,
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

// Code Panel Visibility
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

// Data Panel Visibility
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
    if (val) element?.classList.add('db-dark-mode')
    else element?.classList.remove('db-dark-mode')
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
  // Only save if we have a valid graph AND we have received at least one valid viewport update.
  // This prevents overwriting saved state with default {0,0} during fast reloads.
  if (graphStore.currentGraphId && viewportState.value) {
    graphStore.updateGraphViewport(
      graphStore.currentGraphId,
      viewportState.value.zoom,
      viewportState.value.pan
    )
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
      elements = getStoredGraphElements(graphId) as GraphElement[]
      dataContent = getStoredDataContent(graphId)
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
      JSON.parse(content)
      dataStore.dataContent = content
    } catch {
      alert('Invalid JSON file format.')
    }
    if (dataImportInput.value) dataImportInput.value.value = ''
  }
  reader.readAsText(file)
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

// Shared Model Loader
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

          projectStore.saveProjects()

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

      const newUrl = window.location.origin + window.location.pathname
      window.history.replaceState({}, document.title, newUrl)

      setTimeout(() => {
        handleFit()
      }, 500)
    } catch (e) {
      console.error('Failed to load shared model:', e)
      alert('Invalid or corrupted share link.')
    }
  }
}

// Generic Loader for both bundled and remote models
const loadModelData = async (data: UnifiedModelData | Record<string, unknown>, name: string) => {
  if (!projectStore.currentProjectId) return

  const newGraphMeta = projectStore.addGraphToProject(
    projectStore.currentProjectId,
    (data as UnifiedModelData).name || name
  )
  if (!newGraphMeta) return

  // Handle Elements
  if ((data as UnifiedModelData).elements) {
    graphStore.updateGraphElements(
      newGraphMeta.id,
      (data as UnifiedModelData).elements as GraphElement[]
    )
  } else if ((data as UnifiedModelData).graphJSON) {
    // Legacy support
    graphStore.updateGraphElements(
      newGraphMeta.id,
      (data as UnifiedModelData).graphJSON as GraphElement[]
    )
  }

  // Handle Data/Inits
  if ((data as UnifiedModelData).dataContent) {
    dataStore.updateGraphData(newGraphMeta.id, {
      content: (data as UnifiedModelData).dataContent || '',
    })
  } else if ((data as UnifiedModelData).data || (data as UnifiedModelData).inits) {
    // Legacy separate fields
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

  // Handle Layout
  graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
  if ((data as UnifiedModelData).layout) {
    projectStore.updateGraphLayout(
      projectStore.currentProjectId,
      newGraphMeta.id,
      (data as UnifiedModelData).layout
    )
  }

  graphStore.selectGraph(newGraphMeta.id)
}

// Main App Loading Logic: Local -> Github -> Turing
const handleLoadExample = async (exampleIdOrUrl: string) => {
  if (!projectStore.currentProjectId) return

  try {
    let modelData = null
    let modelName = 'Imported Model'
    let sourceDescription = ''

    const config = examples.find((e) => e.id === exampleIdOrUrl)
    const turingUrl = `https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/examples/${exampleIdOrUrl}/model.json`

    if (config) {
      modelName = config.name

      try {
        toast.add({
          severity: 'info',
          summary: 'Loading...',
          detail: `Loading ${modelName} from Local Path...`,
          life: 2000,
        })
        const localUrl = `${import.meta.env.BASE_URL}examples/${config.id}/model.json`
        const response = await fetch(localUrl)
        if (response.ok) {
          modelData = await response.json()
          sourceDescription = `Local Path`
        } else {
          throw new Error('Local fetch failed')
        }
      } catch {
        if (config.url) {
          const isGithub = config.url.includes('github')
          const sourceLabel = isGithub ? 'GitHub Source' : 'Remote Source'

          toast.add({
            severity: 'warn',
            summary: 'Local Not Found',
            detail: `Trying ${sourceLabel}...`,
            life: 2000,
          })

          try {
            const response = await fetch(config.url)
            if (response.ok) {
              modelData = await response.json()
              sourceDescription = sourceLabel
            } else {
              throw new Error(`${sourceLabel} fetch failed`)
            }
          } catch {
            toast.add({
              severity: 'warn',
              summary: `${sourceLabel} Failed`,
              detail: 'Trying Turing Repository...',
              life: 2000,
            })
          }
        } else {
          toast.add({
            severity: 'warn',
            summary: 'No Remote Config',
            detail: 'Trying Turing Repository...',
            life: 2000,
          })
        }
      }
    } else if (isUrl(exampleIdOrUrl)) {
      // Direct URL case
      toast.add({
        severity: 'info',
        summary: 'Loading...',
        detail: `Model is loading from External Link`,
        life: 2000,
      })
      const response = await fetch(exampleIdOrUrl)
      if (response.ok) {
        modelData = await response.json()
        modelName = modelData.name || 'Remote Model'
        sourceDescription = `External Link`
      }
    }

    if (!modelData && !isUrl(exampleIdOrUrl)) {
      const name = config ? config.name : exampleIdOrUrl

      if (!config) {
        toast.add({
          severity: 'info',
          summary: 'Loading...',
          detail: `Loading ${name} from Turing Repository...`,
          life: 2000,
        })
      }

      try {
        const response = await fetch(turingUrl)
        if (response.ok) {
          modelData = await response.json()
          modelName = modelData.name || name
          sourceDescription = `Turing Repository`
        } else {
          throw new Error('All fetch attempts failed')
        }
      } catch {
        throw new Error(`Failed to load model from any source (Local/GitHub/Turing).`)
      }
    }

    if (modelData) {
      await loadModelData(modelData, modelName)
      toast.add({
        severity: 'success',
        summary: 'Loaded',
        detail: `Model loaded from ${sourceDescription}`,
        life: 3000,
      })
    }
  } catch (error) {
    console.error('Failed to load example model:', error)
    toast.add({
      severity: 'error',
      summary: 'Load Failed',
      detail: 'Failed to load model. Check console for details.',
      life: 5000,
    })
  }
}

onMounted(async () => {
  projectStore.loadProjects()

  if (window.location.search.includes('share=')) {
    await handleLoadShared()
  }

  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project')
    // Load default model if provided in props
    if (props.defaultModel) {
      await handleLoadExample(props.defaultModel)
    } else if (projectStore.currentProjectId) {
      // Fallback default
      await handleLoadExample('rats')
    }
  } else {
    // If returning user, only load default if explicitly requested via prop and no session active
    // But usually we prefer restoring session.
    // If props.defaultModel is present, maybe we should prompt or force load?
    // For now, let's prioritize the session unless empty.
    if (!window.location.search.includes('share=')) {
      const lastGraphId = loadLastGraphId()
      if (lastGraphId && projectStore.currentProject?.graphs.some((g) => g.id === lastGraphId)) {
        graphStore.selectGraph(lastGraphId)
      } else if (projectStore.currentProject?.graphs.length) {
        graphStore.selectGraph(projectStore.currentProject.graphs[0].id)
      } else if (props.defaultModel) {
        await handleLoadExample(props.defaultModel)
      }
    }
  }
  validateGraph()

  if (window.innerWidth < 768) {
    showZoomControls.value = false
  }

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
          const panelW = 400
          const panelH = 300
          const viewportW = window.innerWidth
          const rightSidebarOffset = isRightSidebarOpen.value ? 340 : 20
          let targetScreenX = viewportW - rightSidebarOffset - panelW - 10
          if (targetScreenX < 20) targetScreenX = 20
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
          const panelW = 400
          const panelH = 300
          const leftSidebarOffset = isLeftSidebarOpen.value ? 320 : 20
          const targetScreenX = leftSidebarOffset + 20
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
  viewportState.value = v
  if (saveViewportTimeout) clearTimeout(saveViewportTimeout)
  saveViewportTimeout = setTimeout(persistViewport, 200)
}

const handleGraphLayout = (layoutName: string) => {
  const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
  if (!cy) return
  applyLayoutWithFit(cy, layoutName)
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
      graphStore.updateGraphElements(
        newGraphMeta.id,
        importedGraphData.value.elements as GraphElement[]
      )
      if (importedGraphData.value.dataContent) {
        dataStore.updateGraphData(newGraphMeta.id, { content: importedGraphData.value.dataContent })
      }
      graphStore.updateGraphLayout(newGraphMeta.id, 'preset')
    }

    showNewGraphModal.value = false
    newGraphName.value = ''
    clearImportedData()
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

watch(
  [generatedCode, parsedGraphData, samplerSettings],
  () => {
    if (standaloneScript.value || (activeRightTab.value === 'script' && isRightSidebarOpen.value)) {
      scriptStore.standaloneScript = getScriptContent()
    }
  },
  { deep: true }
)

const handleScriptSettingsDone = () => {
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
  if ((e.target as HTMLElement).closest('.db-theme-toggle-header')) return
  if (!isLeftSidebarOpen.value) {
    toggleLeftSidebar()
  }
}

watch(showNewGraphModal, (val) => {
  if (!val) {
    clearImportedData()
    newGraphName.value = ''
    if (graphImportInput.value) graphImportInput.value.value = ''
    isDragOver.value = false
  }
})

const updateActiveAccordionTabs = (val: string | string[]) => {
  const newVal = Array.isArray(val) ? val : [val]
  activeLeftAccordionTabs.value = newVal
}
</script>
<template>
  <div class="db-app-layout">
    <main class="db-canvas-area">
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
      <div v-else class="db-empty-state">
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
        class="db-collapsed-sidebar-trigger db-left-trigger"
        @click="handleSidebarContainerClick"
      >
        <div class="db-sidebar-trigger-content gap-1">
          <div
            class="flex-grow flex items-center gap-2 overflow-hidden"
            style="flex-grow: 1; overflow: hidden"
          >
            <span class="db-logo-text-minimized">
              <span class="db-desktop-text">{{
                pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS'
              }}</span>
              <span class="db-mobile-text">DoodleBUGS</span>
            </span>
          </div>
          <div class="flex items-center flex-shrink-0" style="flex-shrink: 0">
            <button
              @click.stop="uiStore.toggleDarkMode()"
              class="db-theme-toggle-header"
              :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'"
            >
              <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
            </button>
            <div class="db-toggle-icon-wrapper">
              <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="db-toggle-icon">
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
        class="db-collapsed-sidebar-trigger db-right"
        @click="toggleRightSidebar"
      >
        <div class="db-sidebar-trigger-content gap-2">
          <span class="db-sidebar-title-minimized">Inspector</span>
          <div class="flex items-center">
            <div
              class="db-status-indicator db-validation-status"
              @click.stop="showValidationModal = true"
              :class="isModelValid ? 'db-valid' : 'db-invalid'"
            >
              <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
              <div class="db-instant-tooltip">
                {{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}
              </div>
            </div>
            <button
              class="db-header-icon-btn db-collapsed-share-btn"
              @click.stop="handleShare"
              title="Share via URL"
            >
              <i class="fas fa-share-alt"></i>
            </button>
            <div class="db-toggle-icon-wrapper">
              <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="db-toggle-icon">
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
      <template #header>
        <h3>Create New Project</h3>
      </template>
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
      <template #header>
        <h3>Create New Graph</h3>
      </template>
      <template #body>
        <div class="flex flex-col gap-2">
          <div class="db-form-group">
            <label for="new-graph-name">Graph Name</label>
            <BaseInput
              id="new-graph-name"
              v-model="newGraphName"
              placeholder="Enter a name for your graph"
              @keyup.enter="createNewGraph"
            />
          </div>

          <div class="db-import-section">
            <label class="db-section-label">Import from JSON (Optional)</label>

            <div
              class="db-drop-zone"
              :class="{ 'db-loaded': importedGraphData, 'db-drag-over': isDragOver }"
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
                class="db-hidden-input"
              />

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
                <button
                  class="db-remove-file-btn"
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
      <template #footer>
        <BaseButton @click="createNewGraph" type="primary">Create Graph</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showScriptSettingsModal" @close="showScriptSettingsModal = false">
      <template #header>
        <h3>Script Configuration</h3>
      </template>
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
/* Scoped styles are preserved as per the previous version */
.db-app-layout {
  position: relative;
  width: 100vw;
  height: 100dvh;
  height: 100vh;
  overflow: hidden;
  background-color: var(--theme-bg-canvas);
}

.db-canvas-area {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  bottom: 0;
  z-index: 0;
  transition: bottom 0.1s ease;
}

.db-collapsed-sidebar-trigger {
  position: absolute;
  top: 16px;
  z-index: 100;
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

.db-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--theme-text-secondary);
  gap: 1rem;
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
  margin: 0;
}

.db-validation-status.db-valid {
  color: var(--theme-success);
}

.db-validation-status.db-invalid {
  color: var(--theme-warning);
}

.db-instant-tooltip {
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
  z-index: 600;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.db-status-indicator:hover .db-instant-tooltip {
  opacity: 1;
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

.db-divider {
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
