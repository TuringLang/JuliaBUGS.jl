<script setup lang="ts">
import { ref, onMounted, watch, nextTick, computed } from 'vue';
import { storeToRefs } from 'pinia';
import type { LayoutOptions } from 'cytoscape';
import GraphEditor from '../canvas/GraphEditor.vue';
import FloatingBottomToolbar from '../canvas/FloatingBottomToolbar.vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
import TheNavbar from './TheNavbar.vue';
import LeftSidebar from './LeftSidebar.vue';
import RightSidebar from './RightSidebar.vue';
import AboutModal from './AboutModal.vue';
import ExportModal from './ExportModal.vue';
import ValidationIssuesModal from './ValidationIssuesModal.vue';
import DebugPanel from '../common/DebugPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useProjectStore } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import { useDataStore } from '../../stores/dataStore';
import { useExecutionStore } from '../../stores/executionStore';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGraphValidator } from '../../composables/useGraphValidator';
import { useBugsCodeGenerator, generateStandaloneScript } from '../../composables/useBugsCodeGenerator';
import type { GraphElement, NodeType, ExampleModel } from '../../types';
import type { GeneratedFile } from '../../stores/executionStore';

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
const { getCyInstance, getUndoRedoInstance } = useGraphInstance();
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData);
const { backendUrl, isConnected, isConnecting, isExecuting, samplerSettings } = storeToRefs(executionStore);
const { isLeftSidebarOpen, isRightSidebarOpen, canvasGridStyle, isCodePanelOpen, isDarkMode } = storeToRefs(uiStore);

const currentMode = ref<string>('select');
const currentNodeType = ref<NodeType>('stochastic');
const isGridEnabled = ref(true);
const gridSize = ref(20);
const showZoomControls = ref(true);

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

// Computed property for validation status
const isModelValid = computed(() => validationErrors.value.size === 0);

// Pinned Graph Title Computation
const pinnedGraphTitle = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return null;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return graph ? graph.name : null;
});

// Dark Mode Handling
watch(isDarkMode, (val) => {
  const element = document.querySelector('html');
  if (val) element?.classList.add('dark-mode');
  else element?.classList.remove('dark-mode');
}, { immediate: true });

let currentRunController: AbortController | null = null;
let abortedByUser = false;

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
  validateGraph();
  
  // Initial fit on reload
  setTimeout(() => {
      if (graphStore.currentGraphId) {
          const cy = getCyInstance(graphStore.currentGraphId);
          cy?.resize();
          cy?.fit(undefined, 50);
      }
  }, 500);
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

// Initialize Code Panel Position if needed
watch([isCodePanelOpen, () => graphStore.currentGraphId], ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
        const graph = projectStore.currentProject.graphs.find(g => g.id === graphId);
        if (graph) {
            const hasValidPosition = graph.codePanelX !== undefined && graph.codePanelY !== undefined;
            // If no position saved, OR if it's suspiciously at (0,0) or default (100,100) which might collide
            if (!hasValidPosition || (graph.codePanelX === 100 && graph.codePanelY === 100)) {
                const viewportW = window.innerWidth;
                const rightSidebarW = 340; // Approx with margin
                const panelW = graph.codePanelWidth || 400;
                const panelH = graph.codePanelHeight || 400;
                const topMargin = 80;
                
                // Position to the right, clearing the right sidebar if possible
                let targetX = viewportW - rightSidebarW - panelW - 20;
                // If too narrow, just center it
                if (targetX < 100) targetX = (viewportW - panelW) / 2;
                
                projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
                    codePanelX: targetX,
                    codePanelY: topMargin,
                    codePanelWidth: panelW,
                    codePanelHeight: panelH
                });
            }
        }
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
    // Ensure centering even for preset
    if (layoutName === 'preset') {
        cy.fit(undefined, 50);
    }
    handleLayoutUpdated(layoutName);
};

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element;
  if (element) {
    // Element selected: Open sidebar if not already open
    if (!uiStore.isRightTabPinned) {
      uiStore.setActiveRightTab('properties');
      if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true;
    }
  } else {
    // Element deselected (background click): Close sidebar if not pinned
    if (!uiStore.isRightTabPinned && isRightSidebarOpen.value) {
      isRightSidebarOpen.value = false;
    }
  }
};

