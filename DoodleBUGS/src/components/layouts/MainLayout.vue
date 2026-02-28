<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import { storeToRefs } from 'pinia'
import Tooltip from 'primevue/tooltip'

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
import { useGraphValidator } from '../../composables/useGraphValidator'
import { usePersistence } from '../../composables/usePersistence'
import { useBugsCodeGenerator } from '../../composables/useBugsCodeGenerator'
import { useShareExport } from '../../composables/useShareExport'
import { useEditorActions } from '../../composables/useEditorActions'
import { useStanCodeGenerator } from '../../composables/useStanCodeGenerator'
import type { GraphElement } from '../../types'
import type { CodeLanguage } from '../panels/CodePreviewPanel.vue'

const props = defineProps<{
  defaultModel?: string
}>()

const projectStore = useProjectStore()
const graphStore = useGraphStore()
const uiStore = useUiStore()
const dataStore = useDataStore()
const scriptStore = useScriptStore()
const vTooltip = Tooltip

const { parsedGraphData } = storeToRefs(dataStore)
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements()
const { generatedCode } = useBugsCodeGenerator(elements)
const { generatedStanCode } = useStanCodeGenerator(elements)
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData)
const { samplerSettings, standaloneScript } = storeToRefs(scriptStore)
const { loadLastGraphId } = usePersistence()
const { decodeAndDecompress, expandGraph } = useShareExport()

const actions = useEditorActions(elements, generatedCode, undefined, generatedStanCode)
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
  handleLoadExample: baseLoadExample,
  getScriptContent,
  handleGenerateStandalone,
  handleDownloadBugs,
  handleDownloadStan,
  handleDownloadScript,
  handleDownloadStanScript,
  handleDownloadStanData,
  handleDownloadStanInits,
  openExportModal,
  handleConfirmExport,
  handleExportJson,
  handleSelectNodeFromModal,
  handleShare,
  handleGenerateShareLink,
  createNewProject: baseCreateNewProject,
  createNewGraph,
  triggerGraphImport,
  handleGraphImportFile,
  handleDrop,
  clearImportedData,
} = actions

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

const isModelValid = computed(() => validationErrors.value.size === 0)

const dataImportInput = ref<HTMLInputElement | null>(null)
const viewportState = ref<{ zoom: number; pan: { x: number; y: number } } | null>(null)
const codePanelLanguage = ref<CodeLanguage>('bugs')

const codePanelTitle = computed(() =>
  codePanelLanguage.value === 'stan' ? 'Stan Code Preview' : 'BUGS Code Preview'
)

const handleCodeDownload = () => {
  if (codePanelLanguage.value === 'stan') {
    handleDownloadStan()
  } else {
    handleDownloadBugs()
  }
}

watch(
  isDarkMode,
  (val) => {
    const element = document.querySelector('html')
    if (val) element?.classList.add('db-dark-mode')
    else element?.classList.remove('db-dark-mode')
  },
  { immediate: true }
)

let saveViewportTimeout: ReturnType<typeof setTimeout> | null = null
const persistViewport = () => {
  if (saveViewportTimeout) {
    clearTimeout(saveViewportTimeout)
    saveViewportTimeout = null
  }
  if (graphStore.currentGraphId && viewportState.value) {
    graphStore.updateGraphViewport(
      graphStore.currentGraphId,
      viewportState.value.zoom,
      viewportState.value.pan
    )
  }
}

const handleViewportChanged = (v: { zoom: number; pan: { x: number; y: number } }) => {
  viewportState.value = v
  if (saveViewportTimeout) clearTimeout(saveViewportTimeout)
  saveViewportTimeout = setTimeout(persistViewport, 200)
}

const handleLayoutUpdated = (layoutName: string) => {
  if (graphStore.currentGraphId) graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName)
}

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element
  if (element) {
    if (!uiStore.isRightTabPinned) {
      uiStore.setActiveRightTab('properties')
      if (window.innerWidth < 768 && isLeftSidebarOpen.value) isLeftSidebarOpen.value = false
      if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true
    }
  } else {
    if (!uiStore.isRightTabPinned && isRightSidebarOpen.value) isRightSidebarOpen.value = false
  }
}

