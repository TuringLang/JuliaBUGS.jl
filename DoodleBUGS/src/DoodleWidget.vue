<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, reactive, nextTick } from 'vue'
import { storeToRefs } from 'pinia'
import Toast from 'primevue/toast'
import { useToast } from 'primevue/usetoast'
import Tooltip from 'primevue/tooltip'

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
import { useGraphStore, type GraphContent } from './stores/graphStore'
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
import type { NodeType, GraphElement, UnifiedModelData } from './types'
import { examples, isUrl } from './config/examples'

const props = withDefaults(
  defineProps<{
    initialState?: string // Full JSON dump of project state (restores session)
    model?: string // GitHub URL, any URL, or Model ID (e.g. 'rats')
    localModel?: string // Path to local model file (e.g. 'model.json')
    storageKey?: string // Unique key for localStorage isolation (optional)
    width?: string
    height?: string
  }>(),
  {
    width: '100%',
    height: '600px',
  }
)

const emit = defineEmits<{
  (e: 'state-update', payload: string): void
  (e: 'code-update', payload: string): void
}>()

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()
const toast = useToast()

// Determine unique storage prefix for this instance
const persistencePrefix = computed(() => {
  if (props.storageKey) return `db-${props.storageKey}`
  const modelKey = props.model ? props.model.replace(/[^a-zA-Z0-9-_]/g, '') : null
  const localKey = props.localModel ? props.localModel.replace(/[^a-zA-Z0-9-_]/g, '') : null
  if (modelKey) return `db-model-${modelKey}`
  if (localKey) return `db-local-${localKey}`
  return 'doodlebugs-widget'
})

// Set up tooltip directive
const vTooltip = Tooltip

// Configure stores with isolated prefix
projectStore.setPrefix(persistencePrefix.value)
graphStore.setPrefix(persistencePrefix.value)
dataStore.setPrefix(persistencePrefix.value)
uiStore.setPrefix(persistencePrefix.value)

// Ensure sidebars are closed by default for the widget
uiStore.isLeftSidebarOpen = false
uiStore.isRightSidebarOpen = false

const widgetInitialized = ref(false)
const instanceId = ref(
  typeof crypto !== 'undefined' && crypto.randomUUID
    ? crypto.randomUUID()
    : `widget-${Math.random().toString(36).substring(2, 9)}`
)

// Widget Viewport & Edit Mode State
const widgetRoot = ref<HTMLElement | null>(null)
const isWidgetInView = ref(false)
// Edit mode is now strictly tied to full screen mode for simplicity
const isEditMode = ref(false)
const isFullScreen = ref(false)
const isUIActive = ref(true)
let observer: IntersectionObserver | null = null

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

const codePanelPos = reactive({ x: 0, y: 0 })
const codePanelSize = reactive({ width: 400, height: 300 })
const dataPanelPos = reactive({ x: 0, y: 0 })
const dataPanelSize = reactive({ width: 400, height: 300 })

const graphImportInput = ref<HTMLInputElement | null>(null)
const isDragOver = ref(false)
const isDraggingUI = ref(false)
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 1920)
const isInitialized = ref(false)

const WIDGET_UI_STATE_KEY = `${persistencePrefix.value}-ui-state`
const WIDGET_SOURCE_MAP_KEY = `${persistencePrefix.value}-source-map`

const {
  loadUIState,
  saveUIState,
  getStoredGraphElements,
  getStoredDataContent,
  saveLastGraphId,
  loadLastGraphId,
} = usePersistence(persistencePrefix.value)

const getSourceMap = (): Record<string, string> => {
  try {
    return JSON.parse(localStorage.getItem(WIDGET_SOURCE_MAP_KEY) || '{}')
  } catch {
    return {}
  }
}

const updateSourceMap = (source: string, graphId: string) => {
  const map = getSourceMap()
  map[source] = graphId
  localStorage.setItem(WIDGET_SOURCE_MAP_KEY, JSON.stringify(map))
}

