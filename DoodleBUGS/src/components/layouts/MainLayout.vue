<script setup lang="ts">
import { ref, onMounted, watch, nextTick, computed, type StyleValue } from 'vue';
import { storeToRefs } from 'pinia';
import type { LayoutOptions } from 'cytoscape';
import MultiCanvasView from '../canvas/MultiCanvasView.vue';
import ProjectManager from '../left-sidebar/ProjectManager.vue';
import NodePalette from '../left-sidebar/NodePalette.vue';
import ExecutionSettingsPanel from '../left-sidebar/ExecutionSettingsPanel.vue';
import DataInputPanel from '../panels/DataInputPanel.vue';
import NodePropertiesPanel from '../right-sidebar/NodePropertiesPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import JsonEditorPanel from '../right-sidebar/JsonEditorPanel.vue';
import ExecutionPanel from '../right-sidebar/ExecutionPanel.vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import ToggleSwitch from 'primevue/toggleswitch';
import Accordion from 'primevue/accordion';
import AccordionPanel from 'primevue/accordionpanel';
import AccordionHeader from 'primevue/accordionheader';
import AccordionContent from 'primevue/accordioncontent';
import Toolbar from 'primevue/toolbar';
import Button from 'primevue/button';
import Drawer from 'primevue/drawer';
import AboutModal from './AboutModal.vue';
import ExportModal from './ExportModal.vue';
import ValidationIssuesModal from './ValidationIssuesModal.vue';
import DebugPanel from '../common/DebugPanel.vue';
import DropdownMenu from '../common/DropdownMenu.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useProjectStore } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import { useDataStore } from '../../stores/dataStore';
import { useExecutionStore } from '../../stores/executionStore';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGraphValidator } from '../../composables/useGraphValidator';
import { useBugsCodeGenerator, generateStandaloneScript } from '../../composables/useBugsCodeGenerator';
import type { GraphElement, NodeType, ExampleModel, GraphNode } from '../../types';
import type { GeneratedFile } from '../../stores/executionStore';
import { exampleModels, nodeDefinitions } from '../../config/nodeDefinitions';

interface ExportOptions {
  bg: string;
  full: boolean;
  scale: number;
  quality?: number;
  maxWidth?: number;
  maxHeight?: number;
}

const projectStore = useProjectStore();
const graphStore = useGraphStore();
const uiStore = useUiStore();
const dataStore = useDataStore();
const executionStore = useExecutionStore();

const { parsedGraphData } = storeToRefs(dataStore);
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements();
const { generatedCode } = useBugsCodeGenerator(elements);
const { getCyInstance } = useGraphInstance();
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData);
const { backendUrl, isConnected, isConnecting, isExecuting, samplerSettings } = storeToRefs(executionStore);
const { isLeftSidebarOpen, isRightSidebarOpen, canvasGridStyle, workspaceGridStyle, workspaceGridSize, isWorkspaceGridEnabled, isMultiCanvasView } = storeToRefs(uiStore);

const currentMode = ref<string>('select');
const currentNodeType = ref<NodeType>('stochastic');
const isGridEnabled = ref(true);
const gridSize = ref(20);
const showZoomControls = ref(true);

// Computed property for validation status
const isModelValid = computed(() => validationErrors.value.size === 0);

// Sidebar State
const activeAccordionTabs = ref(['project', 'palette']);

// Modals State
const showNewProjectModal = ref(false);
const newProjectName = ref('');
const showNewGraphModal = ref(false);
const newGraphName = ref('');
const showAboutModal = ref(false);
const showValidationModal = ref(false);
const showConnectModal = ref(false);
const tempBackendUrl = ref(backendUrl.value || 'http://localhost:8081');
const showDebugPanel = ref(false);
const showExportModal = ref(false);
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null);

// Pinned State
const pinnedGraphTitle = ref<string | null>(null);

// --- View Options ---
const gridStyleOptions = [
    { label: 'Dots', value: 'dots' },
    { label: 'Lines', value: 'lines' }
];

const navBackendUrl = ref(backendUrl.value || 'http://localhost:8081');
const cloneCmd = 'git clone https://github.com/TuringLang/JuliaBUGS.jl.git';
const instantiateCmd = 'julia --project=DoodleBUGS/runtime -e "using Pkg; Pkg.instantiate()"';
const startCmd = 'julia --project=DoodleBUGS/runtime DoodleBUGS/runtime/server.jl';

// Copy helpers
const copiedBackendUrl = ref(false);
const copiedCloneCmd = ref(false);
const copiedInstantiateCmd = ref(false);
const copiedStartCmd = ref(false);

function copyWithFeedback(text: string, flag: typeof copiedBackendUrl) {
  navigator.clipboard.writeText(text).then(() => {
    flag.value = true;
    setTimeout(() => (flag.value = false), 1500);
  }).catch(err => console.error('Clipboard copy failed:', err));
}

const copyBackendUrl = () => copyWithFeedback(navBackendUrl.value, copiedBackendUrl);
const copyCloneCmd = () => copyWithFeedback(cloneCmd, copiedCloneCmd);
const copyInstantiateCmd = () => copyWithFeedback(instantiateCmd, copiedInstantiateCmd);
const copyStartCmd = () => copyWithFeedback(startCmd, copiedStartCmd);

// Dark Mode
const isDarkMode = ref(localStorage.getItem('darkMode') === 'true');
const applyDarkMode = () => {
    const element = document.querySelector('html');
    if (isDarkMode.value) element?.classList.add('dark-mode');
    else element?.classList.remove('dark-mode');
};
applyDarkMode();
const toggleDarkMode = () => {
    isDarkMode.value = !isDarkMode.value;
    localStorage.setItem('darkMode', String(isDarkMode.value));
    applyDarkMode();
};

// Mobile Menu
const mobileMenuOpen = ref(false);

onMounted(async () => {
  projectStore.loadProjects();
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project');
    if (projectStore.currentProjectId) await handleLoadExample('rats');
  } else {
    const lastGraphId = localStorage.getItem('doodlebugs-currentGraphId');
    if (lastGraphId && projectStore.currentProject?.graphs.some(g => g.id === lastGraphId)) {
      graphStore.selectGraph(lastGraphId);
    } else if (projectStore.currentProject?.graphs.length) {
      graphStore.selectGraph(projectStore.currentProject.graphs[0].id);
    }
  }
  uiStore.isMultiCanvasView = true;
  validateGraph();
});

watch(() => graphStore.currentGraphId, (newId) => {
    if (newId) {
      nextTick(() => {
        setTimeout(() => {
          const graphContent = graphStore.graphContents.get(newId);
          const layoutToApply = graphContent?.lastLayout || 'dagre';
          handleGraphLayout(layoutToApply);
        }, 100);
      });
    }
}, { immediate: true });

const handleLayoutUpdated = (layoutName: string) => {
  if (graphStore.currentGraphId) {
    graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName);
  }
};