const handleSelectNodeFromModal = (nodeId: string) => {
    const targetNode = elements.value.find(el => el.id === nodeId);
    if (targetNode) {
        handleElementSelected(targetNode);
        graphStore.setElementToFocus(targetNode);
        const cy = getCyInstance(graphStore.currentGraphId!);
        if (cy) {
            cy.animate({
                fit: { eles: cy.getElementById(nodeId), padding: 50 },
                duration: 500
            });
        }
    }
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

const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
  if (!graphStore.currentGraphId) return;
  currentExportType.value = format;
  showExportModal.value = true;
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

    const result: any = await response.json();
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

const abortRun = () => {
  if (currentRunController) {
    abortedByUser = true;
    currentRunController.abort();
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
    if (!isRightSidebarOpen.value) uiStore.toggleRightSidebar();
    executionStore.setExecutionPanelTab('files');
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

// --- Zoom Controls Handlers ---
const handleZoomIn = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) {
            const currentZoom = cy.zoom();
            cy.animate({ zoom: { level: currentZoom * 1.2, position: { x: cy.width()/2, y: cy.height()/2 } }, duration: 200 });
        }
    }
};

const handleZoomOut = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) {
            const currentZoom = cy.zoom();
            cy.animate({ zoom: { level: currentZoom * 0.8, position: { x: cy.width()/2, y: cy.height()/2 } }, duration: 200 });
        }
    }
};

const handleFit = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) {
            cy.animate({ fit: { eles: cy.elements(), padding: 50 }, duration: 300 });
        }
    }
};

const handleUndo = () => {
    if (graphStore.currentGraphId) {
        const ur = getUndoRedoInstance(graphStore.currentGraphId);
        if (ur) ur.undo();
    }
};

const handleRedo = () => {
    if (graphStore.currentGraphId) {
        const ur = getUndoRedoInstance(graphStore.currentGraphId);
        if (ur) ur.redo();
    }
};

// --- Code Export ---
const downloadString = (content: string, filename: string) => {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
};

const handleExportBugs = () => {
    downloadString(generatedCode.value, 'model.bugs');
};

const handleExportStandalone = () => {
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
    downloadString(script, 'standalone.jl');
};

// --- Draggable Code Panel Logic ---
const currentGraph = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return null;
    return projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
});

const codePanelPosition = computed(() => {
    if (!currentGraph.value) return { x: 100, y: 100, width: 400, height: 400 };
    return {
        x: currentGraph.value.codePanelX ?? 100,
        y: currentGraph.value.codePanelY ?? 100,
        width: currentGraph.value.codePanelWidth ?? 400,
        height: currentGraph.value.codePanelHeight ?? 400
    };
});

const dragCodeState = ref<{isDragging: boolean, startX: number, startY: number, initialLeft: number, initialTop: number} | null>(null);

const startDragCode = (e: MouseEvent) => {
    dragCodeState.value = {
        isDragging: true,
        startX: e.clientX,
        startY: e.clientY,
        initialLeft: codePanelPosition.value.x,
        initialTop: codePanelPosition.value.y
    };
    window.addEventListener('mousemove', onDragCode);
    window.addEventListener('mouseup', stopDragCode);
};

const onDragCode = (e: MouseEvent) => {
    if (!dragCodeState.value || !currentGraph.value) return;
    const dx = e.clientX - dragCodeState.value.startX;
    const dy = e.clientY - dragCodeState.value.startY;
    if (projectStore.currentProject) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, currentGraph.value.id, {
            codePanelX: dragCodeState.value.initialLeft + dx,
            codePanelY: dragCodeState.value.initialTop + dy
        }, false);
    }
};

const stopDragCode = () => {
    if (projectStore.currentProject) projectStore.saveProjects();
    dragCodeState.value = null;
    window.removeEventListener('mousemove', onDragCode);
    window.removeEventListener('mouseup', stopDragCode);
};

const startResizeCode = (e: MouseEvent) => {
    const g = currentGraph.value;
    if (!g) return;
    e.stopPropagation();
    const startX = e.clientX;
    const startY = e.clientY;
    const startW = codePanelPosition.value.width;
    const startH = codePanelPosition.value.height;

    const onResize = (ev: MouseEvent) => {
        const dx = ev.clientX - startX;
        const dy = ev.clientY - startY;
        if (projectStore.currentProject && currentGraph.value) {
            projectStore.updateGraphLayout(projectStore.currentProject.id, currentGraph.value.id, {
                codePanelWidth: Math.max(300, startW + dx),
                codePanelHeight: Math.max(200, startH + dy)
            }, false);
        }
    };

    const stopResize = () => {
        if (projectStore.currentProject) projectStore.saveProjects();
        window.removeEventListener('mousemove', onResize);
        window.removeEventListener('mouseup', stopResize);
    };

    window.addEventListener('mousemove', onResize);
    window.addEventListener('mouseup', stopResize);
};

