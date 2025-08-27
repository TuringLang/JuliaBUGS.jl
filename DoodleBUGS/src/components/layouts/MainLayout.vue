<!-- src/components/layouts/MainLayout.vue -->
<script setup lang="ts">
import { ref, computed, onUnmounted, watch, onMounted, nextTick } from 'vue';
import type { StyleValue } from 'vue';
import { storeToRefs } from 'pinia';
import type { Core, LayoutOptions } from 'cytoscape';
import GraphEditor from '../canvas/GraphEditor.vue';
import ProjectManager from '../left-sidebar/ProjectManager.vue';
import NodePalette from '../left-sidebar/NodePalette.vue';
import ExecutionSettingsPanel from '../left-sidebar/ExecutionSettingsPanel.vue';
import DataInputPanel from '../panels/DataInputPanel.vue';
import NodePropertiesPanel from '../right-sidebar/NodePropertiesPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import JsonEditorPanel from '../right-sidebar/JsonEditorPanel.vue';
import ExecutionPanel from '../right-sidebar/ExecutionPanel.vue';
import TheNavbar from './TheNavbar.vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
import AboutModal from './AboutModal.vue';
import ExportModal from './ExportModal.vue';
import ValidationIssuesModal from './ValidationIssuesModal.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useProjectStore } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import { useDataStore } from '../../stores/dataStore';
import { useExecutionStore } from '../../stores/executionStore';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGraphValidator } from '../../composables/useGraphValidator';
import { useBugsCodeGenerator, generateStandaloneScript } from '../../composables/useBugsCodeGenerator';
import type { GraphElement, NodeType, PaletteItemType, ExampleModel } from '../../types';
import type { ExecutionResult, GeneratedFile } from '../../stores/executionStore';

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
const { activeLeftTab, isLeftSidebarOpen, leftSidebarWidth, isRightSidebarOpen, rightSidebarWidth } = storeToRefs(uiStore);

const currentMode = ref<string>('select');
const currentNodeType = ref<NodeType>('stochastic');
const isGridEnabled = ref(true);
const gridSize = ref(20);

const isResizingLeft = ref(false);
const isResizingRight = ref(false);

const showNewProjectModal = ref(false);
const newProjectName = ref('');
const showNewGraphModal = ref(false);
const newGraphName = ref('');
const showAboutModal = ref(false);
const showValidationModal = ref(false);
const showConnectModal = ref(false);
const tempBackendUrl = ref(backendUrl.value || 'http://localhost:8081');

const showExportModal = ref(false);
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null);

onMounted(async () => {
  projectStore.loadProjects();

  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project');
    if (projectStore.currentProjectId) {
      await handleLoadExample('rats');
    }
  } else {
    const lastGraphId = localStorage.getItem('doodlebugs-currentGraphId');
    if (lastGraphId) {
      const project = projectStore.currentProject;
      if (project && project.graphs.some(g => g.id === lastGraphId)) {
        graphStore.selectGraph(lastGraphId);
      }
    } else if (projectStore.currentProject?.graphs.length) {
      graphStore.selectGraph(projectStore.currentProject.graphs[0].id);
    }
  }

  validateGraph();
});

watch(
  () => graphStore.currentGraphId,
  (newId, oldId) => {
    if (newId && newId !== oldId) {
      nextTick(() => {
        setTimeout(() => {
          handleGraphLayout('dagre');
        }, 100);
      });
    }
  }, { immediate: true });

const currentProjectName = computed(() => projectStore.currentProject?.name || null);
const activeGraphName = computed(() => {
  if (projectStore.currentProject && graphStore.currentGraphId) {
    const graphMeta = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return graphMeta?.name || null;
  }
  return null;
});

const leftSidebarStyle = computed((): StyleValue => ({
  width: isLeftSidebarOpen.value ? `${leftSidebarWidth.value}px` : 'var(--vertical-tab-width)',
  transition: isResizingLeft.value ? 'none' : 'width 0.3s ease-in-out',
}));

