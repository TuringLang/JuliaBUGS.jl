<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed, nextTick } from 'vue'
import { storeToRefs } from 'pinia'
import Toast from 'primevue/toast'
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
import { useBugsCodeGenerator } from './composables/useBugsCodeGenerator'
import { useGraphValidator } from './composables/useGraphValidator'
import { usePersistence } from './composables/usePersistence'
import { useEditorActions } from './composables/useEditorActions'
import { useWidgetEmitter } from './composables/useWidgetEmitter'
import { examples } from './config/examples'

const props = withDefaults(
  defineProps<{
    initialState?: string
    model?: string
    localModel?: string
    storageKey?: string
    width?: string
    height?: string
    themeMode?: string
    controlsPosition?: string
    controlsMarginTop?: string
    controlsMarginRight?: string
    controlsMarginBottom?: string
    controlsMarginLeft?: string
    sidebarInsetRight?: string
  }>(),
  {
    width: '100%',
    height: '600px',
    controlsPosition: 'bottom-right',
    sidebarInsetRight: '0',
  }
)

const emit = defineEmits<{
  (e: 'state-update', payload: string): void
  (e: 'code-update', payload: string): void
  (e: 'ready', payload: string): void
  (e: 'models-available', payload: string): void
}>()

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()

const persistencePrefix = computed(() => {
  if (props.storageKey) return `db-${props.storageKey}`
  const modelKey = props.model ? props.model.replace(/[^a-zA-Z0-9-_]/g, '') : null
  const localKey = props.localModel ? props.localModel.replace(/[^a-zA-Z0-9-_]/g, '') : null
  if (modelKey) return `db-model-${modelKey}`
  if (localKey) return `db-local-${localKey}`
  return 'doodlebugs-widget'
})

const vTooltip = Tooltip

projectStore.setPrefix(persistencePrefix.value)
graphStore.setPrefix(persistencePrefix.value)
dataStore.setPrefix(persistencePrefix.value)
uiStore.setPrefix(persistencePrefix.value)
scriptStore.setPrefix(persistencePrefix.value)

// Always true in widget context — used for template consistency with MainLayout's conditional rendering
const showEditorUI = computed(() => true)
const shouldTeleport = computed(() => true)

watch(
  () => props.themeMode,
  (mode) => {
    if (mode != null) {
      uiStore.isDarkMode = mode === 'dark'
    }
  },
  { immediate: true }
)

watch(
  () => props.model,
  (newModel, oldModel) => {
    if (newModel && newModel !== oldModel && widgetInitialized.value) {
      handleLoadExample(newModel, 'standard', sourceMapApi)
    }
  }
)

const widgetInitialized = ref(false)
const instanceId = ref(
  typeof crypto !== 'undefined' && crypto.randomUUID
    ? crypto.randomUUID()
    : `widget-${Math.random().toString(36).substring(2, 9)}`
)

const widgetRoot = ref<HTMLElement | null>(null)
const bottomToolbarRef = ref<InstanceType<typeof FloatingBottomToolbar> | null>(null)
const isWidgetInView = ref(false)
const isEditMode = ref(false)
const isFullScreen = ref(false)

const isUIActive = ref(true)
let observer: IntersectionObserver | null = null

const widgetRect = ref({ top: 0, left: 0, right: 0, width: 0, height: 0, bottom: 0 })
let resizeObserver: ResizeObserver | null = null

const updateWidgetRect = () => {
  if (!widgetRoot.value) return
  const r = widgetRoot.value.getBoundingClientRect()
  widgetRect.value = {
    top: r.top,
    left: r.left,
    right: r.right,
    width: r.width,
    height: r.height,
    bottom: r.bottom,
  }
}

const rightInset = computed(() => parseInt(props.sidebarInsetRight || '0', 10) || 0)

const inlineLeftTriggerStyle = computed(() => {
  if (isFullScreen.value) return {}
  const r = widgetRect.value
  return {
    position: 'fixed' as const,
    top: `${r.top + 10}px`,
    left: `${r.left + 10}px`,
    right: 'auto',
    minWidth: '140px',
    maxWidth: `${Math.max(r.width / 2 - 60, 120)}px`,
  }
})

const inlineRightTriggerStyle = computed(() => {
  if (isFullScreen.value) return {}
  const r = widgetRect.value
  return {
    position: 'fixed' as const,
    top: `${r.top + 10}px`,
    right: `${window.innerWidth - r.right + 10 + rightInset.value}px`,
    left: 'auto',
    maxWidth: `${Math.max(r.width / 2 - 60, 120)}px`,
  }
})