const toggleCodePanel = () => {
    uiStore.toggleCodePanel();
};

const toggleDarkMode = () => {
    uiStore.toggleDarkMode();
};

</script>

<template>
  <div class="app-layout">
    <TheNavbar
        :project-name="projectStore.currentProject?.name || null"
        :active-graph-name="pinnedGraphTitle"
        :is-grid-enabled="isGridEnabled"
        :grid-size="gridSize"
        :current-mode="currentMode"
        :current-node-type="currentNodeType"
        :is-left-sidebar-open="isLeftSidebarOpen"
        :is-right-sidebar-open="isRightSidebarOpen"
        :is-model-valid="isModelValid"
        :show-debug-panel="showDebugPanel"
        :show-zoom-controls="showZoomControls"
        @update:is-grid-enabled="isGridEnabled = $event"
        @update:grid-size="gridSize = $event"
        @update:current-mode="currentMode = $event"
        @update:current-node-type="currentNodeType = $event"
        @update:show-debug-panel="showDebugPanel = $event"
        @update:show-zoom-controls="showZoomControls = $event"
        @new-project="showNewProjectModal = true"
        @new-graph="showNewGraphModal = true"
        @toggle-left-sidebar="uiStore.toggleLeftSidebar()"
        @toggle-right-sidebar="uiStore.toggleRightSidebar()"
        @open-about-modal="showAboutModal = true"
        @open-export-modal="openExportModal"
        @export-json="handleExportJson"
        @apply-layout="handleGraphLayout"
        @load-example="handleLoadExample"
        @show-validation-issues="showValidationModal = true"
        @connect-to-backend-url="tempBackendUrl = $event; connectToBackend()"
        @run-model="runModel"
        @abort-run="abortRun"
        @generate-standalone="handleGenerateStandalone"
        @toggle-code-panel="toggleCodePanel"
    />

    <main class="canvas-area">
        <div v-if="graphStore.currentGraphId" class="single-graph-container">
            <GraphEditor 
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
            />
            
            <FloatingBottomToolbar 
                :current-mode="currentMode"
                :current-node-type="currentNodeType"
                :show-code-panel="isCodePanelOpen"
                @update:current-mode="currentMode = $event"
                @update:current-node-type="currentNodeType = $event"
                @undo="handleUndo"
                @redo="handleRedo"
                @zoom-in="handleZoomIn"
                @zoom-out="handleZoomOut"
                @fit="handleFit"
                @layout-graph="handleGraphLayout"
                @toggle-code-panel="toggleCodePanel"
                @export-bugs="handleExportBugs"
                @export-standalone="handleExportStandalone"
            />

            <!-- Draggable Code Panel -->
            <div v-if="isCodePanelOpen" 
                 class="code-panel-card glass-panel"
                 :style="{
                    left: `${codePanelPosition.x}px`,
                    top: `${codePanelPosition.y}px`,
                    width: `${codePanelPosition.width}px`,
                    height: `${codePanelPosition.height}px`
                 }"
            >
                <div class="graph-header code-header" @mousedown="startDragCode">
                    <span class="graph-title"><i class="fas fa-code"></i> BUGS Code Preview</span>
                    <button class="close-btn" @click="toggleCodePanel"><i class="fas fa-times"></i></button>
                </div>
                <div class="code-content">
                    <CodePreviewPanel :is-active="true" :graph-id="graphStore.currentGraphId" />
                </div>
                <div class="resize-handle" @mousedown.stop="startResizeCode">
                    <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
                </div>
            </div>
        </div>
        <div v-else class="empty-workspace">
            <p>Select or create a graph to start editing.</p>
            <BaseButton @click="showNewGraphModal = true" type="primary">Create New Graph</BaseButton>
        </div>
    </main>

    <!-- Logo Button (Collapsed Left Sidebar) -->
    <div class="sidebar-toggle-logo glass-panel" :class="{ hidden: isLeftSidebarOpen }">
       <div class="flex-grow cursor-pointer flex items-center" @click="uiStore.toggleLeftSidebar" title="Open Menu">
           <span class="logo-text-minimized">
               {{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}
           </span>
       </div>
       
       <div class="flex items-center gap-1 ml-2">
           <button @click.stop="toggleDarkMode" class="theme-toggle-header" :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'">
               <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
           </button>
           <div class="cursor-pointer flex items-center ml-1" @click="uiStore.toggleLeftSidebar" title="Open Menu">
               <svg data-v-ae240f47="" width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path data-v-ae240f47="" fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
           </div>
       </div>
    </div>

    <!-- Right Sidebar Toggle (Collapsed with Status Controls) -->
    <div class="sidebar-toggle-logo right glass-panel" :class="{ hidden: isRightSidebarOpen }">
       <div class="flex-grow cursor-pointer flex items-center" @click="uiStore.toggleRightSidebar" title="Open Inspector">
           <span class="logo-text-minimized">Inspector</span>
       </div>
       
       <div class="flex items-center gap-1 mr-2">
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

       <div class="cursor-pointer flex items-center" @click="uiStore.toggleRightSidebar" title="Open Inspector">
           <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
       </div>
    </div>

    <LeftSidebar 
        :active-accordion-tabs="activeAccordionTabs"
        :project-name="projectStore.currentProject?.name || null"
        :pinned-graph-title="pinnedGraphTitle"
        :is-grid-enabled="isGridEnabled"
        :grid-size="gridSize"
        :show-zoom-controls="showZoomControls"
        :show-debug-panel="showDebugPanel"
        @toggle-left-sidebar="uiStore.toggleLeftSidebar"
        @new-project="showNewProjectModal = true"
        @new-graph="showNewGraphModal = true"
        @update:currentMode="currentMode = $event"
        @update:currentNodeType="currentNodeType = $event"
        @update:isGridEnabled="isGridEnabled = $event"
        @update:gridSize="gridSize = $event"
        @update:showZoomControls="showZoomControls = $event"
        @update:showDebugPanel="showDebugPanel = $event"
        @load-example="handleLoadExample"
        @open-export-modal="openExportModal"
        @export-json="handleExportJson"
        @connect-to-backend-url="tempBackendUrl = $event; connectToBackend()"
        @generate-standalone="handleGenerateStandalone"
        @open-about-modal="showAboutModal = true"
        @toggle-dark-mode="toggleDarkMode"
    />

    <RightSidebar 
        :selected-element="selectedElement"
        :validation-errors="validationErrors"
        :is-model-valid="isModelValid"
        @toggle-right-sidebar="uiStore.toggleRightSidebar"
        @update-element="updateElement"
        @delete-element="deleteElement"
        @show-validation-issues="showValidationModal = true"
    />

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
  height: 100%;
  z-index: 0;
  display: flex;
  justify-content: center;
  align-items: center;
}

