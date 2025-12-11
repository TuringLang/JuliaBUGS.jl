<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, reactive, nextTick, withDefaults } from 'vue'
import { storeToRefs } from 'pinia'
import Toast from 'primevue/toast'
import { useToast } from 'primevue/usetoast'

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
// Order of precedence: prop.storageKey > prop.model > prop.localModel > 'default-widget'
const persistencePrefix = computed(() => {
  if (props.storageKey) return `db-${props.storageKey}`

  // Sanitize model strings to be valid keys
  const modelKey = props.model ? props.model.replace(/[^a-zA-Z0-9-_]/g, '') : null
  const localKey = props.localModel ? props.localModel.replace(/[^a-zA-Z0-9-_]/g, '') : null

  if (modelKey) return `db-model-${modelKey}`
  if (localKey) return `db-local-${localKey}`

  return 'doodlebugs-widget'
})

// Configure stores with isolated prefix
projectStore.setPrefix(persistencePrefix.value)
graphStore.setPrefix(persistencePrefix.value)
dataStore.setPrefix(persistencePrefix.value)
uiStore.setPrefix(persistencePrefix.value)

// Ensure sidebars are closed by default for the widget
uiStore.isLeftSidebarOpen = false
uiStore.isRightSidebarOpen = false

// Widget-specific flag to prevent sidebar flash during initialization
const widgetInitialized = ref(false)

// Instance ID for coordination between multiple widgets
const instanceId = ref(
  typeof crypto !== 'undefined' && crypto.randomUUID
    ? crypto.randomUUID()
    : `widget-${Math.random().toString(36).substring(2, 9)}`
)

// Widget Viewport & Edit Mode State
const widgetRoot = ref<HTMLElement | null>(null)
const isWidgetInView = ref(false)
const isEditMode = ref(false)
const isUIActive = ref(false) // Tracks if this specific widget should show its floating UI
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

// Panel positions and sizes
const codePanelPos = reactive({ x: 0, y: 0 })
const codePanelSize = reactive({ width: 400, height: 300 })
const dataPanelPos = reactive({ x: 0, y: 0 })
const dataPanelSize = reactive({ width: 400, height: 300 })

// Import Graph State
const graphImportInput = ref<HTMLInputElement | null>(null)
const isDragOver = ref(false)

// UI Dragging State
const isDraggingUI = ref(false)

// Computed window width
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 1920)

// Flag to prevent premature canvas rendering
const isInitialized = ref(false)

// LocalStorage key for widget UI state
const WIDGET_UI_STATE_KEY = `${persistencePrefix.value}-ui-state`
const WIDGET_SOURCE_MAP_KEY = `${persistencePrefix.value}-source-map`

// Initialize persistence with scoped prefix
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
    // Persist edit mode
    editMode: isEditMode.value,
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

// CSS for teleported widget content
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
  z-index: 2000;
  pointer-events: none;
}

.db-ui-overlay > * {
  pointer-events: auto;
}

.db-ui-overlay .db-toolbar-container {
  pointer-events: auto !important;
}

.db-sidebar-wrapper {
  position: fixed;
  pointer-events: auto;
  z-index: 2100;
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  gap: 4px;
  left: 0;
  top: 0;
}

.db-sidebar-wrapper.db-right .db-floating-sidebar.db-right {
  position: relative !important;
  right: auto !important;
  left: auto !important;
  margin: 0 !important;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); 
}

.db-ui-overlay .db-floating-panel {
  z-index: 2200 !important;
}

.db-ui-overlay .db-toolbar-container {
  z-index: 2300 !important;
}

.p-popover,
.p-select-overlay,
.p-dialog,
.p-toast,
.p-tooltip {
  z-index: 3000 !important;
}

.p-dialog-mask {
  z-index: 2900 !important;
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
  // Only remove styles if there are no other DoodleBUGS widgets on the page
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

// Generic Loader for both bundled and remote models
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
      // Check both kebab-case (standard) and lowercase (often how browser parses simple attrs)
      const kebab = propName.replace(/([a-z0-9]|(?=[A-Z]))([A-Z])/g, '$1-$2').toLowerCase()
      const lower = propName.toLowerCase()

      const attrVal = root.host.getAttribute(kebab) || root.host.getAttribute(lower)
      if (attrVal) {
        return attrVal
      }
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
        if (!response.ok) {
          throw new Error(
            `Failed to load local file. Status: ${response.status} ${response.statusText}`
          )
        }

        const text = await response.text()
        try {
          modelData = JSON.parse(text)
        } catch (jsonErr: unknown) {
          console.error(
            '[DoodleBUGS] JSON Parse Error:',
            jsonErr,
            'Content Snippet:',
            text.substring(0, 100)
          )
          throw new Error(
            `File found but contained invalid JSON. Check if file path redirects to index.html.`
          )
        }

        modelName = modelData.name || input
      } catch (e: unknown) {
        console.error(`[DoodleBUGS] Local load failed:`, e)
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
              console.error(`[DoodleBUGS] Fallback load failed:`, remoteErr)
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

  // Re-run validation or initial sizing if needed
  nextTick(() => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.resize()
    }
  })
}