const isInlineEditor = computed(() => !isFullScreen.value)

const leftSidebarDrag = ref({ x: 0, y: 0 })
const rightSidebarDrag = ref({ x: 0, y: 0 })
let activeDragSidebar: 'left' | 'right' | null = null
let dragStartX = 0
let dragStartY = 0
let dragAnimFrame: number | null = null

const sidebarDragStyle = (side: 'left' | 'right') => {
  if (!isInlineEditor.value) return {}
  const pos = side === 'left' ? leftSidebarDrag.value : rightSidebarDrag.value
  if (pos.x === 0 && pos.y === 0) return {}
  return { transform: `translate3d(${pos.x}px, ${pos.y}px, 0)` }
}

const sidebarWrapperStyle = (side: 'left' | 'right') => {
  if (isFullScreen.value) return {}
  const r = widgetRect.value
  const style: Record<string, string> = {
    position: 'fixed',
    top: `${r.top}px`,
    height: `${r.height}px`,
    '--db-container-height': `${r.height}px`,
  }
  if (side === 'left') {
    style.left = `${r.left}px`
    style.right = 'auto'
  } else {
    style.right = `${window.innerWidth - r.right + rightInset.value}px`
    style.left = 'auto'
  }
  return style
}

const handleSidebarDragStart = (side: 'left' | 'right', e: MouseEvent | TouchEvent) => {
  activeDragSidebar = side
  const clientX = 'touches' in e ? e.touches[0].clientX : (e as MouseEvent).clientX
  const clientY = 'touches' in e ? e.touches[0].clientY : (e as MouseEvent).clientY
  const pos = side === 'left' ? leftSidebarDrag.value : rightSidebarDrag.value
  dragStartX = clientX - pos.x
  dragStartY = clientY - pos.y
  document.body.style.userSelect = 'none'
  document.body.style.webkitUserSelect = 'none'
  document.addEventListener('mousemove', handleSidebarDragMove)
  document.addEventListener('mouseup', handleSidebarDragEnd)
  document.addEventListener('touchmove', handleSidebarDragMoveTouch, { passive: false })
  document.addEventListener('touchend', handleSidebarDragEnd)
}

const handleSidebarDragMove = (e: MouseEvent) => {
  if (!activeDragSidebar) return
  if (dragAnimFrame) return
  dragAnimFrame = requestAnimationFrame(() => {
    dragAnimFrame = null
    if (!activeDragSidebar) return
    const pos = activeDragSidebar === 'left' ? leftSidebarDrag : rightSidebarDrag
    pos.value = { x: e.clientX - dragStartX, y: e.clientY - dragStartY }
  })
}

const handleSidebarDragMoveTouch = (e: TouchEvent) => {
  if (!activeDragSidebar) return
  e.preventDefault()
  if (dragAnimFrame) return
  dragAnimFrame = requestAnimationFrame(() => {
    dragAnimFrame = null
    if (!activeDragSidebar) return
    const t = e.touches[0]
    const pos = activeDragSidebar === 'left' ? leftSidebarDrag : rightSidebarDrag
    pos.value = { x: t.clientX - dragStartX, y: t.clientY - dragStartY }
  })
}

const handleSidebarDragEnd = () => {
  activeDragSidebar = null
  if (dragAnimFrame) {
    cancelAnimationFrame(dragAnimFrame)
    dragAnimFrame = null
  }
  document.body.style.userSelect = ''
  document.body.style.webkitUserSelect = ''
  document.removeEventListener('mousemove', handleSidebarDragMove)
  document.removeEventListener('mouseup', handleSidebarDragEnd)
  document.removeEventListener('touchmove', handleSidebarDragMoveTouch)
  document.removeEventListener('touchend', handleSidebarDragEnd)
}

const controlsStyle = computed(() => {
  const pos = props.controlsPosition || 'bottom-right'
  const style: Record<string, string> = {
    position: 'absolute',
    zIndex: '1000',
    display: 'flex',
    gap: '8px',
    pointerEvents: 'auto',
  }
  const [vertical, horizontal] = pos.split('-')
  if (vertical === 'top') style.top = props.controlsMarginTop || '10px'
  else style.bottom = props.controlsMarginBottom || '10px'
  if (horizontal === 'left') style.left = props.controlsMarginLeft || '10px'
  else style.right = props.controlsMarginRight || '10px'
  return style
})

const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { parsedGraphData } = storeToRefs(dataStore)
const { generatedCode } = useBugsCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { standaloneScript, samplerSettings } = storeToRefs(scriptStore)