const handleGraphLayout = (layoutName: string) => {
    const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null;
    if (!cy) return;
    /* eslint-disable @typescript-eslint/no-explicit-any */
    const layoutOptionsMap: Record<string, LayoutOptions> = {
        dagre: { name: 'dagre', animate: true, animationDuration: 500, fit: true, padding: 30 } as any,
        fcose: { name: 'fcose', animate: true, animationDuration: 500, fit: true, padding: 30, randomize: false, quality: 'proof' } as any,
        cola: { name: 'cola', animate: true, fit: true, padding: 30, refresh: 1, avoidOverlap: true, infinite: false, centerGraph: true, flow: { axis: 'y', minSeparation: 30 }, handleDisconnected: false, randomize: false } as any,
        klay: { name: 'klay', animate: true, animationDuration: 500, fit: true, padding: 30, klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' } } as any,
        preset: { name: 'preset' }
    };
    /* eslint-enable @typescript-eslint/no-explicit-any */
    const options = layoutOptionsMap[layoutName] || layoutOptionsMap.preset;
    cy.layout(options).run();
    handleLayoutUpdated(layoutName);
};

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element;
  if (element && !uiStore.isRightTabPinned) {
    uiStore.setActiveRightTab('properties');
    if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true;
  }
};

// Zoom to node logic from Validation Modal
const handleSelectNodeFromModal = (nodeId: string) => {
    // Find which graph this node belongs to
    let targetGraphId: string | null = null;
    let targetNode: GraphElement | null = null;

    // Search current project graphs
    if (projectStore.currentProject) {
        for (const graph of projectStore.currentProject.graphs) {
            // Check loaded content
            if (graphStore.graphContents.has(graph.id)) {
                const els = graphStore.graphContents.get(graph.id)!.elements;
                const found = els.find(el => el.id === nodeId);
                if (found) {
                    targetGraphId = graph.id;
                    targetNode = found;
                    break;
                }
            }
        }
    }

    if (targetGraphId && targetNode) {
        if (graphStore.currentGraphId !== targetGraphId) {
            graphStore.selectGraph(targetGraphId);
        }
        
        handleElementSelected(targetNode);
        graphStore.setElementToFocus(targetNode);
    }
};

const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
  if (!graphStore.currentGraphId) return;
  currentExportType.value = format;
  showExportModal.value = true;
};

const createNewProject = () => {
  if (newProjectName.value.trim()) {
    projectStore.createProject(newProjectName.value.trim());
    showNewProjectModal.value = false;
    newProjectName.value = '';
    activeAccordionTabs.value = [...new Set([...activeAccordionTabs.value, 'project'])];
    isLeftSidebarOpen.value = true;
  }
};

const createNewGraph = () => {
  if (projectStore.currentProject && newGraphName.value.trim()) {
    projectStore.addGraphToProject(projectStore.currentProject.id, newGraphName.value.trim());
    showNewGraphModal.value = false;
    newGraphName.value = '';
  }
};

const connectToBackend = async () => {
  isConnecting.value = true;
  isConnected.value = false;
  executionStore.setBackendUrl(tempBackendUrl.value);
  uiStore.setActiveRightTab('connection');
  executionStore.executionLogs.push(`Attempting to connect to backend at ${tempBackendUrl.value}...`);
  
  try {
    const response = await fetch(`${tempBackendUrl.value}/api/health`);
    if (!response.ok) throw new Error(`Health check failed with status: ${response.status}`);
    const result = await response.json();
    if (result.status !== 'ok') throw new Error('Backend returned an invalid health status.');
    isConnected.value = true;
    executionStore.executionLogs.push("Connection successful.");
    showConnectModal.value = false;
    isRightSidebarOpen.value = true;
  } catch (error: unknown) {
    const errorMessage = (error as Error).message;
    executionStore.executionLogs.push(`Connection failed: ${errorMessage}`);
    isConnected.value = false;
  } finally {
    isConnecting.value = false;
  }
};

const jsonToJulia = (jsonString: string): string => {
  try {
    const obj = JSON.parse(jsonString);
    if (Object.keys(obj).length === 0) return "()";
    const formatValue = (value: unknown): string => {
      if (Array.isArray(value)) {
        if (Array.isArray(value[0])) {
          return `[\n    ${value.map(row => (row as unknown[]).join(' ')).join(';\n    ')}\n]`;
        }
        return `[${value.join(', ')}]`;
      }
      return JSON.stringify(value);
    };
    const entries = Object.entries(obj).map(([key, value]) => `${key} = ${formatValue(value)}`);
    return `(\n  ${entries.join(',\n  ')}\n)`;
  } catch {
    return "()";
  }
};

