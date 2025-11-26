<script setup lang="ts">
import { ref, onMounted, watch, computed } from 'vue';
import { storeToRefs } from 'pinia';
import type { LayoutOptions, Core } from 'cytoscape';
import GraphEditor from '../canvas/GraphEditor.vue';
import FloatingBottomToolbar from '../canvas/FloatingBottomToolbar.vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
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

interface RunResponse {
  logs?: string[];
  error?: string;
  results?: Record<string, unknown>[];
  summary?: Record<string, unknown>[];
  quantiles?: Record<string, unknown>[];
  files?: { name: string; content: string | object }[];
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

  // Mobile optimizations: hide zoom controls by default on small screens
  if (window.innerWidth < 768) {
      showZoomControls.value = false;
  }
});

// Initialize Code Panel Position if needed
watch([isCodePanelOpen, () => graphStore.currentGraphId], ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
        const graph = projectStore.currentProject.graphs.find(g => g.id === graphId);
        if (graph) {
            const hasValidPosition = graph.codePanelX !== undefined && graph.codePanelY !== undefined;
            if (!hasValidPosition || (graph.codePanelX === 100 && graph.codePanelY === 100)) {
                const viewportW = window.innerWidth;
                const rightSidebarW = 340; // Approx with margin
                const panelW = graph.codePanelWidth || 400;
                const panelH = graph.codePanelHeight || 400;
                const topMargin = 80;
                
                // Position to the right, clearing the right sidebar if possible
                let targetX = viewportW - rightSidebarW - panelW - 20;
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

const smartFit = (cy: Core, animate: boolean = true) => {
    const eles = cy.elements();
    if (eles.length === 0) return;
    
    const padding = 50;
    const w = cy.width();
    const h = cy.height();
    const bb = eles.boundingBox();
    
    if (bb.w === 0 || bb.h === 0) return;

    // Calculate zoom to fit
    const zoomX = (w - 2 * padding) / bb.w;
    const zoomY = (h - 2 * padding) / bb.h;
    let targetZoom = Math.min(zoomX, zoomY);
    
    // Cap zoom to avoid overly large graph on big screens
    targetZoom = Math.min(targetZoom, 0.8);
    
    // Calculate center pan for the target zoom
    const targetPan = {
        x: (w - targetZoom * (bb.x1 + bb.x2)) / 2,
        y: (h - targetZoom * (bb.y1 + bb.y2)) / 2
    };

    if (animate) {
        cy.animate({
            zoom: targetZoom,
            pan: targetPan,
            duration: 500,
            easing: 'ease-in-out-cubic'
        });
    } else {
        cy.viewport({ zoom: targetZoom, pan: targetPan });
    }
};

const handleGraphLayout = (layoutName: string) => {
    const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null;
    if (!cy) return;
    
    /* eslint-disable @typescript-eslint/no-explicit-any */
    const layoutOptionsMap: Record<string, LayoutOptions> = {
        dagre: { name: 'dagre', animate: true, animationDuration: 500, fit: false, padding: 50 } as any,
        fcose: { name: 'fcose', animate: true, animationDuration: 500, fit: false, padding: 50, randomize: false, quality: 'proof' } as any,
        cola: { name: 'cola', animate: true, fit: false, padding: 50, refresh: 1, avoidOverlap: true, infinite: false, centerGraph: true, flow: { axis: 'y', minSeparation: 30 }, handleDisconnected: false, randomize: false } as any,
        klay: { name: 'klay', animate: true, animationDuration: 500, fit: false, padding: 50, klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' } } as any,
        preset: { name: 'preset', fit: false, padding: 50 } as any
    };
    /* eslint-enable @typescript-eslint/no-explicit-any */
    
    const options = layoutOptionsMap[layoutName] || layoutOptionsMap.preset;
    
    cy.one('layoutstop', () => {
        smartFit(cy, true);
    });
    
    cy.layout(options).run();
    handleLayoutUpdated(layoutName);
};

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element;
  if (element) {
    if (!uiStore.isRightTabPinned) {
      uiStore.setActiveRightTab('properties');
      const isMobile = window.innerWidth < 768;
      if (isMobile && isLeftSidebarOpen.value) {
          isLeftSidebarOpen.value = false;
      }
      if (!isRightSidebarOpen.value) isRightSidebarOpen.value = true;
    }
  } else {
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
  // Explicitly cast to Core, assuming custom method svg() exists via declaration merging
  const cy = (graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null) as Core | null;
  if (!cy || !currentExportType.value) return;
  const fileName = `graph.${currentExportType.value}`;
  try {
    let blob: Blob;
    if (currentExportType.value === 'svg') {
      const svgOptions = { bg: options.bg, full: options.full, scale: options.scale };
      blob = new Blob([cy.svg(svgOptions)], { type: 'image/svg+xml;charset=utf-8' });
    } else {
      // Typings should support png/jpg on Core
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

    const result = await response.json() as RunResponse;
    executionStore.executionLogs = result.logs ?? [];
    if (!response.ok) throw new Error(result.error || `HTTP error! status: ${response.status}`);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    executionStore.executionResults = (result.results ?? result.summary ?? null) as any;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    executionStore.summaryResults = (result.summary ?? null) as any;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    executionStore.quantileResults = (result.quantiles ?? null) as any;

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
    const backendFiles = (result.files ?? []).filter((file: {name: string}) => file.name !== 'standalone.jl').map((file: {name: string; content: string | object}) => {
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

const handleLoadExample = async (exampleKey: string) => {
  if (!projectStore.currentProjectId) return;
  try {
    const baseUrl = import.meta.env.BASE_URL;
    const modelResponse = await fetch(`${baseUrl}examples/${exampleKey}/model.json`);
    if (!modelResponse.ok) throw new Error(`Could not fetch example model: ${modelResponse.statusText}`);
    const modelData: ExampleModel = await modelResponse.json();
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId, modelData.name);
    if (!newGraphMeta) return;
    
    projectStore.updateGraphLayout(projectStore.currentProject!.id, newGraphMeta.id, {});
    graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON);
    
    // Force preset layout initially with the new smartFit flow
    graphStore.updateGraphLayout(newGraphMeta.id, 'preset');

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
    const isMobile = window.innerWidth < 768;
    if (!isLeftSidebarOpen.value && isMobile) {
        isRightSidebarOpen.value = false;
    }
    isLeftSidebarOpen.value = !isLeftSidebarOpen.value;
};

const toggleRightSidebar = () => {
    const isMobile = window.innerWidth < 768;
    if (!isRightSidebarOpen.value && isMobile) {
        isLeftSidebarOpen.value = false;
    }
    isRightSidebarOpen.value = !isRightSidebarOpen.value;
};

const abortRun = () => {
  if (currentRunController) {
    abortedByUser = true;
    currentRunController.abort();
  }
};

// Helper methods for graph actions
const handleUndo = () => {
    if (graphStore.currentGraphId) {
        getUndoRedoInstance(graphStore.currentGraphId)?.undo();
    }
};

const handleRedo = () => {
    if (graphStore.currentGraphId) {
        getUndoRedoInstance(graphStore.currentGraphId)?.redo();
    }
};

const handleZoomIn = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) cy.zoom(cy.zoom() * 1.2);
    }
};

const handleZoomOut = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) cy.zoom(cy.zoom() * 0.8);
    }
};

const handleFit = () => {
    if (graphStore.currentGraphId) {
        const cy = getCyInstance(graphStore.currentGraphId);
        if (cy) smartFit(cy, true);
    }
};

// Code Panel Drag Logic (Touch)
const codePanelRef = ref<HTMLElement | null>(null);
const isDraggingCode = ref(false);
const dragStartCode = ref({ x: 0, y: 0 });
const initialPanelPos = ref({ x: 0, y: 0 });

const startDragCodeTouch = (e: TouchEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingCode.value = true;
    const touch = e.touches[0];
    dragStartCode.value = { x: touch.clientX, y: touch.clientY };
    initialPanelPos.value = { 
        x: graph.codePanelX ?? (window.innerWidth - 420), 
        y: graph.codePanelY ?? 80 
    };
    
    window.addEventListener('touchmove', onDragCodeTouch, { passive: false });
    window.addEventListener('touchend', stopDragCodeTouch);
};

const onDragCodeTouch = (e: TouchEvent) => {
    if (!isDraggingCode.value) return;
    e.preventDefault(); // Prevent scrolling while dragging panel
    const touch = e.touches[0];
    const dx = touch.clientX - dragStartCode.value.x;
    const dy = touch.clientY - dragStartCode.value.y;
    
    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            codePanelX: initialPanelPos.value.x + dx,
            codePanelY: initialPanelPos.value.y + dy
        }, false);
    }
};