const leftSidebarContentStyle = computed((): StyleValue => {
  const contentWidth = leftSidebarWidth.value - 50;
  return {
    width: `${contentWidth}px`,
    opacity: isLeftSidebarOpen.value ? '1' : '0',
    pointerEvents: isLeftSidebarOpen.value ? 'auto' : 'none',
  };
});

const rightSidebarStyle = computed((): StyleValue => ({
  width: isRightSidebarOpen.value ? `${rightSidebarWidth.value}px` : '0',
  opacity: isRightSidebarOpen.value ? '1' : '0',
  pointerEvents: isRightSidebarOpen.value ? 'auto' : 'none',
  borderLeft: isRightSidebarOpen.value ? '1px solid var(--color-border)' : 'none',
  transition: isResizingRight.value ? 'none' : 'width 0.3s ease-in-out, opacity 0.3s ease-in-out',
}));

const startResizeLeft = () => {
  isResizingLeft.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  window.addEventListener('mousemove', doResizeLeft);
  window.addEventListener('mouseup', stopResize);
};

const doResizeLeft = (event: MouseEvent) => {
  if (isResizingLeft.value) {
    const newWidth = event.clientX;
    leftSidebarWidth.value = Math.max(250, Math.min(newWidth, 600));
  }
};

const startResizeRight = () => {
  isResizingRight.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  window.addEventListener('mousemove', doResizeRight);
  window.addEventListener('mouseup', stopResize);
};

const doResizeRight = (event: MouseEvent) => {
  if (isResizingRight.value) {
    const newWidth = window.innerWidth - event.clientX;
    rightSidebarWidth.value = Math.max(400, Math.min(newWidth, 800));
  }
};

const stopResize = () => {
  isResizingLeft.value = false;
  isResizingRight.value = false;
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  window.removeEventListener('mousemove', doResizeLeft);
  window.removeEventListener('mousemove', doResizeRight);
  window.removeEventListener('mouseup', stopResize);
};

onUnmounted(() => {
  stopResize();
});

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element;
  if (element && !uiStore.isRightTabPinned) {
    uiStore.setActiveRightTab('properties');
  }
};

const handleSelectNodeFromModal = (nodeId: string) => {
  const nodeToSelect = elements.value.find(el => el.id === nodeId);
  if (nodeToSelect) {
    handleElementSelected(nodeToSelect);
    const cy = getCyInstance();
    if (cy) {
      cy.elements().unselect();
      cy.getElementById(nodeId).select();
      cy.animate({
        center: {
          eles: cy.getElementById(nodeId)
        },
        zoom: 1.2,
        duration: 500
      });
    }
  }
};

const handleUpdateElement = (updatedEl: GraphElement) => {
  updateElement(updatedEl);
};

const handleDeleteElement = (elementId: string) => {
  deleteElement(elementId);
};

const handleGraphLayout = (layoutName: string) => {
  const cy = getCyInstance();
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
};

const handlePaletteSelection = (itemType: PaletteItemType) => {
  if (itemType === 'add-edge') {
    currentMode.value = 'add-edge';
  } else {
    currentMode.value = 'add-node';
    currentNodeType.value = itemType;
  }
  isLeftSidebarOpen.value = false;
};