const { loadUIState, saveUIState, saveLastGraphId, loadLastGraphId } = usePersistence(
  persistencePrefix.value
)

const actions = useEditorActions(elements, generatedCode, persistencePrefix.value)
const {
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
  smartFit,
} = actions

const { emitReady } = useWidgetEmitter(emit, generatedCode)

const WIDGET_UI_STATE_KEY = `${persistencePrefix.value}-ui-state`
const WIDGET_SOURCE_MAP_KEY = `${persistencePrefix.value}-source-map`
const isDraggingUI = ref(false)
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 1920)
const isInitialized = ref(false)

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
const sourceMapApi = { get: getSourceMap, set: updateSourceMap }

const saveWidgetUIState = () => {
  saveUIState(WIDGET_UI_STATE_KEY, {
    leftSidebar: { open: uiStore.isLeftSidebarOpen, x: 0, y: 0 },
    rightSidebar: { open: uiStore.isRightSidebarOpen, x: 0, y: 0 },
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
    isFullScreen: isFullScreen.value,
  })
}

const WIDGET_STYLES_ID = 'doodlebugs-widget-teleport-styles'

const widgetTeleportCSS = `
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
  position: fixed; top: 0; left: 0; width: 100%; height: 100%;
  z-index: 1000000; pointer-events: none;
}
.db-ui-overlay > * { pointer-events: auto; }
.db-ui-overlay .db-toolbar-container { pointer-events: auto !important; }
.db-sidebar-wrapper {
  position: absolute; pointer-events: none; z-index: 1000001; display: block;
}
.db-sidebar-wrapper > * { pointer-events: auto; }
.db-sidebar-wrapper.db-left { left: 0; top: 0; }
.db-sidebar-wrapper.db-right { right: 0; top: 0; left: auto; }
.db-ui-overlay .db-floating-panel { z-index: 1000002 !important; }
.db-ui-overlay .db-toolbar-container { z-index: 1000003 !important; }
.p-popover, .p-select-overlay, .p-dialog, .p-toast, .p-tooltip { z-index: 1000010 !important; }
.p-dialog-mask { z-index: 1000009 !important; }
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
  document.getElementById(WIDGET_STYLES_ID)?.remove()
}

const resolveProp = (propName: string, propValue: string | undefined): string | null => {
  if (propValue) return propValue
  if (widgetRoot.value) {
    const root = widgetRoot.value.getRootNode()
    if (root instanceof ShadowRoot && root.host) {
      const kebab = propName.replace(/([a-z0-9]|(?=[A-Z]))([A-Z])/g, '$1-$2').toLowerCase()
      const lower = propName.toLowerCase()
      return root.host.getAttribute(kebab) || root.host.getAttribute(lower) || null
    }
  }
  return null
}

const handleLoadExampleAction = (exampleKey: string) => {
  handleLoadExample(exampleKey, 'standard', sourceMapApi)
}

const handleNewProject = () => {
  newProjectName.value = `Project ${projectStore.projects.length + 1}`
  showNewProjectModal.value = true
}

const handleNewGraph = () => {
  if (projectStore.currentProjectId && projectStore.currentProject) {
    newGraphName.value = `Graph ${projectStore.currentProject.graphs.length + 1}`
    showNewGraphModal.value = true
  }
}

const DOODLEBUGS_BASE_URL = 'https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/'

const handleShareGraph = () => {
  shareUrl.value = ''
  showShareModal.value = true
}

const handleShareProjectUrl = () => {
  shareUrl.value = ''
  showShareModal.value = true
}

const handleWidgetGenerateShareLink = (options: {
  scope: 'current' | 'project' | 'custom'
  selectedGraphIds?: string[]
}) => {
  handleGenerateShareLink(options, DOODLEBUGS_BASE_URL)
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
      try {
        await handleLoadExample(sourceKey, isLocalFile ? 'local' : 'standard', sourceMapApi)
      } catch (error) {
        console.warn('[DoodleBUGS] Failed to load model, creating empty graph:', error)
        if (proj.graphs.length === 0) projectStore.addGraphToProject(proj.id, 'Model 1')
        if (!graphStore.currentGraphId && proj.graphs.length > 0)
          graphStore.selectGraph(proj.graphs[0].id)
      }
    }
  } else {
    const lastGraphId = loadLastGraphId()
    if (lastGraphId && proj.graphs.some((g) => g.id === lastGraphId)) {
      graphStore.selectGraph(lastGraphId)
    } else {
      if (proj.graphs.length === 0) projectStore.addGraphToProject(proj.id, 'Model 1')
      if (!graphStore.currentGraphId && proj.graphs.length > 0)
        graphStore.selectGraph(proj.graphs[0].id)
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
      register(id, callbacks) {
        this.instances.set(id, callbacks)
      },
      unregister(id) {
        this.instances.delete(id)
        if (this.activeId === id) {
          this.activeId = null
          this.recalculateActive()
        }
      },
      setActive(id) {
        if (this.activeId === id) return
        this.activeId = id
        this.instances.forEach((inst, key) => {
          inst.setUIActive(key === id)
        })
      },
      recalculateActive() {
        const visible: { id: string; top: number }[] = []
        this.instances.forEach((inst, id) => {
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
        if (!visible.some((v) => v.id === this.activeId)) this.setActive(visible[0].id)
      },
    }
  }
  return w.__DoodleBugsManager
}

const activateWidget = (source: 'click' | 'scroll') => {
  const manager = getManager()
  if (source === 'click') manager.setActive(instanceId.value)
  else manager.recalculateActive()
}

const toggleEditMode = () => {
  isEditMode.value = !isEditMode.value
  if (isEditMode.value) activateWidget('click')
  saveWidgetUIState()
}

let editModeBeforeFullScreen = false
const toggleFullScreen = () => {
  if (!isFullScreen.value) {
    editModeBeforeFullScreen = isEditMode.value
    isEditMode.value = true
  } else {
    isEditMode.value = editModeBeforeFullScreen
  }
  isFullScreen.value = !isFullScreen.value
  if (isFullScreen.value) activateWidget('click')
  setTimeout(() => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) {
        cy.resize()
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
  if (isDocumentScroll && !scrollRafId) {
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

const handleResize = () => {
  windowWidth.value = window.innerWidth
}
const handleWidgetClick = () => {
  activateWidget('click')
}

onMounted(async () => {
  const manager = getManager()
  manager.register(instanceId.value, {
    setUIActive: (val) => {
      isUIActive.value = val
    },
    getRect: () => widgetRoot.value?.getBoundingClientRect() ?? null,
  })

  if (widgetRoot.value) {
    observer = new IntersectionObserver(
      (entries) => {
        isWidgetInView.value = entries[0].isIntersecting
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
    if (savedUIState.leftSidebar) uiStore.isLeftSidebarOpen = savedUIState.leftSidebar.open
    if (savedUIState.rightSidebar) uiStore.isRightSidebarOpen = savedUIState.rightSidebar.open
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
    if (savedUIState.currentGraphId) graphStore.selectGraph(savedUIState.currentGraphId)
    if (savedUIState.isFullScreen) {
      isFullScreen.value = true
      isEditMode.value = true
      activateWidget('click')
    }
  }

  if (savedUIState?.editMode != null) {
    isEditMode.value = savedUIState.editMode
  }
  if (isEditMode.value) activateWidget('click')

  await initGraph()
  isInitialized.value = true
  widgetInitialized.value = true
  validateGraph()
  injectWidgetStyles()
  window.addEventListener('resize', handleResize)

  if (widgetRoot.value) {
    resizeObserver = new ResizeObserver(updateWidgetRect)
    resizeObserver.observe(widgetRoot.value)
    updateWidgetRect()
  }
  window.addEventListener('scroll', updateWidgetRect, { capture: true, passive: true })
  window.addEventListener('resize', updateWidgetRect, { passive: true })

  emitReady()
  emit('models-available', JSON.stringify(examples.map((e) => ({ id: e.id, name: e.name }))))

  setTimeout(() => handleFit(), 800)
})

onUnmounted(() => {
  getManager().unregister(instanceId.value)
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('scroll', handleWindowScroll)
  if (observer) observer.disconnect()
  if (resizeObserver) resizeObserver.disconnect()
  window.removeEventListener('scroll', updateWidgetRect, { capture: true } as EventListenerOptions)
  window.removeEventListener('resize', updateWidgetRect)
  document.body.classList.remove('db-dark-mode')
  document.documentElement.classList.remove('db-dark-mode')
  removeWidgetStyles()
})

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

const isModelValid = computed(() => validationErrors.value.size === 0)

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
  if (!uiStore.isLeftSidebarOpen) uiStore.toggleLeftSidebar()
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
    </div>

    <!-- Non-Fullscreen Controls -->
    <div v-if="!isFullScreen" :style="controlsStyle">
      <button
        v-tooltip.top="{
          value: isEditMode ? 'Disable Editing' : 'Enable Editing',
          showDelay: 0,
          hideDelay: 0,
        }"
        @click="toggleEditMode"
        class="db-widget-control-btn"
        :class="{ 'db-active': isEditMode }"
      >
        <i :class="isEditMode ? 'fas fa-eye' : 'fas fa-pen'"></i>
      </button>
    </div>

    <!-- Floating Toolbar -->
    <Teleport to="body" :disabled="!shouldTeleport">
      <FloatingBottomToolbar
        ref="bottomToolbarRef"
        v-if="isWidgetInView && showEditorUI && isEditMode"
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

    <Teleport to="body" :disabled="!shouldTeleport">
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
        v-show="isWidgetInView && showEditorUI && isEditMode && isUIActive"
      >
        <!-- Collapsed Sidebar Triggers -->
        <template v-if="showEditorUI">
          <Transition name="fade">
            <div
              v-if="!isLeftSidebarOpen"
              class="db-collapsed-sidebar-trigger db-left-trigger"
              :style="inlineLeftTriggerStyle"
              @click="handleSidebarContainerClick"
            >
              <div class="db-sidebar-trigger-content gap-1">
                <div
                  class="grow flex items-center gap-2 overflow-hidden"
                  style="flex-grow: 1; overflow: hidden"
                >
                  <span class="db-logo-text-minimized">
                    <span class="db-desktop-text">{{
                      pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS'
                    }}</span>
                    <span class="db-mobile-text">DoodleBUGS</span>
                  </span>
                </div>
                <div class="flex items-center shrink-0" style="flex-shrink: 0">
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
              :style="inlineRightTriggerStyle"
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
                    v-tooltip.top="{
                      value: isFullScreen ? 'Exit Full Screen' : 'Maximize Graph',
                      showDelay: 0,
                      hideDelay: 0,
                    }"
                    class="db-header-icon-btn"
                    :class="{ 'db-exit-btn': isFullScreen }"
                    @click.stop="toggleFullScreen"
                  >
                    <svg
                      v-if="!isFullScreen"
                      viewBox="0 0 24 24"
                      fill="none"
                      xmlns="http://www.w3.org/2000/svg"
                      style="width: 14px; height: 14px"
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
                    <i v-else class="pi pi-window-minimize"></i>
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

        <!-- Sidebars -->
        <div
          v-if="widgetInitialized && showEditorUI"
          class="db-sidebar-wrapper db-left"
          :style="[sidebarWrapperStyle('left'), sidebarDragStyle('left')]"
        >
          <LeftSidebar
            :enableDrag="isInlineEditor"
            @header-drag-start="handleSidebarDragStart('left', $event)"
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

        <div
          v-if="widgetInitialized && showEditorUI"
          class="db-sidebar-wrapper db-right"
          :style="[sidebarWrapperStyle('right'), sidebarDragStyle('right')]"
        >
          <RightSidebar
            :enableDrag="isInlineEditor"
            @header-drag-start="handleSidebarDragStart('right', $event)"
            :selectedElement="selectedElement"
            :validationErrors="validationErrors"
            :isModelValid="isModelValid"
            :isFullScreen="isFullScreen"
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
            @toggle-fullscreen="toggleFullScreen"
          />
        </div>

        <FloatingPanel
          v-if="showEditorUI"
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
          <CodePreviewPanel :is-active="isCodePanelOpen" :code="generatedCode" />
        </FloatingPanel>

        <FloatingPanel
          v-if="showEditorUI"
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
          @generate="handleWidgetGenerateShareLink"
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

.db-widget-root.db-fullscreen-mode {
  position: fixed !important;
  top: 0;
  left: 0;
  width: 100vw !important;
  height: 100vh !important;
  z-index: 999999;
  margin: 0;
  border-radius: 0;
  background: var(--theme-bg-canvas) !important;
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
  box-sizing: border-box;
}

.db-widget-root.db-dark-mode .db-content-clipper {
  border-color: #3f3f46;
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

/* Widget overrides: sidebar triggers use fixed positioning in fullscreen */
.db-widget-root .db-collapsed-sidebar-trigger {
  position: fixed;
  z-index: 1000004;
}

.db-widget-control-btn {
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
  font-size: 16px;
}

.db-widget-control-btn:hover {
  transform: scale(1.05);
  box-shadow: 0 6px 12px -2px rgba(0, 0, 0, 0.15);
}

.db-widget-control-btn.db-active {
  background: var(--theme-primary, #10b981);
  color: white;
  border-color: var(--theme-primary, #10b981);
}
</style>