// --- GLOBAL WIDGET MANAGER ---
interface WidgetInstanceCallbacks {
  setUIActive: (val: boolean) => void
  setEditMode: (val: boolean) => void
  getRect: () => DOMRect | undefined | null
}

interface DoodleBugsManager {
  instances: Map<string, WidgetInstanceCallbacks>
  activeId: string | null
  globalEditMode: boolean
  register(id: string, callbacks: WidgetInstanceCallbacks): void
  unregister(id: string): void
  setActive(id: string | null): void
  setEditMode(mode: boolean): void
  recalculateActive(): void
}

// Using window to coordinate separate web component instances
const getManager = (): DoodleBugsManager => {
  const w = window as unknown as Window & { __DoodleBugsManager?: DoodleBugsManager }
  if (!w.__DoodleBugsManager) {
    w.__DoodleBugsManager = {
      instances: new Map(), // id -> { setUIActive: (bool)=>void, setEditMode: (bool)=>void, getRect: ()=>DOMRect }
      activeId: null,
      globalEditMode: false,

      register(id: string, callbacks: WidgetInstanceCallbacks) {
        this.instances.set(id, callbacks)
        // Sync new instance to global edit mode
        if (this.globalEditMode) {
          callbacks.setEditMode(true)
        }
      },

      unregister(id: string) {
        this.instances.delete(id)
        if (this.activeId === id) {
          this.activeId = null
          // Pick another active if available
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

      setEditMode(mode: boolean) {
        this.globalEditMode = mode
        this.instances.forEach((inst: WidgetInstanceCallbacks) => {
          inst.setEditMode(mode)
        })
        // If turning on edit mode, make sure *someone* is active if none is
        if (mode && !this.activeId) {
          this.recalculateActive()
        }
      },

      recalculateActive() {
        // Find visible instances
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

const toggleEditMode = () => {
  const manager = getManager()
  manager.setEditMode(!isEditMode.value)

  if (isEditMode.value) {
    activateWidget('click')
  }
  saveWidgetUIState()
}

const handleWindowScroll = (event: Event) => {
  const target = event.target as Node
  const isDocumentScroll =
    target === document || target === document.documentElement || target === document.body

  if (isDocumentScroll) {
    if (observer) {
    } else {
      getManager().recalculateActive()
    }

    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) {
        cy.resize()
      }
    }
  }
}

const handleResize = () => {
  windowWidth.value = window.innerWidth
  if (window.innerWidth - rightDrag.x.value < 500) {
    rightDrag.x.value = window.innerWidth - 320 - 4
  }
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
    setEditMode: (val: boolean) => {
      isEditMode.value = val
      if (!val) {
        uiStore.isLeftSidebarOpen = false
        uiStore.isRightSidebarOpen = false
      }
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
  let rightSidebarLoaded = false

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
      rightSidebarLoaded = true
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
    if (savedUIState.editMode !== undefined) {
      if (!manager.globalEditMode) {
        isEditMode.value = savedUIState.editMode
        manager.setEditMode(savedUIState.editMode)
      }
    }
  }

  nextTick(() => {
    const docWidth = document.documentElement.clientWidth || window.innerWidth
    const defaultRightX = docWidth - 320 - 20

    if (!rightSidebarLoaded || rightDrag.x.value <= 0 || docWidth - rightDrag.x.value > 450) {
      rightDrag.x.value = defaultRightX
    }
    if (!rightSidebarLoaded) {
      rightDrag.y.value = 10
    }
  })

  await initGraph()
  isInitialized.value = true
  widgetInitialized.value = true
  validateGraph()

  injectWidgetStyles()

  window.addEventListener('resize', handleResize)
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
      // FIX: Typed as GraphElement[]
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
    // FIX: Explicitly typed graphElements
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

  // Use the main app URL when sharing from the widget
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
    // Add Zoom Logic
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
    isDraggingUI.value = true
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
    isDraggingUI.value = false
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
      transform: `translate3d(${x.value}px, ${y.value}px, 0)`,
      left: '0px',
      top: '0px',
    })),
  }
}