let currentRunController: AbortController | null = null;
let abortedByUser = false;
const runModel = async () => {
  if (!isConnected.value || !backendUrl.value || isExecuting.value) return;

  uiStore.setActiveRightTab('connection');
  if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true;
  executionStore.resetExecutionState();
  executionStore.setExecutionPanelTab('logs');
  abortedByUser = false;

  try {
    if (currentRunController) {
      currentRunController.abort();
      currentRunController = null;
    }
    currentRunController = new AbortController();

    const dataPayload = parsedGraphData.value.data || {};
    const initsPayload = parsedGraphData.value.inits || {};
    const dataString = dataStore.inputMode === 'julia' ? (dataStore.dataString || '') : jsonToJulia(JSON.stringify(dataPayload));
    const initsString = dataStore.inputMode === 'julia' ? (dataStore.initsString || '') : jsonToJulia(JSON.stringify(initsPayload));

    const payload = {
      model_code: generatedCode.value,
      data: dataPayload,
      inits: initsPayload,
      data_string: dataString,
      inits_string: initsString,
      settings: { ...samplerSettings.value }
    };

    let response = await fetch(`${backendUrl.value}/api/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: currentRunController.signal
    });

    if (response.status === 404) {
      response = await fetch(`${backendUrl.value}/api/run_model`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model_code: payload.model_code,
          data_string: dataString,
          inits_string: initsString,
          settings: samplerSettings.value
        }),
        signal: currentRunController.signal
      });
    }

    /* eslint-disable @typescript-eslint/no-explicit-any */
    const result: any = await response.json();
    /* eslint-enable @typescript-eslint/no-explicit-any */
    executionStore.executionLogs = result.logs ?? [];
    if (!response.ok) throw new Error(result.error || `HTTP error! status: ${response.status}`);

    executionStore.executionResults = result.results ?? result.summary ?? null;
    executionStore.summaryResults = result.summary ?? null;
    executionStore.quantileResults = result.quantiles ?? null;

    const frontendStandaloneScript = generateStandaloneScript({
      modelCode: generatedCode.value,
      data: dataPayload,
      inits: initsPayload,
      settings: {
        n_samples: samplerSettings.value.n_samples,
        n_adapts: samplerSettings.value.n_adapts,
        n_chains: samplerSettings.value.n_chains,
        seed: samplerSettings.value.seed ?? undefined,
      }
    });
    const frontendStandaloneFile: GeneratedFile = { name: 'standalone.jl', content: frontendStandaloneScript };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const backendFiles = (result.files ?? []).filter((file: any) => file.name !== 'standalone.jl').map((file: any) => {
      return {
          name: file.name,
          content: typeof file.content === 'string' ? file.content : JSON.stringify(file.content),
      };
    });
    executionStore.generatedFiles = [frontendStandaloneFile, ...backendFiles];
    executionStore.executionError = null;
    executionStore.setExecutionPanelTab('results');

  } catch (error: unknown) {
    const err = error as Error & { name?: string };
    if (err?.name === 'AbortError') {
      executionStore.executionError = abortedByUser ? 'Execution aborted by user.' : 'Request aborted.';
    } else {
      executionStore.executionError = err.message;
    }
  } finally {
    isExecuting.value = false;
    currentRunController = null;
    abortedByUser = false;
  }
};

const handleGenerateStandalone = () => {
    const dataPayload = parsedGraphData.value.data || {};
    const initsPayload = parsedGraphData.value.inits || {};
    const script = generateStandaloneScript({
      modelCode: generatedCode.value,
      data: dataPayload,
      inits: initsPayload,
      settings: {
        n_samples: samplerSettings.value.n_samples,
        n_adapts: samplerSettings.value.n_adapts,
        n_chains: samplerSettings.value.n_chains,
        seed: samplerSettings.value.seed ?? undefined,
      },
    });
    const files = executionStore.generatedFiles.filter(f => f.name !== 'standalone.jl');
    files.unshift({ name: 'standalone.jl', content: script });
    executionStore.generatedFiles = files;
    uiStore.setActiveRightTab('connection');
    isRightSidebarOpen.value = true;
    executionStore.setExecutionPanelTab('files');
};

const handleExportJson = () => {
  if (!graphStore.currentGraphId) return;
  const elementsToExport = graphStore.currentGraphElements;
  const jsonString = JSON.stringify(elementsToExport, null, 2);
  const blob = new Blob([jsonString], { type: 'application/json' });
  const fileName = `graph.json`;
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
};

const handleConfirmExport = (options: ExportOptions) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const cy = (graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null) as any;
  if (!cy || !currentExportType.value) return;
  const fileName = `graph.${currentExportType.value}`;
  try {
    let blob: Blob;
    if (currentExportType.value === 'svg') {
      const svgOptions = { bg: options.bg, full: options.full, scale: options.scale };
      blob = new Blob([cy.svg(svgOptions)], { type: 'image/svg+xml;charset=utf-8' });
    } else {
      blob = cy[currentExportType.value]({ ...options, output: 'blob' });
    }
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  } catch (err) {
    console.error(`Failed to export ${currentExportType.value}:`, err);
  }
};

const handleLoadExample = async (exampleKey: string) => {
  if (!projectStore.currentProjectId) return;
  try {
    const baseUrl = import.meta.env.BASE_URL;
    const modelResponse = await fetch(`${baseUrl}examples/${exampleKey}/model.json`);
    if (!modelResponse.ok) throw new Error(`Could not fetch example model: ${modelResponse.statusText}`);
    const modelData: ExampleModel = await modelResponse.json();
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId, modelData.name);
    if (!newGraphMeta) return;
    graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON);
    const jsonDataResponse = await fetch(`${baseUrl}examples/${exampleKey}/data.json`);
    if (jsonDataResponse.ok) {
      const fullData = await jsonDataResponse.json();
      dataStore.inputMode = 'json';
      dataStore.dataString = JSON.stringify(fullData.data || {}, null, 2);
      dataStore.initsString = JSON.stringify(fullData.inits || {}, null, 2);
    }
    dataStore.inputMode = 'julia';
    dataStore.updateGraphData(newGraphMeta.id, dataStore.getGraphData(newGraphMeta.id));
  } catch (error) {
    console.error("Failed to load example model:", error);
  }
};

const toggleLeftSidebar = () => {
    isLeftSidebarOpen.value = !isLeftSidebarOpen.value;
};

const toggleRightSidebar = () => {
    isRightSidebarOpen.value = !isRightSidebarOpen.value;
};

const closeRightSidebar = () => {
    isRightSidebarOpen.value = false;
};

const handlePinnedChange = (payload: { id: string | null; name: string | null }) => {
    pinnedGraphTitle.value = payload.name;
};

const leftSidebarStyle = computed(() => {
    if (!isLeftSidebarOpen.value) {
        return {
            transform: 'scale(0)',
            opacity: 0,
            pointerEvents: 'none'
        };
    }
    return {
        transform: 'scale(1)',
        opacity: 1,
        pointerEvents: 'auto'
    };
});

const rightSidebarStyle = computed(() => ({
    transform: isRightSidebarOpen.value ? 'translateX(0)' : 'translateX(100%)',
    width: '320px',
    opacity: isRightSidebarOpen.value ? 1 : 0,
    pointerEvents: isRightSidebarOpen.value ? 'auto' : 'none'
}));

// Direct State Updaters
const setAddNodeType = (type: NodeType) => {
  currentNodeType.value = type;
  currentMode.value = 'add-node';
};

const updateGridEnabled = (val: boolean) => {
  isGridEnabled.value = val;
};

const updateGridSize = (val: number | string | null) => {
    if (val !== null && val !== '') {
        gridSize.value = Number(val);
    }
};

const updateWorkspaceGridSize = (val: number | string | null) => {
    if (val !== null && val !== '') {
        workspaceGridSize.value = Number(val);
    }
};

const updateShowZoomControls = (val: boolean) => {
  showZoomControls.value = val;
};

const updateShowDebugPanel = (val: boolean) => {
  showDebugPanel.value = val;
};

const toggleCanvasView = () => {
  isMultiCanvasView.value = !isMultiCanvasView.value;
};

const setModeAddEdge = () => {
  currentMode.value = 'add-edge';
};

const abortRun = () => {
  if (currentRunController) {
    abortedByUser = true;
    currentRunController.abort();
  }
};

</script>

<template>
  <div class="app-layout">
    <!-- Top Navbar (PrimeVue Toolbar) -->
    <Toolbar class="navbar-toolbar">
      <template #start>
        <div class="flex items-center gap-2">
          <span class="text-lg font-bold mr-3">DoodleBUGS</span>
          
          <!-- Desktop Menu -->
          <div class="desktop-menu flex gap-1">
            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Project</BaseButton>
              </template>
              <template #content>
                <a href="#" @click.prevent="showNewProjectModal = true">New Project...</a>
                <a href="#" @click.prevent="showNewGraphModal = true">New Graph...</a>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Export</BaseButton>
              </template>
              <template #content>
                <a href="#" @click.prevent="openExportModal('png')">as PNG...</a>
                <a href="#" @click.prevent="openExportModal('jpg')">as JPG...</a>
                <a href="#" @click.prevent="openExportModal('svg')">as SVG...</a>
                <div class="dropdown-divider"></div>
                <a href="#" @click.prevent="handleExportJson()">as JSON</a>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Add</BaseButton>
              </template>
              <template #content>
                <div class="dropdown-section-title">Nodes</div>
                <a v-for="nodeDef in nodeDefinitions" :key="nodeDef.nodeType" href="#"
                  @click.prevent="setAddNodeType(nodeDef.nodeType)">
                  {{ nodeDef.label }}
                </a>
                <div class="dropdown-divider"></div>
                <a href="#" @click.prevent="currentMode = 'add-edge'">Add Edge</a>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Layout</BaseButton>
              </template>
              <template #content>
                <a href="#" @click.prevent="handleGraphLayout('dagre')">Dagre (Hierarchical)</a>
                <a href="#" @click.prevent="handleGraphLayout('fcose')">fCoSE (Force-Directed)</a>
                <a href="#" @click.prevent="handleGraphLayout('cola')">Cola (Physics Simulation)</a>
                <a href="#" @click.prevent="handleGraphLayout('klay')">KLay (Layered)</a>
                <a href="#" @click.prevent="handleGraphLayout('preset')">Reset to Preset</a>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">View</BaseButton>
              </template>
              <template #content>
                <div class="view-options" @click.stop>
                  <div class="view-option-row">
                    <label for="multi-canvas" class="view-label">Multi-Canvas View</label>
                    <ToggleSwitch :modelValue="isMultiCanvasView" @update:modelValue="toggleCanvasView" inputId="multi-canvas" />
                  </div>
                  
                  <div class="dropdown-divider"></div>

                  <div class="view-option-row">
                    <label for="show-ws-grid" class="view-label">Workspace Grid</label>
                    <ToggleSwitch v-model="isWorkspaceGridEnabled" inputId="show-ws-grid" />
                  </div>
                  
                  <div class="view-option-row grid-settings-row">
                    <label for="ws-grid-style" class="view-label">Workspace Style</label>
                    <div class="flex gap-2 items-center justify-end settings-controls">
                      <BaseSelect 
                          id="ws-grid-style"
                          v-model="workspaceGridStyle"
                          :options="gridStyleOptions"
                          class="grid-style-select"
                      />
                      <input 
                          type="number" 
                          :value="workspaceGridSize" 
                          @input="(e) => updateWorkspaceGridSize((e.target as HTMLInputElement).value)"
                          step="10" min="10" max="200"
                          class="native-number-input"
                      />
                    </div>
                  </div>

                  <div class="view-option-row">
                    <label for="show-canvas-grid" class="view-label">Canvas Grid</label>
                    <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="updateGridEnabled" inputId="show-canvas-grid" />
                  </div>

                  <div class="view-option-row grid-settings-row">
                    <label for="canvas-grid-style" class="view-label">Canvas Style</label>
                    <div class="flex gap-2 items-center justify-end settings-controls">
                      <BaseSelect 
                          id="canvas-grid-style"
                          v-model="canvasGridStyle"
                          :options="gridStyleOptions"
                          class="grid-style-select"
                      />
                      <input 
                          type="number" 
                          :value="gridSize" 
                          @input="(e) => updateGridSize((e.target as HTMLInputElement).value)"
                          step="5" min="5" max="100"
                          class="native-number-input"
                      />
                    </div>
                  </div>
                  
                  <div class="dropdown-divider"></div>
                  
                  <div class="view-option-row">
                    <label for="show-zoom" class="view-label">Zoom Controls</label>
                    <ToggleSwitch :modelValue="showZoomControls" @update:modelValue="updateShowZoomControls" inputId="show-zoom" />
                  </div>
                  
                  <div class="view-option-row">
                    <label for="show-debug" class="view-label">Debug Console</label>
                    <ToggleSwitch :modelValue="showDebugPanel" @update:modelValue="updateShowDebugPanel" inputId="show-debug" />
                  </div>
                </div>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Examples</BaseButton>
              </template>
              <template #content>
                 <a v-for="example in exampleModels" :key="example.key" href="#" @click.prevent="handleLoadExample(example.key)">
                  {{ example.name }}
                </a>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Connection</BaseButton>
              </template>
              <template #content>
                <div class="execution-dropdown" @click.stop>
                  <div class="dropdown-section-title">Backend</div>
                  <div class="dropdown-input-group">
                    <label for="backend-url-nav">URL:</label>
                    <BaseInput id="backend-url-nav" v-model="navBackendUrl" placeholder="http://localhost:8081" class="backend-url-input" />
                    <BaseButton size="small" type="secondary" class="copy-btn" title="Copy URL" @click.stop="copyBackendUrl">
                      <i v-if="copiedBackendUrl" class="fas fa-check"></i>
                      <i v-else class="fas fa-copy"></i>
                    </BaseButton>
                  </div>
                  <div class="dropdown-actions">
                    <span class="connection-status" :class="{ connected: isConnected }">
                      <strong>{{ isConnected ? 'Connected' : 'Disconnected' }}</strong>
                    </span>
                    <BaseButton @click="connectToBackend" :disabled="isConnecting" size="small" type="primary">
                      <span v-if="isConnecting">Connecting...</span>
                      <span v-else>Connect</span>
                    </BaseButton>
                  </div>
                  <div class="dropdown-divider"></div>
                  <div class="dropdown-section-title">Setup Instructions</div>
                  <div class="setup-instructions">
                    <div class="instruction-item">
                      <span class="instruction-label">1. Clone repository:</span>
                      <div class="instruction-command">
                        <code>{{ cloneCmd }}</code>
                        <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyCloneCmd">
                          <i v-if="copiedCloneCmd" class="fas fa-check"></i>
                          <i v-else class="fas fa-copy"></i>
                        </BaseButton>
                      </div>
                    </div>
                    <div class="instruction-item">
                      <span class="instruction-label">2. First time only (instantiate deps):</span>
                      <div class="instruction-command">
                        <code>{{ instantiateCmd }}</code>
                        <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyInstantiateCmd">
                          <i v-if="copiedInstantiateCmd" class="fas fa-check"></i>
                          <i v-else class="fas fa-copy"></i>
                        </BaseButton>
                      </div>
                    </div>
                    <div class="instruction-item">
                      <span class="instruction-label">3. Start backend:</span>
                      <div class="instruction-command">
                        <code>{{ startCmd }}</code>
                        <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyStartCmd">
                          <i v-if="copiedStartCmd" class="fas fa-check"></i>
                          <i v-else class="fas fa-copy"></i>
                        </BaseButton>
                      </div>
                    </div>
                  </div>
                  <div class="dropdown-divider"></div>
                  <div class="dropdown-section-title">Standalone</div>
                  <a href="#" @click.prevent="handleGenerateStandalone">Generate Standalone Julia Script</a>
                </div>
              </template>
            </DropdownMenu>

            <DropdownMenu>
              <template #trigger>
                <BaseButton type="ghost" size="small">Help</BaseButton>
              </template>
              <template #content>
                <a href="#" @click.prevent="showAboutModal = true">About DoodleBUGS</a>
                <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" rel="noopener noreferrer" class="report-issue-link">
                   Report an Issue
                   <i class="fas fa-external-link-alt external-link-icon"></i>
                </a>
              </template>
            </DropdownMenu>
          </div>
        </div>
      </template>

      <template #end>
        <div class="flex items-center gap-1">
          <Button 
              :icon="isDarkMode ? 'pi pi-sun' : 'pi pi-moon'" 
              @click="toggleDarkMode" 
              text 
              rounded 
              aria-label="Toggle Dark Mode" 
              size="small"
          />
          
          <Button @click="toggleLeftSidebar" :class="{ 'p-button-outlined': isLeftSidebarOpen }" icon="pi pi-align-left" text rounded size="small" title="Toggle Left Sidebar" />
          <Button @click="toggleRightSidebar" :class="{ 'p-button-outlined': isRightSidebarOpen }" icon="pi pi-align-right" text rounded size="small" title="Toggle Right Sidebar" />
          
          <Button icon="pi pi-bars" class="mobile-toggle" @click="mobileMenuOpen = true" text rounded size="small" />
        </div>
      </template>
    </Toolbar>

    <!-- Mobile Menu Drawer -->
    <Drawer v-model:visible="mobileMenuOpen" header="Menu" position="right" class="w-80">
      <Accordion :multiple="true" :value="['run', 'view']">
          <AccordionPanel value="run">
              <AccordionHeader>Run</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton @click="runModel(); mobileMenuOpen = false" type="primary" :disabled="!isConnected || isExecuting" class="w-full justify-center py-3">
                          <i v-if="isExecuting" class="fas fa-spinner fa-spin mr-2"></i>
                          <i v-else class="fas fa-play mr-2"></i>
                          Run Model
                      </BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>
          
          <AccordionPanel value="view">
              <AccordionHeader>View Settings</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-5 pt-3 mobile-view-options">
                      <div class="mobile-option-row">
                          <label for="mobile-multi-canvas">Multi-Canvas</label>
                          <ToggleSwitch :modelValue="isMultiCanvasView" @update:modelValue="toggleCanvasView" inputId="mobile-multi-canvas" />
                      </div>
                      <div class="mobile-option-row">
                          <label for="mobile-show-ws-grid">Workspace Grid</label>
                          <ToggleSwitch v-model="isWorkspaceGridEnabled" inputId="mobile-show-ws-grid" />
                      </div>
                      <div class="mobile-option-row">
                          <label>Workspace Style</label>
                          <div class="flex gap-3 items-center">
                              <BaseSelect 
                                  v-model="workspaceGridStyle"
                                  :options="gridStyleOptions"
                                  class="w-24"
                              />
                              <input 
                                  type="number" 
                                  :value="workspaceGridSize" 
                                  @input="(e) => updateWorkspaceGridSize((e.target as HTMLInputElement).value)"
                                  step="10" min="10" max="200"
                                  class="native-number-input"
                              />
                          </div>
                      </div>
                      <div class="mobile-option-row">
                          <label for="mobile-show-canvas-grid">Canvas Grid</label>
                          <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="updateGridEnabled" inputId="mobile-show-canvas-grid" />
                      </div>
                      <div class="mobile-option-row">
                          <label>Canvas Style</label>
                          <div class="flex gap-3 items-center">
                              <BaseSelect 
                                  v-model="canvasGridStyle"
                                  :options="gridStyleOptions"
                                  class="w-24"
                              />
                              <input 
                                  type="number" 
                                  :value="gridSize" 
                                  @input="(e) => updateGridSize((e.target as HTMLInputElement).value)"
                                  step="5" min="5" max="100"
                                  class="native-number-input"
                              />
                          </div>
                      </div>
                      <div class="mobile-option-row">
                          <label for="mobile-show-zoom">Zoom Controls</label>
                          <ToggleSwitch :modelValue="showZoomControls" @update:modelValue="updateShowZoomControls" inputId="mobile-show-zoom" />
                      </div>
                      <div class="mobile-option-row">
                          <label for="mobile-show-debug">Debug Console</label>
                          <ToggleSwitch :modelValue="showDebugPanel" @update:modelValue="updateShowDebugPanel" inputId="mobile-show-debug" />
                      </div>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="project">
              <AccordionHeader>Project</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton @click="showNewProjectModal = true; mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">New Project</BaseButton>
                      <BaseButton @click="showNewGraphModal = true; mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">New Graph</BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="export">
              <AccordionHeader>Export</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton @click="openExportModal('png'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as PNG</BaseButton>
                      <BaseButton @click="openExportModal('jpg'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as JPG</BaseButton>
                      <BaseButton @click="openExportModal('svg'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as SVG</BaseButton>
                      <BaseButton @click="handleExportJson(); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as JSON</BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="add">
              <AccordionHeader>Add Nodes</AccordionHeader>
              <AccordionContent>
                  <div class="grid grid-cols-2 gap-3 pt-3">
                      <BaseButton v-for="nodeDef in nodeDefinitions" :key="nodeDef.nodeType" 
                          @click="setAddNodeType(nodeDef.nodeType); mobileMenuOpen = false" type="ghost" size="small" class="text-xs p-3 border border-gray-200 dark:border-gray-700 rounded h-full flex items-center justify-center">
                          {{ nodeDef.label }}
                      </BaseButton>
                      <BaseButton @click="setModeAddEdge(); mobileMenuOpen = false" type="ghost" size="small" class="text-xs p-3 border border-gray-200 dark:border-gray-700 rounded h-full flex items-center justify-center">Add Edge</BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="layout">
              <AccordionHeader>Layout</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton @click="handleGraphLayout('dagre'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Dagre</BaseButton>
                      <BaseButton @click="handleGraphLayout('fcose'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">fCoSE</BaseButton>
                      <BaseButton @click="handleGraphLayout('cola'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Cola</BaseButton>
                      <BaseButton @click="handleGraphLayout('klay'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">KLay</BaseButton>
                      <BaseButton @click="handleGraphLayout('preset'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Reset</BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="examples">
              <AccordionHeader>Examples</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton v-for="example in exampleModels" :key="example.key" 
                          @click="handleLoadExample(example.key); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">
                          {{ example.name }}
                      </BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="connection">
              <AccordionHeader>Connection</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-5 pt-3">
                      <div class="flex flex-col gap-2">
                          <label for="backend-url-mobile" class="text-sm font-medium">URL:</label>
                          <BaseInput id="backend-url-mobile" v-model="navBackendUrl" placeholder="http://localhost:8081" class="w-full" />
                      </div>
                      <BaseButton @click="connectToBackend(); mobileMenuOpen = false" :disabled="isConnecting" type="primary" class="w-full justify-center py-3">
                          <span v-if="isConnecting">Connecting...</span>
                          <span v-else>Connect</span>
                      </BaseButton>
                      <BaseButton @click="handleGenerateStandalone(); mobileMenuOpen = false" type="ghost" class="w-full text-left text-sm p-3 border border-gray-200 dark:border-gray-700 rounded">Generate Standalone Script</BaseButton>
                  </div>
              </AccordionContent>
          </AccordionPanel>

          <AccordionPanel value="help">
              <AccordionHeader>Help</AccordionHeader>
              <AccordionContent>
                  <div class="flex flex-col gap-4 pt-3">
                      <BaseButton @click="showAboutModal = true; mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">About</BaseButton>
                      <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" rel="noopener noreferrer" class="p-button p-component p-button-ghost p-button-sm w-full text-left no-underline justify-start p-3 border border-gray-200 dark:border-gray-700 rounded">
                          Report an Issue
                      </a>
                  </div>
              </AccordionContent>
          </AccordionPanel>
      </Accordion>
    </Drawer>

    <!-- Full Screen Canvas -->
    <main class="canvas-area">
      <MultiCanvasView 
        :is-grid-enabled="isGridEnabled" 
        @update:is-grid-enabled="isGridEnabled = $event"
        :grid-size="gridSize" 
        @update:grid-size="gridSize = $event"
        :current-mode="currentMode"
        @update:current-mode="currentMode = $event"
        :current-node-type="currentNodeType" 
        @update:current-node-type="currentNodeType = $event"
        :validation-errors="validationErrors"
        :show-zoom-controls="showZoomControls"
        @update:show-zoom-controls="showZoomControls = $event"
        @element-selected="handleElementSelected" 
        @layout-updated="handleLayoutUpdated"
        @new-graph="showNewGraphModal = true"
        @open-export-modal="openExportModal"
        @pinned-graph-change="handlePinnedChange" />
    </main>

    <!-- Logo Button (Collapsed Left Sidebar) -->
    <div class="sidebar-toggle-logo glass-panel" :class="{ hidden: isLeftSidebarOpen }">
       <div class="flex-grow cursor-pointer flex items-center" @click="toggleLeftSidebar" title="Open Menu">
           <span class="logo-text-minimized">
               {{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}
           </span>
       </div>
       <div class="flex items-center gap-1 ml-2">
           <button @click.stop="toggleDarkMode" class="theme-toggle-header" :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'">
               <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
           </button>
           <div class="cursor-pointer flex items-center" @click="toggleLeftSidebar" title="Open Menu">
               <svg width="20" height="20" fill="none" viewBox="0 0 24 24"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
           </div>
       </div>
    </div>

    <!-- Right Sidebar Toggle (Collapsed with Status Controls) -->
    <div class="sidebar-toggle-logo right glass-panel" :class="{ hidden: isRightSidebarOpen }">
       <div class="flex-grow cursor-pointer flex items-center" @click="toggleRightSidebar" title="Open Inspector">
           <span class="logo-text-minimized">Inspector</span>
       </div>
       
       <div class="flex items-center gap-2 mr-2">
            <div class="status-indicator backend-status" 
                 :class="{ 'connected': isConnected, 'disconnected': !isConnected }">
                <i class="fas fa-circle"></i>
                <div class="instant-tooltip">{{ isConnected ? 'Backend Connected' : 'Backend Disconnected' }}</div>
            </div>
            
            <div class="status-indicator validation-status"
                @click="showValidationModal = true"
                :class="isModelValid ? 'valid' : 'invalid'">
                <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
                <div class="instant-tooltip">{{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}</div>
            </div>
       </div>

       <div class="cursor-pointer flex items-center" @click="toggleRightSidebar" title="Open Inspector">
           <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
       </div>
    </div>

    <!-- Floating Left Sidebar -->
    <aside class="floating-sidebar left glass-panel" :style="leftSidebarStyle as StyleValue">
        <div class="sidebar-header">
            <span class="sidebar-title" @click="toggleLeftSidebar" style="cursor: pointer;">
                {{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}
            </span>
            <div class="flex items-center gap-1">
                <!-- Theme Toggle -->
                <button @click.stop="toggleDarkMode" class="theme-toggle-header" :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'">
                    <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
                </button>
                <div class="cursor-pointer flex items-center" @click="toggleLeftSidebar">
                    <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
                </div>
            </div>
        </div>
        
        <div class="sidebar-content-scrollable">
             <Accordion :value="activeAccordionTabs" multiple class="sidebar-accordion">
                <!-- Project -->
                <AccordionPanel value="project">
                    <AccordionHeader><i class="fas fa-folder icon-12"></i> Project</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <ProjectManager @new-project="showNewProjectModal = true" @new-graph="showNewGraphModal = true" />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Nodes -->
                <AccordionPanel value="palette">
                    <AccordionHeader><i class="fas fa-shapes icon-12"></i> Nodes</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <NodePalette @select-palette-item="(type) => { 
                                if (type === 'add-edge') {
                                    currentMode = 'add-edge';
                                } else {
                                    currentNodeType = type; 
                                    currentMode = 'add-node'; 
                                }
                            }" />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Data -->
                <AccordionPanel value="data">
                    <AccordionHeader><i class="fas fa-database icon-12"></i> Data</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper fixed-height-panel">
                            <DataInputPanel :is-active="true" />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Settings -->
                <AccordionPanel value="settings">
                    <AccordionHeader><i class="fas fa-sliders-h icon-12"></i> Run Settings</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <ExecutionSettingsPanel />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- View Options -->
                <AccordionPanel value="view">
                    <AccordionHeader><i class="fas fa-eye icon-12"></i> View Options</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <div class="menu-row">
                                <label>Workspace Grid</label>
                                <ToggleSwitch v-model="isWorkspaceGridEnabled" />
                            </div>
                            <div class="menu-row">
                                <label>WS Style</label>
                                <BaseSelect v-model="workspaceGridStyle" :options="gridStyleOptions" class="w-24" />
                            </div>
                            <div class="menu-row">
                                <label>WS Size</label>
                                <input 
                                    type="number" 
                                    :value="workspaceGridSize" 
                                    @input="(e) => updateWorkspaceGridSize((e.target as HTMLInputElement).value)"
                                    step="10" min="10" max="200"
                                    class="native-number-input"
                                />
                            </div>
                            <div class="divider"></div>
                            <div class="menu-row">
                                <label>Canvas Grid</label>
                                <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="updateGridEnabled" />
                            </div>
                            <div class="menu-row">
                                <label>Canvas Style</label>
                                <BaseSelect v-model="canvasGridStyle" :options="gridStyleOptions" class="w-24" />
                            </div>
                            <div class="menu-row">
                                <label>Canvas Size</label>
                                <input 
                                    type="number" 
                                    :value="gridSize" 
                                    @input="(e) => updateGridSize((e.target as HTMLInputElement).value)"
                                    step="5" min="5" max="100"
                                    class="native-number-input"
                                />
                            </div>
                            <div class="divider"></div>
                            <div class="menu-row">
                                <label>Zoom Controls</label>
                                <ToggleSwitch v-model="showZoomControls" />
                            </div>
                            <div class="menu-row">
                                <label>Debug Console</label>
                                <ToggleSwitch v-model="showDebugPanel" />
                            </div>
                            <div class="menu-row">
                                <label>Examples</label>
                                <BaseSelect :modelValue="''" :options="exampleModels.map(e => ({ label: e.name, value: e.key }))" @update:modelValue="handleLoadExample" placeholder="Load..." class="w-full" />
                            </div>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Export -->
                <AccordionPanel value="export">
                    <AccordionHeader><i class="fas fa-file-export icon-12"></i> Export</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <BaseButton type="ghost" class="menu-btn" @click="openExportModal('png')"><i class="fas fa-image"></i> PNG Image</BaseButton>
                            <BaseButton type="ghost" class="menu-btn" @click="openExportModal('jpg')"><i class="fas fa-file-image"></i> JPG Image</BaseButton>
                            <BaseButton type="ghost" class="menu-btn" @click="openExportModal('svg')"><i class="fas fa-vector-square"></i> SVG Vector</BaseButton>
                            <div class="divider"></div>
                            <BaseButton type="ghost" class="menu-btn" @click="handleExportJson()"><i class="fas fa-file-code"></i> JSON Data</BaseButton>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Connection -->
                <AccordionPanel value="connect">
                    <AccordionHeader><i class="fas fa-network-wired icon-12"></i> Connection</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <div class="flex-col gap-2">
                                <label class="text-xs font-bold">Backend URL</label>
                                <BaseInput v-model="navBackendUrl" placeholder="http://localhost:8081" />
                            </div>
                            <div class="status-display" :class="{ connected: isConnected }">
                                Status: {{ isConnected ? 'Connected' : 'Disconnected' }}
                            </div>
                            <BaseButton @click="connectToBackend" :disabled="isConnecting" type="primary" class="w-full justify-center">
                                {{ isConnecting ? 'Connecting...' : 'Connect' }}
                            </BaseButton>
                            <div class="divider"></div>
                            <BaseButton @click="handleGenerateStandalone" type="ghost" class="menu-btn"><i class="fas fa-file-alt"></i> Generate Script</BaseButton>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <!-- Help -->
                <AccordionPanel value="help">
                    <AccordionHeader><i class="fas fa-question-circle icon-12"></i> Help</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <BaseButton type="ghost" class="menu-btn" @click="showAboutModal = true"><i class="fas fa-info-circle"></i> About</BaseButton>
                            <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" class="menu-btn ghost-btn">
                                <i class="fab fa-github"></i> Report Issue
                            </a>
                        </div>
                    </AccordionContent>
                </AccordionPanel>
             </Accordion>
        </div>
    </aside>

    <!-- Floating Right Sidebar -->
    <aside class="floating-sidebar right glass-panel" :style="rightSidebarStyle as StyleValue">
        <div class="sidebar-header" @click="toggleRightSidebar" style="cursor: pointer;">
            <span class="sidebar-title">Inspector</span>
            
            <!-- Controls in Header when Open -->
            <div class="flex items-center gap-3 ml-auto" @click.stop>
                 <div class="status-indicator backend-status" 
                     :class="{ 'connected': isConnected, 'disconnected': !isConnected }">
                    <i class="fas fa-circle"></i>
                    <div class="instant-tooltip">{{ isConnected ? 'Backend Connected' : 'Backend Disconnected' }}</div>
                </div>
                <div class="status-indicator validation-status"
                    @click="showValidationModal = true"
                    :class="isModelValid ? 'valid' : 'invalid'">
                    <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
                    <div class="instant-tooltip">{{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}</div>
                </div>
            </div>

            <div class="cursor-pointer flex items-center ml-2">
                 <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
            </div>
        </div>
        
        <div class="sidebar-tabs text-tabs">
            <button :class="{ active: uiStore.activeRightTab === 'properties' }" @click="uiStore.setActiveRightTab('properties')">Props</button>
            <button :class="{ active: uiStore.activeRightTab === 'code' }" @click="uiStore.setActiveRightTab('code')">Code</button>
            <button :class="{ active: uiStore.activeRightTab === 'json' }" @click="uiStore.setActiveRightTab('json')">JSON</button>
            <button :class="{ active: uiStore.activeRightTab === 'connection' }" @click="uiStore.setActiveRightTab('connection')">Run</button>
        </div>

        <div class="sidebar-content">
            <NodePropertiesPanel v-show="uiStore.activeRightTab === 'properties'" 
                :selected-element="selectedElement" 
                :validation-errors="validationErrors"
                @update-element="updateElement" 
                @delete-element="deleteElement" />
            <CodePreviewPanel v-show="uiStore.activeRightTab === 'code'" :is-active="uiStore.activeRightTab === 'code'" />
            <JsonEditorPanel v-show="uiStore.activeRightTab === 'json'" :is-active="uiStore.activeRightTab === 'json'" />
            <ExecutionPanel v-show="uiStore.activeRightTab === 'connection'" />
        </div>
    </aside>

    <!-- Modals -->
    <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
      <template #header><h3>Create New Project</h3></template>
      <template #body>
        <div class="flex-col gap-2">
          <label>Project Name:</label>
          <BaseInput v-model="newProjectName" placeholder="Enter project name" @keyup.enter="createNewProject" />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showNewProjectModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewProject" type="primary">Create</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
      <template #header><h3>Create New Graph</h3></template>
      <template #body>
        <div class="flex-col gap-2">
          <label>Graph Name:</label>
          <BaseInput v-model="newGraphName" placeholder="Enter graph name" @keyup.enter="createNewGraph" />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showNewGraphModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewGraph" type="primary">Create</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showConnectModal" @close="showConnectModal = false">
      <template #header><h3>Connect to Backend</h3></template>
      <template #body>
        <div class="flex-col gap-2">
          <label>Backend Server URL:</label>
          <BaseInput v-model="tempBackendUrl" placeholder="http://localhost:8081" @keyup.enter="connectToBackend" />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showConnectModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="connectToBackend" type="primary" :disabled="isConnecting">
          {{ isConnecting ? 'Connecting...' : 'Connect' }}
        </BaseButton>
      </template>
    </BaseModal>

    <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
    <ExportModal :is-open="showExportModal" :export-type="currentExportType" @close="showExportModal = false" @confirm-export="handleConfirmExport" />
    <ValidationIssuesModal :is-open="showValidationModal" :validation-errors="validationErrors" :elements="elements" @select-node="handleSelectNodeFromModal" @close="showValidationModal = false" />
    <DebugPanel v-if="showDebugPanel" />
  </div>
</template>

<style scoped>
.app-layout {
  position: relative;
  width: 100vw;
  height: 100vh;
  overflow: hidden;
  background-color: var(--theme-bg-canvas);
}

.canvas-area {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  z-index: 0;
}

/* Logo Button (Collapsed Sidebar) */
.sidebar-toggle-logo {
  position: absolute;
  top: 16px;
  left: 16px;
  z-index: 50;
  padding: 8px 12px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  transition: all 0.2s ease;
  border: 1px solid var(--theme-border);
  background: var(--theme-bg-panel);
}

.sidebar-toggle-logo.right {
  left: auto;
  right: 16px;
}

.sidebar-toggle-logo.hidden {
    opacity: 0;
    pointer-events: none;
    transform: scale(0.8);
}

.sidebar-toggle-logo:hover {
  transform: scale(1.02);
  box-shadow: var(--shadow-md);
}

.logo-text-minimized {
    font-family: var(--font-family-sans);
    font-size: 14px;
    font-weight: 600;
    color: var(--theme-text-primary);
}

/* Right Sidebar Toggle */
.sidebar-toggle {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  width: 32px;
  height: 60px;
  z-index: 40;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.sidebar-toggle.right {
  right: 0;
  border-top-left-radius: var(--radius-lg);
  border-bottom-left-radius: var(--radius-lg);
  border-right: none;
}

.sidebar-toggle:hover {
  width: 40px;
  color: var(--theme-primary);
  background: var(--theme-bg-panel);
}

/* Floating Sidebars */
.floating-sidebar {
  position: absolute;
  top: 16px;
  bottom: 16px;
  z-index: 50;
  display: flex;
  flex-direction: column;
  border-radius: var(--radius-lg);
  overflow: hidden;
  transition: transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1), opacity 0.3s ease;
}

.floating-sidebar.left {
  left: 16px;
  width: 300px !important;
  transform-origin: top left;
}

.floating-sidebar.right {
  right: 16px;
}

.sidebar-header {
  padding: 12px 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--theme-border);
  background: var(--theme-bg-panel-transparent);
  color: var(--theme-text-primary);
  flex-shrink: 0;
}

.sidebar-title {
  font-weight: 600;
  font-size: var(--font-size-md);
}

.toggle-icon {
    color: var(--theme-text-secondary);
}

.close-btn {
  background: transparent;
  border: none;
  color: var(--theme-text-secondary);
  cursor: pointer;
  padding: 6px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  z-index: 100;
}

.close-btn:hover {
  color: var(--theme-text-primary);
  background-color: var(--theme-bg-hover);
}

/* Accordion Sidebar Structure */
.sidebar-content-scrollable {
    overflow-y: auto;
    flex: 1;
    background: var(--theme-bg-panel);
}

/* Accordion Styling Overrides */
:deep(.sidebar-accordion .p-accordion-header-link) {
    padding: 0.75rem 1rem;
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--theme-text-primary);
    background: transparent;
    border: none;
    border-bottom: 1px solid var(--theme-border);
    outline: none;
    justify-content: flex-start; /* Align headings to the left */
}

:deep(.sidebar-accordion .p-accordion-header:not(.p-disabled) .p-accordion-header-link:focus) {
    box-shadow: none;
    background: var(--theme-bg-hover);
}

:deep(.sidebar-accordion .p-accordion-content-content) {
    padding: 0;
    background: transparent;
}

:deep(.sidebar-accordion .p-accordion-panel) {
    border: none;
}

.icon-12 {
    font-size: 12px;
    width: 20px;
    text-align: center;
    margin-right: 8px;
    color: var(--theme-text-secondary);
}

.panel-content-wrapper {
    padding: 4px;
    background: var(--theme-bg-panel);
}

.fixed-height-panel {
    height: 350px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
}

/* Override child styles to fit accordion */
:deep(.project-manager), :deep(.node-palette), :deep(.execution-settings-panel) {
    background: transparent;
    height: auto !important;
    overflow: visible !important;
    padding: 8px;
    border: none;
}

:deep(.data-input-panel) {
    height: 100%;
    padding: 8px;
}

/* Sidebar Right Content */
.sidebar-content {
  flex: 1;
  overflow-y: auto;
  background: var(--theme-bg-panel);
}

/* Menu Panel Styling */
.menu-panel {
    display: flex;
    padding: 8px;
}
.menu-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: var(--font-size-sm);
    color: var(--theme-text-primary);
    margin-bottom: 8px;
}
.menu-btn {
    justify-content: flex-start !important;
    gap: 10px;
    width: 100%;
    padding: 10px !important;
    font-size: var(--font-size-sm);
    color: var(--theme-text-primary);
    border-radius: var(--radius-sm);
    transition: background-color 0.2s;
}
.menu-btn:hover {
    background-color: var(--theme-bg-hover);
}
.ghost-btn {
    color: var(--theme-text-secondary);
    text-decoration: none;
    display: flex;
    align-items: center;
    border-radius: var(--radius-sm);
    padding: 8px;
}
.ghost-btn:hover {
    background: var(--theme-bg-hover);
    color: var(--theme-text-primary);
}
.divider {
    height: 1px;
    background: var(--theme-border);
    margin: 12px 0;
}
.status-display {
    font-size: var(--font-size-xs);
    padding: 8px;
    border-radius: var(--radius-sm);
    background: var(--theme-bg-active);
    text-align: center;
    color: var(--theme-text-secondary);
    margin-bottom: 8px;
}
.status-display.connected {
    color: var(--theme-success);
    background: rgba(16, 185, 129, 0.1);
}

/* Theme toggle button in Header */
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

/* Styled BaseInput for Grid Size */
.native-number-input {
    width: 60px;
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--theme-border);
    border-radius: var(--radius-sm);
    background: var(--theme-bg-panel);
    color: var(--theme-text-primary);
    font-size: 0.85rem;
    text-align: right;
}
.native-number-input:focus {
    outline: none;
    border-color: var(--theme-primary);
}

/* Select (Desktop) */
.grid-style-select {
    width: auto !important;
    min-width: 4.5rem; /* Enough for "Lines" + arrow */
}

.grid-style-select :deep(.p-select-label) {
    padding: 0.25rem 0.5rem;
    font-size: 0.85rem;
}

.grid-style-select :deep(.p-select-dropdown) {
    width: 1.5rem;
}

.setup-instructions {
    padding: 0.5rem 0;
}

.instruction-item {
    margin-bottom: 1rem;
}

.instruction-item:last-child {
    margin-bottom: 0;
}

.instruction-label {
    display: block;
    font-size: 0.8rem;
    font-weight: 500;
    margin-bottom: 0.25rem;
    color: var(--p-text-color);
}

.instruction-command {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background-color: var(--color-background-mute);
    border: 1px solid var(--p-content-border-color);
    border-radius: 4px;
    padding: 0.5rem;
}

:global(.dark-mode) .instruction-command {
    background-color: var(--color-background-soft);
}

.instruction-command code {
    flex: 1;
    font-family: 'Courier New', monospace;
    font-size: 0.75rem;
    color: var(--p-text-color);
    word-break: break-all;
}

.copy-btn-inline {
    flex-shrink: 0;
    padding: 0.15rem 0.4rem;
}

/* Mobile Menu Spacing */
.mobile-view-options {
    gap: 1.5rem;
}

.mobile-option-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 0.5rem 0;
    border-bottom: 1px solid var(--p-content-border-color);
}

.mobile-option-row:last-child {
    border-bottom: none;
}

.mobile-option-row label {
    font-size: 0.95rem;
    cursor: pointer;
    font-weight: 500;
}

.icon-only-btn-compact {
    padding: 4px !important;
    width: 24px;
    height: 24px;
    min-width: 0;
    display: flex;
    justify-content: center;
    align-items: center;
}

.navbar-toolbar {
    border: none;
    border-bottom: 1px solid var(--p-content-border-color);
    border-radius: 0;
    padding: 0.25rem 1rem;
    background: var(--p-content-background);
    min-height: var(--navbar-height);
}

/* Responsive Visibility */
@media (max-width: 1024px) {
    .desktop-menu, .desktop-actions {
        display: none !important;
    }
    .mobile-toggle {
        display: inline-flex !important;
    }
}

@media (min-width: 1025px) {
    .mobile-toggle {
        display: none !important;
    }
}

/* Instant Tooltip Status Indicator */
.status-indicator {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    cursor: help;
}

.backend-status { margin-right: 5px; }
.backend-status.connected { color: var(--theme-success); }
.backend-status.disconnected { color: var(--theme-danger); }

.validation-status { font-size: 1.1em; margin: 0 5px; }
.validation-status.valid { color: var(--theme-success) !important; }
.validation-status.invalid { color: var(--theme-warning); }

.instant-tooltip {
    position: absolute;
    top: 100%;
    left: 50%;
    transform: translateX(-50%);
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
    box-shadow: 0 2px 6px rgba(0,0,0,0.2);
}

.status-indicator:hover .instant-tooltip {
    opacity: 1;
}

.dropdown-checkbox {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 8px;
    cursor: pointer;
}
.dropdown-input-group {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 8px;
}

.execution-dropdown {
    padding: 5px;
    min-width: 300px;
}
.dropdown-actions {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 10px;
}
.connection-status {
    font-size: 0.85em;
}
.connection-status.connected { color: var(--theme-success); }

.report-issue-link {
    display: flex;
    justify-content: space-between;
    align-items: center;
}
.external-link-icon {
    font-size: 0.8em;
    opacity: 0.7;
}

.view-options {
    padding: 0.75rem;
    min-width: 320px;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.view-option-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
}

.view-label {
    cursor: pointer;
    font-size: 0.85rem;
    font-weight: 500;
    flex: 1;
    text-align: left;
    white-space: nowrap;
}

.settings-controls {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 8px;
}

@media (max-width: 640px) {
    .hidden-sm {
        display: none;
    }
}

/* Tabs for Right Sidebar */
.sidebar-tabs {
  display: flex;
  background: var(--theme-bg-hover);
  padding: 4px;
  gap: 4px;
  border-bottom: 1px solid var(--theme-border);
}

.sidebar-tabs button {
  flex: 1;
  background: transparent;
  border: none;
  padding: 8px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  color: var(--theme-text-secondary);
  transition: all 0.2s;
  font-weight: 500;
}

.sidebar-tabs button:hover {
  background: rgba(0,0,0,0.05);
  color: var(--theme-text-primary);
}

.sidebar-tabs button.active {
  background: var(--theme-bg-panel);
  color: var(--theme-primary);
  box-shadow: var(--shadow-sm);
}
</style>