const stopDragCodeTouch = () => {
    isDraggingCode.value = false;
    window.removeEventListener('touchmove', onDragCodeTouch);
    window.removeEventListener('touchend', stopDragCodeTouch);
    projectStore.saveProjects();
};

// Code Panel Drag Logic (Mouse)
const startDragCode = (e: MouseEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingCode.value = true;
    dragStartCode.value = { x: e.clientX, y: e.clientY };
    initialPanelPos.value = { 
        x: graph.codePanelX ?? (window.innerWidth - 420), 
        y: graph.codePanelY ?? 80 
    };
    
    window.addEventListener('mousemove', onDragCode);
    window.addEventListener('mouseup', stopDragCode);
};

const onDragCode = (e: MouseEvent) => {
    if (!isDraggingCode.value) return;
    const dx = e.clientX - dragStartCode.value.x;
    const dy = e.clientY - dragStartCode.value.y;
    
    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            codePanelX: initialPanelPos.value.x + dx,
            codePanelY: initialPanelPos.value.y + dy
        }, false);
    }
};

const stopDragCode = () => {
    isDraggingCode.value = false;
    window.removeEventListener('mousemove', onDragCode);
    window.removeEventListener('mouseup', stopDragCode);
    projectStore.saveProjects();
};

const getCodePanelStyle = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return {};
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return {};
    
    return {
        left: `${graph.codePanelX ?? (window.innerWidth - 420)}px`,
        top: `${graph.codePanelY ?? 80}px`,
        width: `${graph.codePanelWidth ?? 400}px`,
        height: `${graph.codePanelHeight ?? 400}px`
    };
});