// Left sidebar initialized higher (y=10)
const leftDrag = useDrag(20, 10)
// Right sidebar initialized (y=10 to match left)
const rightDrag = useDrag(typeof window !== 'undefined' ? window.innerWidth - 320 - 20 : 1580, 10)

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
    // Add isEditMode to persisted state
    isEditMode,
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

// Improved Animation hooks for sidebars

// Helper to get toolbar rect safely
const getToolbarRect = (contextEl: HTMLElement): DOMRect | null => {
  // 1. Try finding toolbar within the same overlay (most robust for multiple widgets)
  let toolbarEl = contextEl.closest('.db-ui-overlay')?.querySelector('.db-toolbar-container')

  // 2. Fallback to global document query if overlay context fails
  if (!toolbarEl) {
    toolbarEl = document.querySelector('.db-toolbar-container')
  }

  return toolbarEl ? toolbarEl.getBoundingClientRect() : null
}

const onSidebarLeave = (el: Element, done: () => void) => {
  const htmlEl = el as HTMLElement
  const isLeft = htmlEl.classList.contains('db-left')
  const tbRect = getToolbarRect(htmlEl)

  if (!tbRect) {
    const anim = htmlEl.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 200 })
    anim.onfinish = done
    return
  }

  const sbRect = htmlEl.getBoundingClientRect()

  // Calculate centers
  const sbCenterX = sbRect.left + sbRect.width / 2
  const sbCenterY = sbRect.top + sbRect.height / 2

  // Target: Left side of toolbar for Left Sidebar, Right side for Right Sidebar
  const targetX = isLeft
    ? tbRect.left + tbRect.width * 0.2 // Move to left 20% of toolbar
    : tbRect.right - tbRect.width * 0.2 // Move to right 20% of toolbar

  const targetY = tbRect.top + tbRect.height / 2

  const deltaX = targetX - sbCenterX
  const deltaY = targetY - sbCenterY

  const currentTransform = htmlEl.style.transform || ''

  const animation = htmlEl.animate(
    [
      { transform: `${currentTransform} translate(0px, 0px) scale(1)`, opacity: 1 },
      {
        transform: `${currentTransform} translate(${deltaX}px, ${deltaY}px) scale(0.1)`,
        opacity: 0,
      },
    ],
    {
      duration: 250,
      easing: 'ease-in', // Accelerate into the toolbar
    }
  )

  animation.onfinish = done
}

const onSidebarEnter = (el: Element, done: () => void) => {
  const htmlEl = el as HTMLElement
  const isLeft = htmlEl.classList.contains('db-left')
  const tbRect = getToolbarRect(htmlEl)

  if (!tbRect) {
    const anim = htmlEl.animate(
      [
        { opacity: 0, transform: 'scale(0.9)' },
        { opacity: 1, transform: 'scale(1)' },
      ],
      { duration: 200 }
    )
    anim.onfinish = done
    return
  }

  const sbRect = htmlEl.getBoundingClientRect()

  const sbCenterX = sbRect.left + sbRect.width / 2
  const sbCenterY = sbRect.top + sbRect.height / 2

  // Origin: Start from Left/Right side of toolbar
  const originX = isLeft ? tbRect.left + tbRect.width * 0.2 : tbRect.right - tbRect.width * 0.2

  const originY = tbRect.top + tbRect.height / 2

  // Delta to move FROM Origin TO Destination (sbRect)
  // We animate from the offset back to 0 (which is the natural position)
  const startDeltaX = originX - sbCenterX
  const startDeltaY = originY - sbCenterY

  const currentTransform = htmlEl.style.transform || ''

  const animation = htmlEl.animate(
    [
      {
        transform: `${currentTransform} translate(${startDeltaX}px, ${startDeltaY}px) scale(0.1)`,
        opacity: 0,
      },
      { transform: `${currentTransform} translate(0px, 0px) scale(1)`, opacity: 1 },
    ],
    {
      duration: 250,
      easing: 'ease-out', // Decelerate out of toolbar
    }
  )
  animation.onfinish = done
}
</script>