const saveWidgetUIState = () => {
  saveUIState(WIDGET_UI_STATE_KEY, {
    leftSidebar: {
      open: uiStore.isLeftSidebarOpen,
      x: 0,
      y: 0,
    },
    rightSidebar: {
      open: uiStore.isRightSidebarOpen,
      x: 0,
      y: 0,
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
    editMode: isEditMode.value,
    // @ts-expect-error - Extending UI state for widget specific needs
    isFullScreen: isFullScreen.value,
  })
}

const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { parsedGraphData } = storeToRefs(dataStore)
const { samplerSettings, standaloneScript } = storeToRefs(scriptStore)
const { generatedCode } = useBugsCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
const { smartFit, applyLayoutWithFit } = useGraphLayout()
const { shareUrl, minifyGraph, generateShareLink } = useShareExport()
const { importedGraphData, processGraphFile, clearImportedData } = useImportExport()

const WIDGET_STYLES_ID = 'doodlebugs-widget-teleport-styles'

const widgetTeleportCSS = `
/* DoodleBUGS Widget - Teleported Content Styles */
.db-ui-overlay,
.db-sidebar-wrapper,
.db-floating-panel,
.p-dialog,
.p-popover,
.p-toast,
.p-select-overlay,
.p-tooltip {
  font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  font-size: 12px;
  line-height: 1.5;
  letter-spacing: normal;
  font-weight: 400;
  color: var(--theme-text-primary, #1f2937);
  box-sizing: border-box;
}

.db-ui-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  z-index: 1000000; /* Higher than widget root to ensure UI is on top */
  pointer-events: none;
}

.db-ui-overlay > * {
  pointer-events: auto;
}

.db-ui-overlay .db-toolbar-container {
  pointer-events: auto !important;
}

/* Fixed positioning wrapper for sidebars to match MainLayout */
.db-sidebar-wrapper {
  position: absolute;
  pointer-events: none; /* Let clicks pass through if sidebar is closed/scaled down */
  z-index: 1000001; /* Above UI overlay */
  display: block;
}

.db-sidebar-wrapper > * {
  pointer-events: auto; /* Re-enable for the sidebar content itself */
}

.db-sidebar-wrapper.db-left {
  left: 0;
  top: 0;
}

.db-sidebar-wrapper.db-right {
  right: 0;
  top: 0;
  left: auto;
}

.db-ui-overlay .db-floating-panel {
  z-index: 1000002 !important;
}

.db-ui-overlay .db-toolbar-container {
  z-index: 1000003 !important; /* Toolbar should be above panels */
}

.p-popover,
.p-select-overlay,
.p-dialog,
.p-toast,
.p-tooltip {
  z-index: 1000010 !important; /* Above all DoodleBUGS UI */
}

.p-dialog-mask {
  z-index: 1000009 !important;
}

/* Sidebar Animations */
.db-sidebar-transition-enter-active,
.db-sidebar-transition-leave-active {
  transition: transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1), opacity 0.3s ease;
}

.db-sidebar-transition-enter-from,
.db-sidebar-transition-leave-to {
  opacity: 0;
  transform: scale(0.95);
}

.db-sidebar-transition-enter-to,
.db-sidebar-transition-leave-from {
  opacity: 1;
  transform: scale(1);
}
`

const injectWidgetStyles = () => {
  if (document.getElementById(WIDGET_STYLES_ID)) return
  const styleElement = document.createElement('style')
  styleElement.id = WIDGET_STYLES_ID
  styleElement.textContent = widgetTeleportCSS
  document.head.appendChild(styleElement)
}

const removeWidgetStyles = () => {
  const otherWidgets = document.querySelectorAll('doodle-bugs')
  if (otherWidgets.length > 0) return

  const styleElement = document.getElementById(WIDGET_STYLES_ID)
  if (styleElement) {
    styleElement.remove()
  }
}

const pinnedGraphTitle = computed(() => {
  if (!projectStore.currentProject || !graphStore.currentGraphId) return null
  const graph = projectStore.currentProject.graphs.find((g) => g.id === graphStore.currentGraphId)
  return graph ? graph.name : null
})

const loadModelData = async (
  data: UnifiedModelData | Record<string, unknown>,
  name: string,
  sourceKey?: string
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

  if (sourceKey) {
    updateSourceMap(sourceKey, newGraphMeta.id)
  }
  graphStore.selectGraph(newGraphMeta.id)
  saveLastGraphId(newGraphMeta.id)

  return newGraphMeta.id
}

const resolveProp = (propName: string, propValue: string | undefined): string | null => {
  if (propValue) return propValue
  if (widgetRoot.value) {
    const root = widgetRoot.value.getRootNode()
    if (root instanceof ShadowRoot && root.host) {
      const kebab = propName.replace(/([a-z0-9]|(?=[A-Z]))([A-Z])/g, '$1-$2').toLowerCase()
      const lower = propName.toLowerCase()
      const attrVal = root.host.getAttribute(kebab) || root.host.getAttribute(lower)
      if (attrVal) return attrVal
    }
  }
  return null
}

const handleLoadExample = async (
  input: string,
  type: 'local' | 'prop',
  shouldPersistSource: boolean = true
) => {
  if (!projectStore.currentProjectId) return

  toast.add({
    severity: 'info',
    summary: 'Loading...',
    detail: `Attempting to load ${type === 'local' ? 'local file' : 'model'}: ${input}`,
    life: 2000,
  })

  try {
    let modelData = null
    let modelName = 'Imported Model'
    let sourceDescription = ''

    if (type === 'local') {
      sourceDescription = 'Local File'
      try {
        const response = await fetch(input)
        if (!response.ok) throw new Error(`Failed to load local file. Status: ${response.status}`)
        const text = await response.text()
        modelData = JSON.parse(text)
        modelName = modelData.name || input
      } catch (e: unknown) {
        throw new Error(e instanceof Error ? e.message : String(e))
      }
    } else {
      if (isUrl(input)) {
        const isGithub = input.toLowerCase().includes('github')
        sourceDescription = isGithub ? 'GitHub Source' : 'External URL'
        try {
          const response = await fetch(input)
          if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`)
          modelData = await response.json()
          modelName = modelData.name || 'Remote Model'
        } catch (e: unknown) {
          throw new Error(
            `Failed to fetch URL: "${input}". ${e instanceof Error ? e.message : String(e)}`
          )
        }
      } else {
        const turingUrl = `https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/examples/${input}/model.json`
        try {
          const response = await fetch(turingUrl)
          if (response.ok) {
            modelData = await response.json()
            modelName = modelData.name || input
            sourceDescription = 'Turing Repository'
          }
        } catch {
          console.warn('[DoodleBUGS] Turing fetch failed, checking fallback...')
        }

        if (!modelData) {
          const config = examples.find((e) => e.id === input)
          if (config && config.url) {
            sourceDescription = 'GitHub/Config Source'
            try {
              const response = await fetch(config.url)
              if (response.ok) {
                modelData = await response.json()
                modelName = config.name
              }
            } catch (remoteErr: unknown) {
              console.error('[DoodleBUGS] Fallback load failed:', remoteErr)
            }
          }
        }

        if (!modelData) {
          throw new Error(`Model ID "${input}" not found in Turing Repo or Config.`)
        }
      }
    }

    if (modelData) {
      await loadModelData(modelData, modelName, shouldPersistSource ? input : undefined)
      toast.add({
        severity: 'success',
        summary: 'Loaded',
        detail: `${modelName} loaded from ${sourceDescription}`,
        life: 3000,
      })
    }
  } catch (error: unknown) {
    console.error('[DoodleBUGS] CRITICAL LOAD ERROR:', error)
    toast.add({
      severity: 'error',
      summary: 'Load Failed',
      detail: error instanceof Error ? error.message : 'An unexpected error occurred.',
      life: 5000,
    })
  }
}

const handleLoadExampleAction = (exampleKey: string) => {
  handleLoadExample(exampleKey, 'prop', false)
}

const initGraph = async () => {
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project')
  }
  if (!projectStore.currentProjectId && projectStore.projects.length > 0) {
    projectStore.selectProject(projectStore.projects[0].id)
  }
  const proj = projectStore.currentProject
  if (!proj) return

  const rawLocalModel = resolveProp('localModel', props.localModel)
  const rawModel = resolveProp('model', props.model)
  const sourceKey = rawLocalModel || rawModel
  const isLocalFile = !!rawLocalModel

  if (sourceKey) {
    const map = getSourceMap()
    const mappedGraphId = map[sourceKey]
    const existingGraph = mappedGraphId
      ? proj.graphs.find((g) => g.id === mappedGraphId)
      : undefined

    if (existingGraph) {
      graphStore.selectGraph(existingGraph.id)
      saveLastGraphId(existingGraph.id)
    } else {
      await handleLoadExample(sourceKey, isLocalFile ? 'local' : 'prop', true)
    }
  } else {
    const lastGraphId = loadLastGraphId()
    if (lastGraphId && proj.graphs.some((g) => g.id === lastGraphId)) {
      graphStore.selectGraph(lastGraphId)
    } else {
      if (proj.graphs.length === 0) {
        projectStore.addGraphToProject(proj.id, 'Model 1')
      }
      if (!graphStore.currentGraphId && proj.graphs.length > 0) {
        graphStore.selectGraph(proj.graphs[0].id)
      }
    }
  }

  if (graphStore.currentGraphId && !graphStore.graphContents.has(graphStore.currentGraphId)) {
    graphStore.createNewGraphContent(graphStore.currentGraphId)
  }

  nextTick(() => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.resize()
    }
  })
}

interface WidgetInstanceCallbacks {
  setUIActive: (val: boolean) => void
  getRect: () => DOMRect | undefined | null
}

interface DoodleBugsManager {
  instances: Map<string, WidgetInstanceCallbacks>
  activeId: string | null
  register(id: string, callbacks: WidgetInstanceCallbacks): void
  unregister(id: string): void
  setActive(id: string | null): void
  recalculateActive(): void
}

const getManager = (): DoodleBugsManager => {
  const w = window as unknown as Window & { __DoodleBugsManager?: DoodleBugsManager }
  if (!w.__DoodleBugsManager) {
    w.__DoodleBugsManager = {
      instances: new Map(),
      activeId: null,
      register(id: string, callbacks: WidgetInstanceCallbacks) {
        this.instances.set(id, callbacks)
      },
      unregister(id: string) {
        this.instances.delete(id)
        if (this.activeId === id) {
          this.activeId = null
          this.recalculateActive()
        }
      },
      setActive(id: string | null) {
        if (this.activeId === id) return
        this.activeId = id
        this.instances.forEach((inst: WidgetInstanceCallbacks, key: string) => {
          inst.setUIActive(key === id)
        })
      },
      recalculateActive() {
        const visible: { id: string; top: number }[] = []
        this.instances.forEach((inst: WidgetInstanceCallbacks, id: string) => {
          const rect = inst.getRect()
          if (rect && rect.height > 0 && rect.bottom > 0 && rect.top < window.innerHeight) {
            visible.push({ id, top: rect.top })
          }
        })
        if (visible.length === 0) {
          this.setActive(null)
          return
        }
        visible.sort((a, b) => a.top - b.top)
        const currentIsVisible = visible.some((v) => v.id === this.activeId)
        if (!currentIsVisible) {
          this.setActive(visible[0].id)
        }
      },
    }
  }
  return w.__DoodleBugsManager
}

const activateWidget = (source: 'click' | 'scroll') => {
  const manager = getManager()
  if (source === 'click') {
    manager.setActive(instanceId.value)
  } else if (source === 'scroll') {
    manager.recalculateActive()
  }
}

const toggleFullScreen = () => {
  isFullScreen.value = !isFullScreen.value

  // Edit mode is strictly tied to full screen status
  isEditMode.value = isFullScreen.value

  if (isFullScreen.value) {
    activateWidget('click')
  }

  // Force graph resize and center after layout transition
  setTimeout(() => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) {
        cy.resize()
        // Center the graph after resize
        smartFit(cy, true)
      }
    }
  }, 100)

  saveWidgetUIState()
}

let scrollRafId: number | null = null
const handleWindowScroll = (event: Event) => {
  const target = event.target as Node
  const isDocumentScroll =
    target === document || target === document.documentElement || target === document.body

  if (isDocumentScroll) {
    if (!scrollRafId) {
      scrollRafId = requestAnimationFrame(() => {
        getManager().recalculateActive()
        if (graphStore.currentGraphId) {
          const cy = getCyInstance(graphStore.currentGraphId)
          if (cy) cy.resize()
        }
        scrollRafId = null
      })
    }
  }
}

const handleResize = () => {
  windowWidth.value = window.innerWidth
}

const handleWidgetClick = () => {
  activateWidget('click')
}

onMounted(async () => {
  const manager = getManager()
  manager.register(instanceId.value, {
    setUIActive: (val: boolean) => {
      isUIActive.value = val
    },
    getRect: () => (widgetRoot.value ? widgetRoot.value.getBoundingClientRect() : null),
  })

  if (widgetRoot.value) {
    observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0]
        isWidgetInView.value = entry.isIntersecting
        manager.recalculateActive()
      },
      { threshold: [0, 0.1] }
    )
    observer.observe(widgetRoot.value)
  }

  window.addEventListener('scroll', handleWindowScroll, { passive: true })
  graphStore.selectGraph(undefined as unknown as string)
  projectStore.loadProjects()

  if (props.initialState) {
    try {
      const state = JSON.parse(props.initialState)
      if (state.project) projectStore.importState(state.project)
      if (state.graphs)
        state.graphs.forEach((g: GraphContent) => graphStore.graphContents.set(g.graphId, g))
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
      uiStore.isLeftSidebarOpen = savedUIState.leftSidebar.open
    }
    if (savedUIState.rightSidebar) {
      uiStore.isRightSidebarOpen = savedUIState.rightSidebar.open
    }
    if (savedUIState.codePanel) {
      codePanelPos.x = savedUIState.codePanel.x
      codePanelPos.y = savedUIState.codePanel.y
      codePanelSize.width = savedUIState.codePanel.width
      codePanelSize.height = savedUIState.codePanel.height
    }
    if (savedUIState.dataPanel) {
      dataPanelPos.x = savedUIState.dataPanel.x
      dataPanelPos.y = savedUIState.dataPanel.y
      dataPanelSize.width = savedUIState.dataPanel.width
      dataPanelSize.height = savedUIState.dataPanel.height
    }
    if (savedUIState.currentGraphId) {
      graphStore.selectGraph(savedUIState.currentGraphId)
    }
    // Restore Fullscreen state if persisted
    // @ts-expect-error - isFullScreen is added to saved state for widget persistence
    if (savedUIState.isFullScreen) {
      isFullScreen.value = true
      isEditMode.value = true
      activateWidget('click')
    }
  }

  await initGraph()
  isInitialized.value = true
  widgetInitialized.value = true
  validateGraph()
  injectWidgetStyles()
  window.addEventListener('resize', handleResize)

  // Force fit to view on load (and reload)
  setTimeout(() => {
    handleFit()
  }, 800)
})

onUnmounted(() => {
  getManager().unregister(instanceId.value)
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('scroll', handleWindowScroll)
  if (observer) observer.disconnect()
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

watch(
  [generatedCode, parsedGraphData, samplerSettings],
  () => {
    if (
      standaloneScript.value ||
      (uiStore.activeRightTab === 'script' && uiStore.isRightSidebarOpen)
    ) {
      scriptStore.standaloneScript = getScriptContent()
    }
  },
  { deep: true }
)

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

const handleGenerateStandalone = () => {
  const script = getScriptContent()
  scriptStore.standaloneScript = script
  uiStore.setActiveRightTab('script')
  uiStore.isRightSidebarOpen = true
}

const handleDownloadBugs = () => {
  const content = generatedCode.value
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
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
  await generateShareLink(payload, 'https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/')
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
    if (isEditMode.value) {
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

const isModelValid = computed(() => validationErrors.value.size === 0)

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

watch(
  [
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
    isEditMode,
  ],
  () => {
    saveWidgetUIState()
  },
  { deep: true }
)

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

const handleSidebarContainerClick = (e: MouseEvent) => {
  if ((e.target as HTMLElement).closest('.db-theme-toggle-header')) return
  if (!uiStore.isLeftSidebarOpen) {
    uiStore.toggleLeftSidebar()
  }
}
</script>

<template>
  <div
    ref="widgetRoot"
    class="db-widget-root"
    :class="{ 'db-dark-mode': isDarkMode, 'db-fullscreen-mode': isFullScreen }"
    @mousedown.capture="handleWidgetClick"
    :style="
      isFullScreen
        ? {
            position: 'fixed',
            top: 0,
            left: 0,
            width: '100vw',
            height: '100vh',
            zIndex: 9990,
            margin: 0,
            borderRadius: 0,
          }
        : { width: props.width, height: props.height, position: 'relative', display: 'block' }
    "
  >
    <div class="db-content-clipper">
      <div
        class="db-canvas-layer"
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
          :read-only="!isEditMode"
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
        <div v-else class="db-empty-placeholder">
          <div class="db-msg-box">
            <i class="fas fa-spinner fa-spin"></i>
            <p>Initializing...</p>
          </div>
        </div>
      </div>

      <!-- Non-Fullscreen Controls (Embedded Mode - Reduced to just Maximize) -->
      <div
        v-if="!isFullScreen"
        style="
          position: absolute;
          top: 10px;
          right: 10px;
          z-index: 1000;
          display: flex;
          gap: 8px;
          pointer-events: auto;
        "
      >
        <button
          v-tooltip.top="{ value: 'Maximize Graph', showDelay: 0, hideDelay: 0 }"
          @click="toggleFullScreen"
          style="
            width: 40px;
            height: 40px;
            border-radius: 50%;
            background: var(--theme-bg-panel, white);
            border: 1px solid var(--theme-border, #e5e7eb);
            color: var(--theme-text-secondary, #4b5563);
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
            padding: 0;
            transition: all 0.2s;
          "
          @mouseenter="(e) => ((e.currentTarget as HTMLElement).style.transform = 'scale(1.05)')"
          @mouseleave="(e) => ((e.currentTarget as HTMLElement).style.transform = 'scale(1)')"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            style="width: 18px; height: 18px"
          >
            <path
              d="M18 20.75H12C11.8011 20.75 11.6103 20.671 11.4697 20.5303C11.329 20.3897 11.25 20.1989 11.25 20C11.25 19.8011 11.329 19.6103 11.4697 19.4697C11.6103 19.329 11.8011 19.25 12 19.25H18C18.3315 19.25 18.6495 19.1183 18.8839 18.8839C19.1183 18.6495 19.25 18.3315 19.25 18V6C19.25 5.66848 19.1183 5.35054 18.8839 5.11612C18.6495 4.8817 18.3315 4.75 18 4.75H6C5.66848 4.75 5.35054 4.8817 5.11612 5.11612C4.8817 5.35054 4.75 5.66848 4.75 6V12C4.75 12.1989 4.67098 12.3897 4.53033 12.5303C4.38968 12.671 4.19891 12.75 4 12.75C3.80109 12.75 3.61032 12.671 3.46967 12.5303C3.32902 12.3897 3.25 12.1989 3.25 12V6C3.25 5.27065 3.53973 4.57118 4.05546 4.05546C4.57118 3.53973 5.27065 3.25 6 3.25H18C18.7293 3.25 19.4288 3.53973 19.9445 4.05546C20.4603 4.57118 20.75 5.27065 20.75 6V18C20.75 18.7293 20.4603 19.4288 19.9445 19.9445C19.4288 20.4603 18.7293 20.75 18 20.75Z"
              fill="currentColor"
            />
            <path
              d="M16 12.75C15.8019 12.7474 15.6126 12.6676 15.4725 12.5275C15.3324 12.3874 15.2526 12.1981 15.25 12V8.75H12C11.8011 8.75 11.6103 8.67098 11.4697 8.53033C11.329 8.38968 11.25 8.19891 11.25 8C11.25 7.80109 11.329 7.61032 11.4697 7.46967C11.6103 7.32902 11.8011 7.25 12 7.25H16C16.1981 7.25259 16.3874 7.33244 16.5275 7.47253C16.6676 7.61263 16.7474 7.80189 16.75 8V12C16.7474 12.1981 16.6676 12.3874 16.5275 12.5275C16.3874 12.6676 16.1981 12.7474 16 12.75Z"
              fill="currentColor"
            />
            <path
              d="M11.5 13.25C11.3071 13.2352 11.1276 13.1455 11 13C10.877 12.8625 10.809 12.6845 10.809 12.5C10.809 12.3155 10.877 12.1375 11 12L15.5 7.5C15.6422 7.36752 15.8302 7.29539 16.0245 7.29882C16.2188 7.30225 16.4042 7.38096 16.5416 7.51838C16.679 7.65579 16.7578 7.84117 16.7612 8.03548C16.7646 8.22978 16.6925 8.41782 16.56 8.56L12 13C11.8724 13.1455 11.6929 13.2352 11.5 13.25Z"
              fill="currentColor"
            />
            <path
              d="M8 20.75H5C4.53668 20.7474 4.09309 20.5622 3.76546 20.2345C3.43784 19.9069 3.25263 19.4633 3.25 19V16C3.25263 15.5367 3.43784 15.0931 3.76546 14.7655C4.09309 14.4378 4.53668 14.2526 5 14.25H8C8.46332 14.2526 8.90691 14.4378 9.23454 14.7655C9.56216 15.0931 9.74738 15.5367 9.75 16V19C9.74738 19.4633 9.56216 19.9069 9.23454 20.2345C8.90691 20.5622 8.46332 20.7474 8 20.75ZM5 15.75C4.9337 15.75 4.87011 15.7763 4.82322 15.8232C4.77634 15.8701 4.75 15.9337 4.75 16V19C4.75 19.0663 4.77634 19.1299 4.82322 19.1768C4.87011 19.2237 4.9337 19.25 5 19.25H8C8.0663 19.25 8.12989 19.2237 8.17678 19.1768C8.22366 19.1299 8.25 19.0663 8.25 19V16C8.25 15.9337 8.22366 15.8701 8.17678 15.8232C8.12989 15.7763 8.0663 15.75 8 15.75H5Z"
              fill="currentColor"
            />
          </svg>
        </button>
      </div>
    </div>

    <!-- Floating Toolbar (Only in Full Screen) -->
    <Teleport to="body">
      <FloatingBottomToolbar
        ref="bottomToolbarRef"
        v-if="isWidgetInView && isFullScreen && isEditMode"
        :current-mode="currentMode"
        :current-node-type="currentNodeType"
        :show-zoom-controls="showZoomControls"
        :show-code-panel="isCodePanelOpen"
        :show-data-panel="isDataPanelOpen"
        :is-detach-mode-active="isDetachModeActive"
        :show-detach-mode-control="showDetachModeControl"
        :is-widget="false"
        :style="{ zIndex: 1000003 }"
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
    </Teleport>

    <Teleport to="body">
      <div class="db-toast-wrapper">
        <Toast position="top-center" />
      </div>

      <div
        class="db-ui-overlay"
        :class="{
          'db-dark-mode': isDarkMode,
          'db-widget-ready': widgetInitialized,
          'db-fullscreen': isFullScreen,
        }"
        v-show="isWidgetInView && isFullScreen && isEditMode && isUIActive"
      >
        <!-- Collapsed Sidebar Triggers (Only in Full Screen) -->
        <template v-if="isFullScreen">
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
                    v-tooltip.top="{
                      value: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                      showDelay: 0,
                      hideDelay: 0,
                    }"
                    @click.stop="uiStore.toggleDarkMode()"
                    class="db-theme-toggle-header"
                  >
                    <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
                  </button>
                  <div
                    v-tooltip.top="{ value: 'Expand Sidebar', showDelay: 0, hideDelay: 0 }"
                    class="db-toggle-icon-wrapper"
                  >
                    <svg
                      width="20"
                      height="20"
                      fill="none"
                      viewBox="0 0 24 24"
                      class="db-toggle-icon"
                    >
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

          <Transition name="fade">
            <div
              v-if="!isRightSidebarOpen"
              class="db-collapsed-sidebar-trigger db-right"
              @click="uiStore.toggleRightSidebar()"
            >
              <div class="db-sidebar-trigger-content gap-2">
                <span class="db-sidebar-title-minimized">Inspector</span>
                <div class="flex items-center">
                  <div
                    v-tooltip.top="{
                      value: isModelValid ? 'Model is valid' : 'Model has validation issues',
                      showDelay: 0,
                      hideDelay: 0,
                    }"
                    class="db-status-indicator db-validation-status"
                    @click.stop="showValidationModal = true"
                    :class="isModelValid ? 'db-valid' : 'db-invalid'"
                  >
                    <i
                      :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"
                    ></i>
                  </div>
                  <button
                    v-tooltip.top="{ value: 'Share via URL', showDelay: 0, hideDelay: 0 }"
                    class="db-header-icon-btn db-collapsed-share-btn"
                    @click.stop="handleShare"
                  >
                    <i class="fas fa-share-alt"></i>
                  </button>
                  <button
                    v-tooltip.top="{ value: 'Exit Full Screen', showDelay: 0, hideDelay: 0 }"
                    class="db-header-icon-btn db-exit-btn"
                    @click.stop="toggleFullScreen"
                  >
                    <i class="pi pi-window-minimize"></i>
                  </button>

                  <div
                    v-tooltip.top="{ value: 'Expand Sidebar', showDelay: 0, hideDelay: 0 }"
                    class="db-toggle-icon-wrapper"
                  >
                    <svg
                      width="20"
                      height="20"
                      fill="none"
                      viewBox="0 0 24 24"
                      class="db-toggle-icon"
                    >
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
        </template>

        <!-- Sidebars (Visible only in Full Screen) -->
        <Transition name="db-sidebar-transition">
          <div
            v-if="widgetInitialized && isLeftSidebarOpen && isFullScreen"
            class="db-sidebar-wrapper db-left"
          >
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
              :isCodePanelOpen="isCodePanelOpen"
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
              @update:show-detach-mode-control="showDetachModeControl = $event"
              @toggle-code-panel="toggleCodePanel"
              @load-example="handleLoadExampleAction"
              @open-about-modal="showAboutModal = true"
              @open-faq-modal="showFaqModal = true"
              @toggle-dark-mode="uiStore.toggleDarkMode"
              @share-graph="handleShareGraph"
              @share-project-url="handleShareProjectUrl"
            />
          </div>
        </Transition>

        <Transition name="db-sidebar-transition">
          <div
            v-if="widgetInitialized && isRightSidebarOpen && isFullScreen"
            class="db-sidebar-wrapper db-right"
          >
            <RightSidebar
              v-show="isRightSidebarOpen"
              :selectedElement="selectedElement"
              :validationErrors="validationErrors"
              :isModelValid="isModelValid"
              :showExitButton="true"
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
              @exit-fullscreen="toggleFullScreen"
            />
          </div>
        </Transition>

        <FloatingPanel
          v-if="isFullScreen"
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
          @drag-start="handleUIInteractionStart"
          @drag-end="
            (pos) => {
              codePanelPos.x = pos.x
              codePanelPos.y = pos.y
              handleUIInteractionEnd()
            }
          "
          @resize-start="handleUIInteractionStart"
          @resize-end="
            (size) => {
              codePanelSize.width = size.width
              codePanelSize.height = size.height
              handleUIInteractionEnd()
            }
          "
        >
          <CodePreviewPanel :is-active="isCodePanelOpen" />
        </FloatingPanel>

        <FloatingPanel
          v-if="isFullScreen"
          title="Data & Inits"
          icon="fas fa-database"
          badge="JSON"
          :is-open="isDataPanelOpen"
          :default-width="dataPanelSize.width"
          :default-height="dataPanelSize.height"
          :default-x="dataPanelPos.x || windowWidth - 420"
          :default-y="dataPanelPos.y"
          @close="toggleDataPanel"
          @drag-start="handleUIInteractionStart"
          @drag-end="
            (pos) => {
              dataPanelPos.x = pos.x
              dataPanelPos.y = pos.y
              handleUIInteractionEnd()
            }
          "
          @resize-start="handleUIInteractionStart"
          @resize-end="
            (size) => {
              dataPanelSize.width = size.width
              dataPanelSize.height = size.height
              handleUIInteractionEnd()
            }
          "
        >
          <DataInputPanel :is-active="isDataPanelOpen" />
        </FloatingPanel>

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

        <DebugPanel v-if="showDebugPanel" @close="showDebugPanel = false" />
      </div>
    </Teleport>
  </div>
</template>

<style>
.db-widget-root {
  overflow: visible !important;
  background: var(--theme-bg-canvas);
  isolation: isolate;
  z-index: 0;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  padding-top: 0;

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

/* Full Screen Mode */
.db-widget-root.db-fullscreen-mode {
  position: fixed !important;
  top: 0;
  left: 0;
  width: 100vw !important;
  height: 100vh !important;
  z-index: 999999; /* Canvas base Z-Index - very high to cover everything */
  margin: 0;
  border-radius: 0;
  background: var(--theme-bg-canvas) !important; /* Solid background to prevent bleed-through */
}

.db-widget-root.db-fullscreen-mode .db-content-clipper {
  border-radius: 0;
  border: none;
}

.db-content-clipper {
  flex: 1;
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  border-radius: 6px;
  z-index: 10;
  border: 1px solid var(--theme-border);
}

.db-widget-root.db-dark-mode .db-content-clipper {
  border-color: #3f3f46;
  border-color: var(--theme-danger);
  color: white;
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

.db-widget-root.db-dark-mode .db-cytoscape-container.db-grid-background.db-grid-dots {
  background-image: radial-gradient(
    circle,
    rgba(255, 255, 255, 0.2) 1.2px,
    transparent 1px
  ) !important;
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
  position: fixed; /* Use fixed positioning in fullscreen mode */
  top: 16px;
  z-index: 1000004; /* Above toolbar and panels */
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
  gap: 12px;
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

.db-exit-btn {
  margin-left: 4px;
  color: var(--theme-text-primary);
}

.db-exit-btn:hover {
  background-color: var(--theme-bg-active);
  color: var(--theme-primary);
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
    max-width: 48%;
    padding: 6px 8px;
  }
  .db-collapsed-sidebar-trigger.db-left-trigger {
    min-width: auto !important;
  }
  .db-collapsed-sidebar-trigger.db-right {
    max-width: 48%;
  }
  .db-logo-text-minimized {
    font-size: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: block;
  }
  .db-sidebar-title-minimized {
    font-size: 11px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .db-sidebar-trigger-content {
    gap: 2px;
    flex-wrap: wrap;
  }
  .db-header-icon-btn {
    font-size: 11px;
    padding: 3px;
  }
  .db-status-indicator {
    width: 20px;
    height: 20px;
  }
  .db-validation-status {
    font-size: 0.95em;
    margin: 0 2px;
  }
  .db-collapsed-share-btn {
    width: 20px;
    height: 20px;
  }
  .db-toggle-icon-wrapper {
    gap: 6px;
  }
  .db-toggle-icon-wrapper svg {
    width: 16px;
    height: 16px;
  }
}
</style>