.single-graph-container {
    width: 100%;
    height: 100%;
    position: relative;
}

.empty-workspace {
    text-align: center;
    color: var(--theme-text-secondary);
}

.empty-workspace p {
    margin-bottom: 1rem;
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

.toggle-icon {
    color: var(--theme-text-secondary);
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

.backend-status { margin-right: 0; }
.backend-status.connected { color: var(--theme-success); }
.backend-status.disconnected { color: var(--theme-danger); }

.validation-status { font-size: 1.1em; margin: 0 5px; }
.validation-status.valid { color: var(--theme-success); }
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

/* Draggable Code Panel Styling */
.code-panel-card {
  position: absolute;
  background-color: var(--theme-bg-panel);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-md);
  display: flex;
  flex-direction: column;
  border: 1px solid var(--theme-border);
  overflow: visible; 
  transition: box-shadow 0.2s;
  z-index: 100; 
}

.graph-header {
  height: 36px;
  background-color: var(--theme-bg-hover);
  border-bottom: 1px solid var(--theme-border);
  display: flex;
  align-items: center;
  padding: 0 10px;
  cursor: move;
  user-select: none;
  justify-content: space-between;
  border-top-left-radius: var(--radius-md);
  border-top-right-radius: var(--radius-md);
}

.graph-title {
  font-weight: 600;
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--theme-text-primary);
  display: flex;
  align-items: center;
  gap: 6px;
}

.code-content {
  flex: 1;
  position: relative;
  overflow: hidden;
  background-color: var(--theme-bg-panel);
  display: flex;
  flex-direction: column;
  border-bottom-left-radius: var(--radius-md);
  border-bottom-right-radius: var(--radius-md);
}

.code-content :deep(.code-preview-panel) {
    height: 100%;
    padding: 0;
}
.code-content :deep(.header-section) {
    display: none; 
}
.code-content :deep(.editor-wrapper) {
    border-radius: 0;
}

.resize-handle {
  position: absolute;
  bottom: 0;
  right: 0;
  width: 16px;
  height: 16px;
  cursor: nwse-resize;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--theme-text-secondary);
  font-size: 9px;
  z-index: 20;
  background: var(--theme-bg-hover);
  border-top-left-radius: 4px;
  border-bottom-right-radius: var(--radius-md);
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
</style>