// Resize Code Panel Logic
const isResizingCode = ref(false);
const initialPanelSize = ref({ width: 0, height: 0 });

const startResizeCode = (e: MouseEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    e.stopPropagation();
    e.preventDefault();
    isResizingCode.value = true;
    dragStartCode.value = { x: e.clientX, y: e.clientY };
    initialPanelSize.value = { 
        width: graph.codePanelWidth ?? 400, 
        height: graph.codePanelHeight ?? 400 
    };
    window.addEventListener('mousemove', onResizeCode);
    window.addEventListener('mouseup', stopResizeCode);
};

const onResizeCode = (e: MouseEvent) => {
    if (!isResizingCode.value) return;
    const dx = e.clientX - dragStartCode.value.x;
    const dy = e.clientY - dragStartCode.value.y;
    
    const newWidth = Math.max(300, initialPanelSize.value.width + dx);
    const newHeight = Math.max(200, initialPanelSize.value.height + dy);

    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            codePanelWidth: newWidth,
            codePanelHeight: newHeight
        }, false);
    }
};

const stopResizeCode = () => {
    isResizingCode.value = false;
    window.removeEventListener('mousemove', onResizeCode);
    window.removeEventListener('mouseup', stopResizeCode);
    projectStore.saveProjects();
};

// Resize Code Panel (Touch)
const startResizeCodeTouch = (e: TouchEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    e.stopPropagation();
    isResizingCode.value = true;
    const touch = e.touches[0];
    dragStartCode.value = { x: touch.clientX, y: touch.clientY };
    initialPanelSize.value = { 
        width: graph.codePanelWidth ?? 400, 
        height: graph.codePanelHeight ?? 400 
    };
    window.addEventListener('touchmove', onResizeCodeTouch, { passive: false });
    window.addEventListener('touchend', stopResizeCodeTouch);
};