<template>
  <div
    ref="widgetRoot"
    class="db-widget-root"
    :class="{ 'db-dark-mode': isDarkMode }"
    @mousedown.capture="handleWidgetClick"
    :style="{ width: props.width, height: props.height, position: 'relative', display: 'block' }"
  >
    <!-- Removed .db-widget-frame wrapper entirely, just render content clipper directly -->
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

      <div
        class="db-edit-toggle-wrapper"
        style="position: absolute; top: 10px; right: 10px; z-index: 500"
      >
        <button
          @click="toggleEditMode"
          :title="isEditMode ? 'Stop Editing' : 'Edit Graph'"
          style="
            width: 40px;
            height: 40px;
            border-radius: 50%;
            background: white;
            border: 1px solid #e5e7eb;
            color: #4b5563;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
            padding: 0;
            transition: all 0.2s;
          "
          :style="isEditMode ? 'background: #ef4444; border-color: #ef4444; color: white;' : ''"
        >
          <svg
            v-if="!isEditMode"
            viewBox="0 0 24 24"
            width="18"
            height="18"
            xmlns="http://www.w3.org/2000/svg"
            fill="currentColor"
          >
            <path
              d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"
            />
          </svg>

          <svg
            v-else
            viewBox="0 0 76.00 76.00"
            xmlns="http://www.w3.org/2000/svg"
            width="22"
            height="22"
            fill="currentColor"
          >
            <path
              fill="currentColor"
              d="M 53.2929,21.2929L 54.7071,22.7071C 56.4645,24.4645 56.4645,27.3137 54.7071,29.0711L 52.2323,31.5459L 44.4541,23.7677L 46.9289,21.2929C 48.6863,19.5355 51.5355,19.5355 53.2929,21.2929 Z M 31.7262,52.052L 23.948,44.2738L 43.0399,25.182L 50.818,32.9601L 31.7262,52.052 Z M 23.2409,47.1023L 28.8977,52.7591L 21.0463,54.9537L 23.2409,47.1023 Z M 17,28L 17,23L 23,23L 23,17L 28,17L 28,23L 34,23L 34,28L 28,28L 28,34L 23,34L 23,28L 17,28 Z "
            ></path>
          </svg>
        </button>
      </div>
    </div>

    <Teleport to="body">
      <div class="db-toast-wrapper">
        <Toast position="top-center" />
      </div>

      <div
        class="db-ui-overlay"
        :class="{ 'db-dark-mode': isDarkMode, 'db-widget-ready': widgetInitialized }"
        v-show="isWidgetInView && isEditMode && isUIActive"
      >
        <Transition :css="false" @enter="onSidebarEnter" @leave="onSidebarLeave">
          <div
            v-if="widgetInitialized && isLeftSidebarOpen"
            class="db-sidebar-wrapper db-left"
            :style="leftDrag.style.value"
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
              @load-example="handleLoadExampleAction"
              @open-about-modal="showAboutModal = true"
              @open-faq-modal="showFaqModal = true"
              @toggle-dark-mode="uiStore.toggleDarkMode"
              @share-graph="handleShareGraph"
              @share-project-url="handleShareProjectUrl"
              @header-drag-start="onLeftHeaderDragStart"
            />
          </div>
        </Transition>

        <Transition :css="false" @enter="onSidebarEnter" @leave="onSidebarLeave">
          <div
            v-if="widgetInitialized && isRightSidebarOpen"
            class="db-sidebar-wrapper db-right"
            :style="rightDrag.style.value"
          >
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
        </Transition>

        <FloatingBottomToolbar
          ref="bottomToolbarRef"
          :current-mode="currentMode"
          :current-node-type="currentNodeType"
          :show-zoom-controls="showZoomControls"
          :show-code-panel="isCodePanelOpen"
          :show-data-panel="isDataPanelOpen"
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

        <FloatingPanel
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
  /* Dimensions controlled by Vue style binding from props */
  overflow: visible !important; /* Force overflow visible so content can hang outside */
  background: var(--theme-bg-canvas);
  /* Create stacking context for children */
  isolation: isolate;
  z-index: 0;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  padding-top: 0; /* Let inner wrapper handle spacing */

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

/* Content Clipper ensures rounded corners and overflow hidden for the canvas */
.db-content-clipper {
  flex: 1; /* Flex grow to fill remaining vertical space */
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  border-radius: 6px;
  z-index: 10;
  /* Removed border from here as we removed frame */
  border: 1px solid var(--theme-border);
}

.db-widget-root.db-dark-mode .db-content-clipper {
  border-color: #3f3f46;
}

/* Edit Toggle Button Styles */
.db-edit-toggle-wrapper {
  position: absolute;
  top: 10px;
  right: 10px;
  z-index: 500;
}

.db-edit-toggle-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  color: var(--theme-text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--shadow-md);
  transition: all 0.2s cubic-bezier(0.25, 0.8, 0.25, 1);
  padding: 0;
}

.db-edit-toggle-btn:hover {
  background: var(--theme-bg-hover);
  color: var(--theme-primary);
  transform: scale(1.05);
}

.db-edit-toggle-btn.db-active {
  background: var(--theme-danger);
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

/* Dark mode grid styling for widget */
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