const createNewProject = () => {
  baseCreateNewProject()
  activeLeftAccordionTabs.value = [...new Set([...activeLeftAccordionTabs.value, 'project'])]
  isLeftSidebarOpen.value = true
}

const handleLoadExample = async (exampleIdOrUrl: string) => {
  await baseLoadExample(exampleIdOrUrl, 'standard')
}

const handleLoadShared = async () => {
  const params = new URLSearchParams(window.location.search)
  const shareParam = params.get('share')
  let jsonStr: string | null = null
  if (shareParam) {
    try {
      jsonStr = await decodeAndDecompress(shareParam)
    } catch {
      /* ignore */
    }
  }
  if (!jsonStr) return

  try {
    const payload = JSON.parse(jsonStr)

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
              graphStore.updateGraphElements(newGraph.id, expandGraph(graphData.e))
              graphStore.updateGraphLayout(newGraph.id, 'preset')
              if (graphData.d) {
                try {
                  dataStore.updateGraphData(newGraph.id, {
                    content: JSON.stringify(JSON.parse(graphData.d), null, 2),
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
        if (projectStore.currentProject?.graphs.length)
          graphStore.selectGraph(projectStore.currentProject.graphs[0].id)
      }
    } else if (payload && payload.n && payload.e) {
      projectStore.createProject('Shared Project')
      if (projectStore.currentProjectId) {
        const newGraph = projectStore.addGraphToProject(projectStore.currentProjectId, payload.n)
        if (newGraph) {
          graphStore.updateGraphElements(
            newGraph.id,
            payload.v === 2 ? expandGraph(payload.e) : payload.e
          )
          graphStore.updateGraphLayout(newGraph.id, 'preset')
          if (payload.d) {
            try {
              dataStore.updateGraphData(newGraph.id, {
                content: JSON.stringify(JSON.parse(payload.d), null, 2),
              })
            } catch {
              dataStore.updateGraphData(newGraph.id, { content: payload.d })
            }
          }
          projectStore.saveProjects()
          graphStore.selectGraph(newGraph.id)
        }
      }
    }

    window.history.replaceState(
      {},
      document.title,
      window.location.origin + window.location.pathname
    )
    setTimeout(() => handleFit(), 500)
  } catch (e) {
    console.error('Failed to load shared model:', e)
    alert('Invalid or corrupted share link.')
  }
}

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

const handleScriptSettingsDone = () => {
  scriptStore.standaloneScript = getScriptContent()
  showScriptSettingsModal.value = false
}

const handleOpenScriptSettings = () => {
  showScriptSettingsModal.value = true
}

const toggleJsonPanel = () => {
  showDebugPanel.value = true
}

const toggleLeftSidebar = () => {
  if (!isLeftSidebarOpen.value && window.innerWidth < 768) isRightSidebarOpen.value = false
  isLeftSidebarOpen.value = !isLeftSidebarOpen.value
}

const toggleRightSidebar = () => {
  if (!isRightSidebarOpen.value && window.innerWidth < 768) isLeftSidebarOpen.value = false
  isRightSidebarOpen.value = !isRightSidebarOpen.value
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

watch(
  () => graphStore.currentGraphId,
  (newId) => {
    if (newId) {
      const content = graphStore.graphContents.get(newId)
      if (content)
        viewportState.value = { zoom: content.zoom ?? 1, pan: content.pan ?? { x: 0, y: 0 } }
    }
  },
  { immediate: true }
)

watch(
  [isCodePanelOpen, () => graphStore.currentGraphId],
  ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === graphId)
      if (graph && (graph.codePanelX === undefined || graph.codePanelY === undefined)) {
        const panelW = 400,
          panelH = 300
        const rightOffset = isRightSidebarOpen.value ? 340 : 20
        let targetX = window.innerWidth - rightOffset - panelW - 10
        if (targetX < 20) targetX = 20
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
          codePanelX: targetX,
          codePanelY: 90,
          codePanelWidth: panelW,
          codePanelHeight: panelH,
        })
      }
    }
  },
  { immediate: true }
)