const onResizeCodeTouch = (e: TouchEvent) => {
    if (!isResizingCode.value) return;
    e.preventDefault();
    const touch = e.touches[0];
    const dx = touch.clientX - dragStartCode.value.x;
    const dy = touch.clientY - dragStartCode.value.y;
    
    const newWidth = Math.max(300, initialPanelSize.value.width + dx);
    const newHeight = Math.max(200, initialPanelSize.value.height + dy);

    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            codePanelWidth: newWidth,
            codePanelHeight: newHeight
        }, false);
    }
};

const stopResizeCodeTouch = () => {
    isResizingCode.value = false;
    window.removeEventListener('touchmove', onResizeCodeTouch);
    window.removeEventListener('touchend', stopResizeCodeTouch);
    projectStore.saveProjects();
};

// Left sidebar click-to-open logic
const handleSidebarContainerClick = (e: MouseEvent) => {
    if ((e.target as HTMLElement).closest('.theme-toggle-header')) return;
    if (!isLeftSidebarOpen.value) {
        toggleLeftSidebar(); // Use logic to ensure exclusive open
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
      />
      <div v-else class="empty-state">
        <p>No graph selected. Create or select a graph to start.</p>
        <BaseButton @click="showNewGraphModal = true" type="primary">Create New Graph</BaseButton>
      </div>
    </main>

    <!-- Left Sidebar (Collapsed state handled via toggle) -->
    <LeftSidebar
        :activeAccordionTabs="activeAccordionTabs"
        :projectName="projectStore.currentProject?.name || null"
        :pinnedGraphTitle="pinnedGraphTitle"
        :isGridEnabled="isGridEnabled"
        :gridSize="gridSize"
        :showZoomControls="showZoomControls"
        :showDebugPanel="showDebugPanel"
        @toggle-left-sidebar="toggleLeftSidebar"
        @new-project="showNewProjectModal = true"
        @new-graph="showNewGraphModal = true"
        @update:currentMode="currentMode = $event"
        @update:currentNodeType="currentNodeType = $event"
        @update:isGridEnabled="isGridEnabled = $event"
        @update:gridSize="gridSize = $event"
        @update:showZoomControls="showZoomControls = $event"
        @update:showDebugPanel="showDebugPanel = $event"
        @toggle-code-panel="uiStore.toggleCodePanel"
        @load-example="handleLoadExample"
        @open-export-modal="openExportModal"
        @export-json="handleExportJson"
        @connect-to-backend-url="(url) => { tempBackendUrl = url; connectToBackend(); }"
        @run-model="runModel"
        @abort-run="abortRun"
        @generate-standalone="handleGenerateStandalone"
        @open-about-modal="showAboutModal = true"
    />

    <!-- Collapsed Left Sidebar Trigger Area -->
    <Transition name="fade">
        <div v-if="!isLeftSidebarOpen" 
             class="collapsed-sidebar-trigger glass-panel"
             @click="handleSidebarContainerClick">
           <div class="sidebar-trigger-content">
               <div class="flex-grow flex items-center gap-2 overflow-hidden" style="flex-grow: 1; overflow: hidden;">
                   <span class="logo-text-minimized">
                       <span class="desktop-text">{{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}</span>
                       <span class="mobile-text">DoodleBUGS</span>
                   </span>
               </div>
               <div class="flex items-center gap-1 flex-shrink-0" style="flex-shrink: 0;">
                   <button @click.stop="uiStore.toggleDarkMode()" class="theme-toggle-header" :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'">
                       <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
                   </button>
                   <div class="toggle-icon-wrapper">
                       <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
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
    />

    <!-- Collapsed Right Sidebar Trigger Area -->
    <Transition name="fade">
        <div v-if="!isRightSidebarOpen" 
             class="collapsed-sidebar-trigger right glass-panel"
             @click="toggleRightSidebar">
           <div class="sidebar-trigger-content">
               <span class="sidebar-title-minimized">Inspector</span>
               <div class="flex items-center gap-2">
                    <div class="status-indicator validation-status"
                        @click.stop="showValidationModal = true"
                        :class="isModelValid ? 'valid' : 'invalid'">
                        <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
                    </div>
                   <div class="toggle-icon-wrapper">
                       <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
                   </div>
               </div>
           </div>
        </div>
    </Transition>

    <!-- Code Panel Floating -->
    <div v-if="isCodePanelOpen && graphStore.currentGraphId" 
         ref="codePanelRef"
         class="code-panel-floating glass-panel"
         :style="getCodePanelStyle"
         @mousedown="startDragCode"
         @touchstart="startDragCodeTouch"
    >
        <div class="graph-header code-header">
            <span class="graph-title"><i class="fas fa-code"></i> BUGS Code Preview</span>
            <button class="close-btn" @click="uiStore.toggleCodePanel()" @touchstart.stop="uiStore.toggleCodePanel()"><i class="fas fa-times"></i></button>
        </div>
        <div class="code-content">
            <CodePreviewPanel :is-active="true" />
        </div>
        <div class="resize-handle" 
             @mousedown.stop="startResizeCode"
             @touchstart.stop.prevent="startResizeCodeTouch"
        >
            <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
        </div>
    </div>

    <!-- Floating Toolbar -->
    <FloatingBottomToolbar 
        :current-mode="currentMode"
        :current-node-type="currentNodeType"
        :show-code-panel="isCodePanelOpen"
        :show-zoom-controls="showZoomControls"
        @update:current-mode="currentMode = $event"
        @update:current-node-type="currentNodeType = $event"
        @undo="handleUndo"
        @redo="handleRedo"
        @zoom-in="handleZoomIn"
        @zoom-out="handleZoomOut"
        @fit="handleFit"
        @layout-graph="handleGraphLayout"
        @toggle-code-panel="uiStore.toggleCodePanel"
        @export-bugs="() => { /* handled via copy inside panel mostly */ }"
        @export-standalone="handleGenerateStandalone"
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
}

.collapsed-sidebar-trigger {
    position: absolute;
    top: 16px;
    z-index: 49; /* Below floating sidebar (50) */
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

.collapsed-sidebar-trigger.glass-panel {
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

/* Code Panel Floating */
.code-panel-floating {
    position: absolute;
    background-color: var(--theme-bg-panel);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-floating);
    display: flex;
    flex-direction: column;
    border: 1px solid var(--theme-border);
    overflow: hidden;
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
}

.graph-title {
  font-weight: 600;
  font-size: 12px;
  color: var(--theme-text-primary);
  display: flex;
  align-items: center;
  gap: 6px;
}

.close-btn {
    background: transparent;
    border: none;
    color: var(--theme-text-secondary);
    cursor: pointer;
    font-size: 13px;
    padding: 4px;
    display: flex;
    align-items: center;
}
.close-btn:hover {
    color: var(--theme-text-primary);
}

.code-content {
    flex: 1;
    overflow: hidden;
    background-color: var(--theme-bg-panel);
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

.validation-status { font-size: 1.1em; margin: 0; }
.validation-status.valid { color: var(--theme-success); }
.validation-status.invalid { color: var(--theme-warning); }

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
    box-shadow: 0 2px 6px rgba(0,0,0,0.2);
}

.status-indicator:hover .instant-tooltip {
    opacity: 1;
}

/* Fade Transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Responsive Text Styles */
.desktop-text { display: inline; }
.mobile-text { display: none; }

@media (max-width: 768px) {
    .desktop-text { display: none; }
    .mobile-text { display: inline; }

    .collapsed-sidebar-trigger {
        min-width: auto !important; /* Override desktop min-widths */
        max-width: 42%; /* Ensure two triggers don't overlap (42% * 2 + margins < 100%) */
        padding: 8px;
    }
    
    .collapsed-sidebar-trigger.glass-panel {
        min-width: auto !important;
    }

    .logo-text-minimized {
        font-size: 12px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        display: block; /* Needed for ellipsis to work */
    }
    
    .sidebar-trigger-content {
        gap: 4px;
    }
}
</style>