const createNewProject = () => {
  if (newProjectName.value.trim()) {
    projectStore.createProject(newProjectName.value.trim());
    showNewProjectModal.value = false;
    newProjectName.value = '';
    activeLeftTab.value = 'project';
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

const saveCurrentGraph = () => {
  if (graphStore.currentGraphId) {
    graphStore.saveGraph(graphStore.currentGraphId, graphStore.graphContents.get(graphStore.currentGraphId)!);
  }
};

const triggerDownload = (blob: Blob, fileName: string) => {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

const handleExportJson = () => {
  if (!graphStore.currentGraphId) return;
  const elementsToExport = graphStore.currentGraphElements;
  const jsonString = JSON.stringify(elementsToExport, null, 2);
  const blob = new Blob([jsonString], { type: 'application/json' });
  const fileName = `${activeGraphName.value || 'graph'}.json`;
  triggerDownload(blob, fileName);
};

const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
  if (!graphStore.currentGraphId) return;
  currentExportType.value = format;
  showExportModal.value = true;
};

const handleConfirmExport = (options: ExportOptions) => {
  const cy = getCyInstance() as Core & { svg: (options: object) => string; jpg: (options: object) => Blob; png: (options: object) => Blob; };
  if (!cy || !currentExportType.value) return;
  const fileName = `${activeGraphName.value || 'graph'}.${currentExportType.value}`;
  try {
    let blob: Blob;
    if (currentExportType.value === 'svg') {
      const svgOptions = { bg: options.bg, full: options.full, scale: options.scale };
      blob = new Blob([cy.svg(svgOptions)], { type: 'image/svg+xml;charset=utf-8' });
    } else {
      blob = cy[currentExportType.value]({ ...options, output: 'blob' });
    }
    triggerDownload(blob, fileName);
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
      
      // Temporarily set mode to json to ensure correct data ingestion
      dataStore.inputMode = 'json';
      dataStore.dataString = JSON.stringify(fullData.data || {}, null, 2);
      dataStore.initsString = JSON.stringify(fullData.inits || {}, null, 2);

    } else {
      const juliaDataResponse = await fetch(`${baseUrl}examples/${exampleKey}/data.jl`);
      if (juliaDataResponse.ok) {
        const juliaText = await juliaDataResponse.text();
        const dataMatch = juliaText.match(/data\s*=\s*(\([\s\S]*?\))\s*/m);
        const initsMatch = juliaText.match(/inits\s*=\s*(\([\s\S]*?\))\s*/m);
        
        // Set the mode to julia before assigning julia strings
        dataStore.inputMode = 'julia';
        dataStore.dataString = dataMatch ? dataMatch[1] : '()';
        dataStore.initsString = initsMatch ? initsMatch[1] : '()';
      }
    }
    
    // Set the default view to Julia and save the final state
    dataStore.inputMode = 'julia';
    dataStore.updateGraphData(newGraphMeta.id, dataStore.getGraphData(newGraphMeta.id));

  } catch (error) {
    console.error("Failed to load example model:", error);
  }
};

const isModelValid = computed(() => validationErrors.value.size === 0);

// Inline navbar connect handler
const connectToBackendUrl = async (url: string) => {
  tempBackendUrl.value = url?.trim() || '';
  await connectToBackend();
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

let currentRunController: AbortController | null = null;
let abortedByUser = false;
const abortRun = () => {
  if (currentRunController) {
    abortedByUser = true;
    executionStore.executionLogs.push('Abort requested by user...');
    currentRunController.abort();
  }
};

const runModel = async () => {
  if (!isConnected.value || !backendUrl.value || isExecuting.value) return;

  uiStore.setActiveRightTab('connection');
  executionStore.resetExecutionState();
  executionStore.setExecutionPanelTab('logs');

  // Reset abort flag each run
  abortedByUser = false;

  try {
    // Ensure any previous in-flight request is cancelled
    if (currentRunController) {
      currentRunController.abort();
      currentRunController = null;
    }
    currentRunController = new AbortController();

    // Build payload with JSON-first approach AND include Julia literals for backend
    const dataPayload = dataStore.inputMode === 'json' ? JSON.parse(dataStore.dataString || '{}') : JSON.parse(JSON.stringify(juliaTupleToJsonObject(dataStore.dataString)));
    const initsPayload = dataStore.inputMode === 'json' ? JSON.parse(dataStore.initsString || '{}') : JSON.parse(JSON.stringify(juliaTupleToJsonObject(dataStore.initsString)));

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

    // Prefer new /api/run endpoint; fallback to legacy /api/run_model
    const started = performance.now();
    let response = await fetch(`${backendUrl.value}/api/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: currentRunController.signal
    });
    const tFetch = performance.now();
    executionStore.executionLogs.push(`HTTP ${response.status} from /api/run in ${Math.round(tFetch - started)}ms`);

    if (response.status === 404) {
      executionStore.executionLogs.push(`Falling back to /api/run_model`);
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

    type RunApiResponse = {
      logs?: string[];
      error?: string;
      results?: ExecutionResult[] | null;
      summary?: ExecutionResult[] | null;
      quantiles?: ExecutionResult[] | null;
      files?: GeneratedFile[];
    };
    let result: RunApiResponse;
    try {
      result = (await response.json()) as RunApiResponse;
      executionStore.executionLogs.push(`Parsed JSON response in ${Math.round(performance.now() - tFetch)}ms`);
    } catch (e) {
      const text = await response.text().catch(() => '');
      executionStore.executionError = `Failed to parse JSON: ${(e as Error).message}`;
      executionStore.executionLogs.push(`Response text (truncated): ${text.slice(0, 400)}...`);
      throw e;
    }

    executionStore.executionLogs = result.logs ?? [];
    if (!response.ok) throw new Error(result.error || `HTTP error! status: ${response.status}`);

    // Maintain backward-compat; prefer summary if present
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
    executionStore.generatedFiles = (result.files ?? []).filter(file => file.name !== 'standalone.jl').concat(frontendStandaloneFile);
    executionStore.executionError = null;

    // Switch to Results on successful completion
    executionStore.setExecutionPanelTab('results');

  } catch (error: unknown) {
    const err = error as Error & { name?: string };
    if (err?.name === 'AbortError') {
      if (abortedByUser) {
        executionStore.executionError = 'Execution aborted by user.';
        executionStore.executionLogs.push('Fetch aborted by user.');
      } else {
        executionStore.executionError = 'Request was aborted. If this was unintentional, avoid editing or reloading during a run, or try a production preview build.';
        executionStore.executionLogs.push('Fetch aborted by the browser or app environment.');
      }
    } else if (err instanceof TypeError) {
      executionStore.executionError = `Network error during fetch: ${err.message}. This can happen if the request was interrupted (HMR/navigation).`;
      executionStore.executionLogs.push('Network error likely due to request interruption.');
    } else {
      executionStore.executionError = err.message;
    }
  } finally {
    isExecuting.value = false;
    if (currentRunController) {
      currentRunController = null;
    }
    abortedByUser = false;
  }
};

// Convert a Julia NamedTuple-like string to a JSON-friendly object (best-effort)
function juliaTupleToJsonObject(juliaString: string): Record<string, unknown> {
  try {
    // Very conservative: if it's already JSON, return parsed
    try { return JSON.parse(juliaString); } catch { /* ignore */ }
    // Minimal parser for patterns like: (a = 1, b = [1,2], c = [ [..]; [..] ])
    // We will transform into JSON by replacing Julia syntax tokens carefully.
    let s = juliaString.trim();
    if (!s || s === '()') return {};
    // Replace tuple parens with braces
    s = s.replace(/^\(/, '{').replace(/\)$/, '}');
    // Replace "key =" with ""key":"
    s = s.replace(/(\w+)\s*=\s*/g, '"$1": ');
    // Replace Julia matrix [a b; c d] with array of arrays [[a,b],[c,d]] (best-effort)
    s = s.replace(/\[\s*([\s\S]*?)\s*\]/g, (match, content) => {
      // If it contains semicolons, treat as rows
      if (content.includes(';')) {
        const rows = content.split(';').map((row: string) => `[${row.trim().replace(/\s+/g, ', ')}]`);
        return `[${rows.join(',')}]`;
      }
      // Otherwise keep commas
      return `[${content.replace(/\s+/g, ' ')}]`;
    });
    // Remove trailing commas if any
    s = s.replace(/,\s*}/g, '}');
    return JSON.parse(s);
  } catch {
    return {};
  }
}

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

const handleGenerateStandalone = () => {
  try {
    // Build JSON-first payloads similar to runModel
    const dataPayload = dataStore.inputMode === 'json' ? JSON.parse(dataStore.dataString || '{}') : JSON.parse(JSON.stringify(juliaTupleToJsonObject(dataStore.dataString)));
    const initsPayload = dataStore.inputMode === 'json' ? JSON.parse(dataStore.initsString || '{}') : JSON.parse(JSON.stringify(juliaTupleToJsonObject(dataStore.initsString)));

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

    // Update files list (replace existing standalone.jl if present)
    const files = executionStore.generatedFiles.filter(f => f.name !== 'standalone.jl');
    files.unshift({ name: 'standalone.jl', content: script });
    executionStore.generatedFiles = files;
    executionStore.executionLogs.push('Generated standalone Julia script (frontend).');

    // Focus Execution panel and open right sidebar
    uiStore.setActiveRightTab('connection');
    isRightSidebarOpen.value = true;

    // Trigger immediate download
    const blob = new Blob([script], { type: 'text/x-julia' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${activeGraphName.value || 'model'}-standalone.jl`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  } catch (err) {
    executionStore.executionLogs.push(`Failed to generate standalone script: ${(err as Error).message}`);
  }
};
</script>

<template>
  <div class="main-layout">
    <TheNavbar :project-name="currentProjectName" :active-graph-name="activeGraphName" :is-grid-enabled="isGridEnabled"
      @update:is-grid-enabled="isGridEnabled = $event" :grid-size="gridSize" @update:grid-size="gridSize = $event"
      :current-mode="currentMode" @update:current-mode="currentMode = $event" :current-node-type="currentNodeType"
      @update:current-node-type="currentNodeType = $event" :is-left-sidebar-open="isLeftSidebarOpen"
      :is-right-sidebar-open="isRightSidebarOpen" @toggle-left-sidebar="uiStore.toggleLeftSidebar"
      @toggle-right-sidebar="uiStore.toggleRightSidebar" @new-project="showNewProjectModal = true"
      @new-graph="showNewGraphModal = true" @save-current-graph="saveCurrentGraph"
      @open-about-modal="showAboutModal = true" @export-json="handleExportJson" @open-export-modal="openExportModal"
      @apply-layout="handleGraphLayout" @load-example="handleLoadExample" @validate-model="validateGraph"
      :is-model-valid="isModelValid" @show-validation-issues="showValidationModal = true"
      @connect-to-backend-url="connectToBackendUrl" @run-model="runModel" @abort-run="abortRun" @generate-standalone="handleGenerateStandalone" />

    <div class="content-area">
      <aside class="left-sidebar" :style="leftSidebarStyle">
        <div class="vertical-tabs-container">
          <button :class="{ active: activeLeftTab === 'project' }" @click="uiStore.handleLeftTabClick('project')"
            title="Project Manager">
            <i class="fas fa-folder"></i> <span v-show="isLeftSidebarOpen">Project</span>
          </button>
          <button :class="{ active: activeLeftTab === 'palette' }" @click="uiStore.handleLeftTabClick('palette')"
            title="Node Palette">
            <i class="fas fa-shapes"></i> <span v-show="isLeftSidebarOpen">Palette</span>
          </button>
          <button :class="{ active: activeLeftTab === 'data' }" @click="uiStore.handleLeftTabClick('data')"
            title="Data Input">
            <i class="fas fa-database"></i> <span v-show="isLeftSidebarOpen">Data</span>
          </button>
          <button :class="{ active: activeLeftTab === 'settings' }" @click="uiStore.handleLeftTabClick('settings')"
            title="Execution Settings">
            <i class="fas fa-cog"></i> <span v-show="isLeftSidebarOpen">Settings</span>
          </button>
        </div>
        <div class="left-sidebar-content" :style="leftSidebarContentStyle">
          <div v-show="activeLeftTab === 'project'">
            <ProjectManager @new-project="showNewProjectModal = true" @new-graph="showNewGraphModal = true" />
          </div>
          <div v-show="activeLeftTab === 'palette'">
            <NodePalette @select-palette-item="handlePaletteSelection" />
          </div>
          <div v-show="activeLeftTab === 'data'" class="fill-height">
            <DataInputPanel :is-active="activeLeftTab === 'data'" />
          </div>
          <div v-show="activeLeftTab === 'settings'" class="fill-height">
            <ExecutionSettingsPanel />
          </div>
        </div>
      </aside>

      <div class="resizer resizer-left" @mousedown.prevent="startResizeLeft"></div>

      <main class="graph-editor-wrapper">
        <GraphEditor :is-grid-enabled="isGridEnabled" :grid-size="gridSize" :current-mode="currentMode"
          :elements="elements" :current-node-type="currentNodeType" :validation-errors="validationErrors"
          @update:current-mode="currentMode = $event" @update:current-node-type="currentNodeType = $event"
          @element-selected="handleElementSelected" />
      </main>

      <div class="resizer resizer-right" @mousedown.prevent="startResizeRight"></div>

      <aside class="right-sidebar" :style="rightSidebarStyle">
        <div class="tabs-header">
          <div class="tab-buttons">
            <button :class="{ active: uiStore.activeRightTab === 'properties' }"
              @click="uiStore.setActiveRightTab('properties')">Properties</button>
            <button :class="{ active: uiStore.activeRightTab === 'code' }"
              @click="uiStore.setActiveRightTab('code')">Code</button>
            <button :class="{ active: uiStore.activeRightTab === 'json' }"
              @click="uiStore.setActiveRightTab('json')">JSON</button>
            <button :class="{ active: uiStore.activeRightTab === 'connection' }"
              @click="uiStore.setActiveRightTab('connection')">Connection</button>
          </div>
          <button @click="uiStore.toggleRightTabPinned()" class="pin-button"
            :class="{ 'pinned': uiStore.isRightTabPinned }" title="Pin Tab">
            <i class="fas fa-thumbtack"></i>
          </button>
        </div>
        <div class="tabs-content">
          <div v-show="uiStore.activeRightTab === 'properties'" class="tab-pane">
            <NodePropertiesPanel :selected-element="selectedElement" :validation-errors="validationErrors"
              @update-element="handleUpdateElement" @delete-element="handleDeleteElement" />
          </div>
          <div v-show="uiStore.activeRightTab === 'code'" class="tab-pane fill-height">
            <CodePreviewPanel :is-active="uiStore.activeRightTab === 'code'" />
          </div>
          <div v-show="uiStore.activeRightTab === 'json'" class="tab-pane fill-height">
            <JsonEditorPanel :is-active="uiStore.activeRightTab === 'json'" />
          </div>
          <div v-show="uiStore.activeRightTab === 'connection'" class="tab-pane fill-height">
            <ExecutionPanel />
          </div>
        </div>
      </aside>
    </div>

    <!-- Modals -->
    <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
      <template #header>
        <h3>Create New Project</h3>
      </template>
      <template #body>
        <div class="modal-body-content">
          <label for="new-project-name">Project Name:</label>
          <BaseInput id="new-project-name" v-model="newProjectName" placeholder="Enter project name"
            @keyup.enter="createNewProject" />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showNewProjectModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewProject" type="primary">Create</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
      <template #header>
        <h3>Create New Graph</h3>
      </template>
      <template #body>
        <div class="modal-body-content">
          <label for="new-graph-name">Graph Name:</label>
          <BaseInput id="new-graph-name" v-model="newGraphName" placeholder="Enter graph name"
            @keyup.enter="createNewGraph" />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showNewGraphModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewGraph" type="primary">Create</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showConnectModal" @close="showConnectModal = false">
      <template #header>
        <h3>Connect to Backend</h3>
      </template>
      <template #body>
        <div class="modal-body-content">
          <label for="backend-url">Backend Server URL:</label>
          <BaseInput id="backend-url" v-model="tempBackendUrl" placeholder="http://localhost:8081"
            @keyup.enter="connectToBackend" />
          <small>The URL of your running JuliaBUGS backend server.</small>
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showConnectModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="connectToBackend" type="primary" :disabled="isConnecting">
          <span v-if="isConnecting">Connecting...</span>
          <span v-else>Connect</span>
        </BaseButton>
      </template>
    </BaseModal>

    <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
    <ExportModal :is-open="showExportModal" :export-type="currentExportType" @close="showExportModal = false"
      @confirm-export="handleConfirmExport" />
    <ValidationIssuesModal :is-open="showValidationModal" :validation-errors="validationErrors" :elements="elements"
      @close="showValidationModal = false" @select-node="handleSelectNodeFromModal" />
  </div>
</template>

<style scoped>
.main-layout {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

.content-area {
  display: flex;
  flex-grow: 1;
  overflow: hidden;
}

.left-sidebar {
  display: flex;
  background-color: var(--color-background-soft);
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  flex-shrink: 0;
}

.vertical-tabs-container {
  display: flex;
  flex-direction: column;
  width: var(--vertical-tab-width);
  border-right: 1px solid var(--color-border-light);
  background-color: var(--color-background-dark);
  padding-top: 10px;
  flex-shrink: 0;
}

.vertical-tabs-container button {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  width: 100%;
  padding: 10px 0;
  border: none;
  background-color: transparent;
  color: var(--color-text-light);
  font-size: 0.75em;
  font-weight: 500;
  transition: all 0.2s ease;
  gap: 5px;
  cursor: pointer;
  white-space: nowrap;
}

.vertical-tabs-container button i {
  font-size: 1.3em;
  color: var(--color-secondary);
  transition: color 0.2s ease;
}

.vertical-tabs-container button:hover {
  background-color: var(--color-primary-hover);
  color: white;
}

.vertical-tabs-container button:hover i {
  color: white;
}

.vertical-tabs-container button.active {
  background-color: var(--color-primary);
  color: white;
  border-left: 2px solid white;
}

.vertical-tabs-container button.active i {
  color: white;
}

.left-sidebar-content {
  flex-grow: 1;
  overflow-y: auto;
  padding: 15px;
  -webkit-overflow-scrolling: touch;
  transition: opacity 0.3s ease-in-out;
  box-sizing: border-box;
}

.left-sidebar-content>.fill-height {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.right-sidebar {
  display: flex;
  flex-direction: column;
  background-color: var(--color-background-soft);
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  flex-shrink: 0;
}

.tabs-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--color-border-light);
  flex-shrink: 0;
  padding-right: 10px;
}

.tab-buttons {
  display: flex;
  flex-grow: 1;
}

.tab-buttons button {
  flex: 1;
  padding: 10px 15px;
  border: none;
  background-color: transparent;
  border-bottom: 2px solid transparent;
  font-weight: 500;
  color: var(--color-text);
  transition: all 0.2s ease;
  white-space: nowrap;
}

.tab-buttons button:hover {
  background-color: var(--color-background-mute);
}

.tab-buttons button.active {
  color: var(--color-primary);
  border-bottom-color: var(--color-primary);
  background-color: var(--color-background-soft);
}

.pin-button {
  background: none;
  border: none;
  color: var(--color-secondary);
  cursor: pointer;
  padding: 5px;
  font-size: 0.9em;
  border-radius: 4px;
  transition: all 0.2s ease;
}

.pin-button:hover {
  background-color: var(--color-background-mute);
}

.pin-button.pinned {
  color: var(--color-primary);
  transform: rotate(45deg);
}

.tabs-content {
  flex-grow: 1;
  overflow-y: auto;
  position: relative;
  min-height: 0;
}

.tab-pane {
  background-color: var(--color-background-soft);
}

.tab-pane.fill-height {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.graph-editor-wrapper {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  position: relative;
  background-color: var(--color-background-mute);
  min-width: 0;
}

.resizer {
  flex-shrink: 0;
  width: 2px;
  background-color: transparent;
  cursor: col-resize;
  transition: background-color 0.2s ease;
}

.resizer:hover,
.resizer-left:active,
.resizer-right:active {
  background-color: var(--color-primary);
}

.resizer-left {
  border-right: 1px solid var(--color-border);
}

.resizer-right {
  border-left: 1px solid var(--color-border);
}

.modal-body-content {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.modal-body-content label {
  font-weight: 500;
}

.modal-body-content small {
  display: block;
  margin-top: 4px;
  color: var(--color-secondary);
}
</style>