watch(
  [isDataPanelOpen, () => graphStore.currentGraphId],
  ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === graphId)
      if (graph && (graph.dataPanelX === undefined || graph.dataPanelY === undefined)) {
        const leftOffset = isLeftSidebarOpen.value ? 320 : 20
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
          dataPanelX: leftOffset + 20,
          dataPanelY: 90,
          dataPanelWidth: 400,
          dataPanelHeight: 300,
        })
      }
    }
  },
  { immediate: true }
)

watch(
  [() => graphStore.currentGraphId, () => projectStore.currentProject?.graphs],
  () => {
    const id = graphStore.currentGraphId
    if (id && projectStore.currentProject) {
      const graph = projectStore.currentProject.graphs.find((g) => g.id === id)
      if (graph) {
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

watch(
  [generatedCode, parsedGraphData, samplerSettings],
  () => {
    if (standaloneScript.value || (activeRightTab.value === 'script' && isRightSidebarOpen.value)) {
      scriptStore.standaloneScript = getScriptContent()
    }
  },
  { deep: true }
)

watch(showNewGraphModal, (val) => {
  if (!val) {
    clearImportedData()
    newGraphName.value = ''
    if (graphImportInput.value) graphImportInput.value.value = ''
    isDragOver.value = false
  }
})

const handleSidebarContainerClick = (e: MouseEvent) => {
  if ((e.target as HTMLElement).closest('.db-theme-toggle-header')) return
  if (!isLeftSidebarOpen.value) toggleLeftSidebar()
}

const updateActiveAccordionTabs = (val: string | string[]) => {
  activeLeftAccordionTabs.value = Array.isArray(val) ? val : [val]
}

onMounted(async () => {
  projectStore.loadProjects()

  if (window.location.search.includes('share=')) await handleLoadShared()

  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project')
    if (props.defaultModel) await handleLoadExample(props.defaultModel)
    else if (projectStore.currentProjectId) await handleLoadExample('rats')
  } else {
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
  if (window.innerWidth < 768) showZoomControls.value = false
  window.addEventListener('beforeunload', persistViewport)
})

onUnmounted(() => {
  window.removeEventListener('beforeunload', persistViewport)
  persistViewport()
})
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
      @download-stan="handleDownloadStan"
      @download-stan-script="handleDownloadStanScript"
      @download-stan-data="handleDownloadStanData"
      @download-stan-inits="handleDownloadStanInits"
      @generate-script="handleGenerateStandalone"
      @share="handleShare"
      @open-export-modal="openExportModal"
      @export-json="handleExportJson"
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
              v-tooltip.top="{ value: 'Share via URL', showDelay: 0, hideDelay: 0 }"
              class="db-header-icon-btn db-collapsed-share-btn"
              @click.stop="handleShare"
            >
              <i class="fas fa-share-alt"></i>
            </button>
            <div
              v-tooltip.top="{ value: 'Expand Sidebar', showDelay: 0, hideDelay: 0 }"
              class="db-toggle-icon-wrapper"
            >
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
      :title="codePanelTitle"
      icon="fas fa-code"
      :is-open="isCodePanelOpen"
      :default-width="codePanelSize.width"
      :default-height="codePanelSize.height"
      :default-x="codePanelPos.x"
      :default-y="codePanelPos.y"
      :show-download="true"
      @close="toggleCodePanel"
      @download="handleCodeDownload"
      @drag-end="handleCodePanelDragEnd"
      @resize-end="handleCodePanelResizeEnd"
    >
      <CodePreviewPanel :is-active="true" v-model:language="codePanelLanguage" />
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

.db-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--theme-text-secondary);
  gap: 1rem;
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
</style>
