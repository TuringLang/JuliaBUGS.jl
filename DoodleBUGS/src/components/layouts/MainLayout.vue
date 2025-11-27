<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed } from 'vue';
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
import FaqModal from './FaqModal.vue';
import ExportModal from './ExportModal.vue';
import GraphStyleModal from './GraphStyleModal.vue';
import ShareModal from './ShareModal.vue';
import ValidationIssuesModal from './ValidationIssuesModal.vue';
import DebugPanel from '../common/DebugPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import DataInputPanel from '../panels/DataInputPanel.vue';
import ScriptSettingsPanel from '../panels/ScriptSettingsPanel.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useProjectStore } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import { useDataStore } from '../../stores/dataStore';
import { useScriptStore } from '../../stores/scriptStore';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGraphValidator } from '../../composables/useGraphValidator';
import { useBugsCodeGenerator, generateStandaloneScript } from '../../composables/useBugsCodeGenerator';
import type { GraphElement, NodeType, ExampleModel, GraphNode } from '../../types';

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
const scriptStore = useScriptStore();

const { parsedGraphData } = storeToRefs(dataStore);
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements();
const { generatedCode } = useBugsCodeGenerator(elements);
const { getCyInstance, getUndoRedoInstance } = useGraphInstance();
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData);
const { samplerSettings, standaloneScript } = storeToRefs(scriptStore);
const { isLeftSidebarOpen, isRightSidebarOpen, canvasGridStyle, isDarkMode, activeRightTab } = storeToRefs(uiStore);

const currentMode = ref<string>('select');
const currentNodeType = ref<NodeType>('stochastic');
const isGridEnabled = ref(true);
const gridSize = ref(20);
const showZoomControls = ref(true);

// Sidebar State
const activeAccordionTabs = ref(['project']);

// Modals State
const showNewProjectModal = ref(false);
const newProjectName = ref('');
const showNewGraphModal = ref(false);
const newGraphName = ref('');
const importMode = ref<'blank' | 'json'>('blank');
const importJsonContent = ref('');
const showAboutModal = ref(false);
const showFaqModal = ref(false);
const showValidationModal = ref(false);
const showScriptSettingsModal = ref(false);
const showDebugPanel = ref(false);
const showExportModal = ref(false);
const showStyleModal = ref(false);
const showShareModal = ref(false);
const shareUrl = ref('');
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null);

// Data Import Ref
const dataImportInput = ref<HTMLInputElement | null>(null);

// Local viewport state for smooth UI updates
const viewportState = ref({ zoom: 1, pan: { x: 0, y: 0 } });

// Computed property for validation status
const isModelValid = computed(() => validationErrors.value.size === 0);

// Pinned Graph Title Computation
const pinnedGraphTitle = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return null;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return graph ? graph.name : null;
});

// Code Panel Visibility (Per-Graph State)
const isCodePanelOpen = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return false;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return !!graph?.showCodePanel;
});

const toggleCodePanel = () => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (graph) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            showCodePanel: !graph.showCodePanel
        });
    }
};

// Data Panel Visibility (Per-Graph State)
const isDataPanelOpen = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return false;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return !!graph?.showDataPanel;
});

const toggleDataPanel = () => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (graph) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            showDataPanel: !graph.showDataPanel
        });
    }
};

const toggleJsonPanel = () => {
    showDebugPanel.value = true;
};

// Dark Mode Handling
watch(isDarkMode, (val) => {
  const element = document.querySelector('html');
  if (val) element?.classList.add('dark-mode');
  else element?.classList.remove('dark-mode');
}, { immediate: true });

// Viewport Persistence Logic
let saveViewportTimeout: ReturnType<typeof setTimeout> | null = null;

const persistViewport = () => {
    if (saveViewportTimeout) {
        clearTimeout(saveViewportTimeout);
        saveViewportTimeout = null;
    }
    if (graphStore.currentGraphId) {
        graphStore.updateGraphViewport(graphStore.currentGraphId, viewportState.value.zoom, viewportState.value.pan);
    }
};

// Minification Helpers
// Map full keys to short keys
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
    y: 'y'
};

const nodeTypeMap: Record<string, number> = {
    stochastic: 1,
    deterministic: 2,
    constant: 3,
    observed: 4,
    plate: 5
};
const revNodeTypeMap = { 1: 'stochastic', 2: 'deterministic', 3: 'constant', 4: 'observed', 5: 'plate' };

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const minifyGraph = (elements: GraphElement[]): any[] => {
    return elements.map(el => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const min: any = {};
        if (el.type === 'node') {
            const node = el as GraphNode;
            min[keyMap.id] = node.id.replace('node_', ''); // Strip prefix if standard
            min[keyMap.name] = node.name;
            min[keyMap.type] = 0; // 0 for node
            min[keyMap.nodeType] = nodeTypeMap[node.nodeType];
            min[keyMap.position] = [Math.round(node.position.x), Math.round(node.position.y)];
            if (node.parent) min[keyMap.parent] = node.parent.replace('node_', '').replace('plate_', '');
            
            if (node.distribution) min[keyMap.distribution] = node.distribution;
            if (node.equation) min[keyMap.equation] = node.equation;
            if (node.observed) min[keyMap.observed] = 1;
            if (node.indices) min[keyMap.indices] = node.indices;
            if (node.loopVariable) min[keyMap.loopVariable] = node.loopVariable;
            if (node.loopRange) min[keyMap.loopRange] = node.loopRange;
            if (node.param1) min[keyMap.param1] = node.param1;
            if (node.param2) min[keyMap.param2] = node.param2;
            if (node.param3) min[keyMap.param3] = node.param3;
        } else {
            const edge = el;
            min[keyMap.id] = edge.id.replace('edge_', '');
            min[keyMap.type] = 1; // 1 for edge
            min[keyMap.source] = edge.source.replace('node_', '').replace('plate_', '');
            min[keyMap.target] = edge.target.replace('node_', '').replace('plate_', '');
        }
        return min;
    });
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const expandGraph = (minElements: any[]): GraphElement[] => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return minElements.map(min => {
        if (min[keyMap.type] === 0) { // Node
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const node: any = {
                id: min[keyMap.id].startsWith('node_') || min[keyMap.id].startsWith('plate_') ? min[keyMap.id] : (min[keyMap.nodeType] === 5 ? 'plate_' : 'node_') + min[keyMap.id],
                name: min[keyMap.name],
                type: 'node',
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                nodeType: (revNodeTypeMap as any)[min[keyMap.nodeType]],
                position: { 
                    x: (min[keyMap.position] && !isNaN(min[keyMap.position][0])) ? min[keyMap.position][0] : 0, 
                    y: (min[keyMap.position] && !isNaN(min[keyMap.position][1])) ? min[keyMap.position][1] : 0
                }
            };
            if (min[keyMap.parent]) {
                const pid = min[keyMap.parent];
                node.parent = pid.startsWith('plate_') || pid.startsWith('node_') ? pid : 'plate_' + pid; // Guessing prefix if missing, usually plates are parents
            }
            if (min[keyMap.distribution]) node.distribution = min[keyMap.distribution];
            if (min[keyMap.equation]) node.equation = min[keyMap.equation];
            if (min[keyMap.observed]) node.observed = true;
            if (min[keyMap.indices]) node.indices = min[keyMap.indices];
            if (min[keyMap.loopVariable]) node.loopVariable = min[keyMap.loopVariable];
            if (min[keyMap.loopRange]) node.loopRange = min[keyMap.loopRange];
            if (min[keyMap.param1]) node.param1 = min[keyMap.param1];
            if (min[keyMap.param2]) node.param2 = min[keyMap.param2];
            if (min[keyMap.param3]) node.param3 = min[keyMap.param3];
            return node as GraphNode;
        } else {
            // Edge
            return {
                id: min[keyMap.id].startsWith('edge_') ? min[keyMap.id] : 'edge_' + min[keyMap.id],
                type: 'edge',
                source: min[keyMap.source].startsWith('node_') || min[keyMap.source].startsWith('plate_') ? min[keyMap.source] : 'node_' + min[keyMap.source],
                target: min[keyMap.target].startsWith('node_') || min[keyMap.target].startsWith('plate_') ? min[keyMap.target] : 'node_' + min[keyMap.target]
            };
        }
    });
};

const createSharePayload = (graphName: string, graphElements: GraphElement[], dataContent: string, version: number) => {
    // Minify Data content: Parse JSON and re-stringify to remove whitespace
    let minData = dataContent;
    try {
        const d = JSON.parse(dataContent);
        minData = JSON.stringify(d); // Removes whitespace
    } catch { /* ignore */ }

    // Version 2: Minified Single Graph
    if (version === 2) {
        return {
            v: 2,
            n: graphName,
            e: minifyGraph(graphElements),
            d: minData
        };
    }
    return {};
};

const generateShareLink = (payload: object) => {
    try {
        const jsonStr = JSON.stringify(payload);
        // Standard Base64 Encoding with UTF-8 support
        const base64 = btoa(unescape(encodeURIComponent(jsonStr)));
        
        const baseUrl = window.location.origin + window.location.pathname;
        shareUrl.value = `${baseUrl}?share=${encodeURIComponent(base64)}`;
        showShareModal.value = true;
    } catch (e) {
        console.error("Failed to generate share link:", e);
        alert("Failed to generate share link. Model might be too large.");
    }
}

const handleShare = () => {
    if (!graphStore.currentGraphId || !pinnedGraphTitle.value) return;
    const payload = createSharePayload(pinnedGraphTitle.value, graphStore.currentGraphElements, dataStore.dataContent, 2);
    generateShareLink(payload);
};

const handleShareGraph = (graphId: string) => {
    // Logic to get graph data even if not loaded in memory (from LS)
    let elements: GraphElement[] = [];
    let dataContent = "";
    let name = "";

    if (graphId === graphStore.currentGraphId) {
        elements = graphStore.currentGraphElements;
        dataContent = dataStore.dataContent;
        name = pinnedGraphTitle.value || "Graph";
    } else {
        const storedGraph = localStorage.getItem(`doodlebugs-graph-${graphId}`);
        const storedData = localStorage.getItem(`doodlebugs-data-${graphId}`);
        const project = projectStore.projects.find(p => p.graphs.some(g => g.id === graphId));
        const graphMeta = project?.graphs.find(g => g.id === graphId);
        name = graphMeta?.name || "Graph";

        if (storedGraph) {
            try {
                elements = JSON.parse(storedGraph).elements;
            } catch { elements = []; }
        }
        if (storedData) {
             try {
                const parsed = JSON.parse(storedData);
                dataContent = parsed.content || (parsed.jsonData ? JSON.stringify({data: JSON.parse(parsed.jsonData || '{}'), inits: JSON.parse(parsed.jsonInits || '{}')}) : '{}');
            } catch { 
                dataContent = "{}";
            }
        }
    }
    
    const payload = createSharePayload(name, elements, dataContent, 2);
    generateShareLink(payload);
};

const handleShareProjectUrl = (projectId: string) => {
    const project = projectStore.projects.find(p => p.id === projectId);
    if (!project) return;

    const graphsData = project.graphs.map(graphMeta => {
        let elements: GraphElement[] = [];
        let dataContent = "{}";

        if (graphMeta.id === graphStore.currentGraphId) {
            elements = graphStore.currentGraphElements;
            dataContent = dataStore.dataContent;
        } else {
            const storedGraph = localStorage.getItem(`doodlebugs-graph-${graphMeta.id}`);
            const storedData = localStorage.getItem(`doodlebugs-data-${graphMeta.id}`);
            
            if (storedGraph) {
                try { elements = JSON.parse(storedGraph).elements; } catch {}
            }
            if (storedData) {
                try {
                    const parsed = JSON.parse(storedData);
                    dataContent = parsed.content || "{}";
                } catch {}
            }
        }

        // Minify Data
        try {
            const d = JSON.parse(dataContent);
            dataContent = JSON.stringify(d);
        } catch { /* ignore */ }

        return {
            n: graphMeta.name,
            e: minifyGraph(elements),
            d: dataContent
        };
    });

    // Version 3 Payload: Full Project
    const payload = {
        v: 3,
        pn: project.name,
        g: graphsData
    };

    generateShareLink(payload);
};

const handleExportData = () => {
    if (!graphStore.currentGraphId) return;
    const content = dataStore.dataContent;
    const blob = new Blob([content], { type: 'application/json' });
    const fileName = `data.json`;
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

// Data Import Logic
const triggerDataImport = () => {
    dataImportInput.value?.click();
};

const handleDataImport = (event: Event) => {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    
    const reader = new FileReader();
    reader.onload = (e) => {
        const content = e.target?.result as string;
        try {
            // Validate JSON
            JSON.parse(content);
            dataStore.dataContent = content;
        } catch (e) {
            alert('Invalid JSON file format.');
        }
        // Reset file input
        if (dataImportInput.value) dataImportInput.value.value = '';
    };
    reader.readAsText(file);
};

const handleLoadShared = async () => {
    const params = new URLSearchParams(window.location.search);
    const shareParam = params.get('share');
    
    let jsonStr: string | null = null;

    if (shareParam) {
        try {
            // Standard Base64 Decoding with UTF-8 support
            jsonStr = decodeURIComponent(escape(atob(shareParam)));
        } catch {
            console.error("Failed to decode base64 share");
        }
    }
    
    if (jsonStr) {
        try {
            const payload = JSON.parse(jsonStr);
            
            // Handle V3 (Project)
            if (payload.v === 3 && payload.pn && payload.g) {
                projectStore.createProject(payload.pn + " (Shared)");
                if (projectStore.currentProjectId) {
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    payload.g.forEach((graphData: any) => {
                        const newGraph = projectStore.addGraphToProject(projectStore.currentProjectId!, graphData.n);
                        if (newGraph) {
                            try {
                                const elements = expandGraph(graphData.e);
                                graphStore.updateGraphElements(newGraph.id, elements);
                                graphStore.updateGraphLayout(newGraph.id, 'preset');
                                
                                if (graphData.d) {
                                    try {
                                        const dObj = JSON.parse(graphData.d);
                                        dataStore.updateGraphData(newGraph.id, { content: JSON.stringify(dObj, null, 2) });
                                    } catch {
                                        dataStore.updateGraphData(newGraph.id, { content: graphData.d });
                                    }
                                }
                            } catch (e) {
                                console.error(`Error loading graph ${graphData.n}:`, e);
                            }
                        }
                    });
                    
                    // Force save the project list to ensure persistence across reloads
                    projectStore.saveProjects();

                    // Select first graph
                    if (projectStore.currentProject?.graphs.length) {
                        graphStore.selectGraph(projectStore.currentProject.graphs[0].id);
                    }
                }
            }
            // Handle V2 (Single Graph)
            else if (payload && payload.n && payload.e) {
                projectStore.createProject("Shared Project");
                if (projectStore.currentProjectId) {
                    const newGraph = projectStore.addGraphToProject(projectStore.currentProjectId, payload.n);
                    if (newGraph) {
                        let elements = payload.e;
                        // Check if version 2 (minified)
                        if (payload.v === 2) {
                            elements = expandGraph(payload.e);
                        }

                        graphStore.updateGraphElements(newGraph.id, elements);
                        graphStore.updateGraphLayout(newGraph.id, 'preset');
                        
                        if (payload.d) {
                            try {
                                const dObj = JSON.parse(payload.d);
                                dataStore.updateGraphData(newGraph.id, { content: JSON.stringify(dObj, null, 2) });
                            } catch {
                                dataStore.updateGraphData(newGraph.id, { content: payload.d });
                            }
                        }
                        projectStore.saveProjects();
                        graphStore.selectGraph(newGraph.id);
                    }
                }
            }
            
            // Clean URL without reloading
            const newUrl = window.location.origin + window.location.pathname;
            window.history.replaceState({}, document.title, newUrl);

        } catch (e) {
            console.error("Failed to load shared model:", e);
            alert("Invalid or corrupted share link.");
        }
    }
};

onMounted(async () => {
  projectStore.loadProjects();
  
  // Check for shared model
  if (window.location.search.includes('share=')) {
      await handleLoadShared();
  }
  
  // Default init if no shared model loaded or no projects exist
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project');
    if (projectStore.currentProjectId) await handleLoadExample('rats');
  } else {
    // If not a fresh shared load, restore last session
    if (!window.location.search.includes('share=')) {
        const lastGraphId = localStorage.getItem('doodlebugs-currentGraphId');
        if (lastGraphId && projectStore.currentProject?.graphs.some(g => g.id === lastGraphId)) {
          graphStore.selectGraph(lastGraphId);
        } else if (projectStore.currentProject?.graphs.length) {
          graphStore.selectGraph(projectStore.currentProject.graphs[0].id);
        }
    }
  }
  validateGraph();

  // Mobile: hide zoom controls by default on small screens
  if (window.innerWidth < 768) {
      showZoomControls.value = false;
  }

  // Force save on page reload/close
  window.addEventListener('beforeunload', persistViewport);
});

onUnmounted(() => {
    window.removeEventListener('beforeunload', persistViewport);
    persistViewport();
});

// Sync viewport state when graph changes
watch(() => graphStore.currentGraphId, (newId) => {
    if (newId) {
        const content = graphStore.graphContents.get(newId);
        if (content) {
            viewportState.value = {
                zoom: content.zoom ?? 1,
                pan: content.pan ?? { x: 0, y: 0 }
            };
        }
    }
}, { immediate: true });

// Initialize Code Panel Position if missing
watch([isCodePanelOpen, () => graphStore.currentGraphId], ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
        const graph = projectStore.currentProject.graphs.find(g => g.id === graphId);
        
        if (graph) {
            const needsInit = graph.codePanelX === undefined || graph.codePanelY === undefined;
            if (needsInit) {
                // Simple default dimensions
                const panelW = 400;
                const panelH = 300;
                
                // Position on the RIGHT side relative to the graph view
                const viewportW = window.innerWidth;
                // Sidebar is ~320px + 16px margin = 336px.
                const rightSidebarOffset = isRightSidebarOpen.value ? 340 : 20; 
                
                let targetScreenX = viewportW - rightSidebarOffset - panelW - 10;
                if (targetScreenX < 20) targetScreenX = 20; // Safety check
                
                // Top offset
                const targetScreenY = 90;

                projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
                    codePanelX: targetScreenX,
                    codePanelY: targetScreenY,
                    codePanelWidth: panelW,
                    codePanelHeight: panelH
                });
            }
        }
    }
}, { immediate: true });

// Initialize Data Panel Position if missing
watch([isDataPanelOpen, () => graphStore.currentGraphId], ([isOpen, graphId]) => {
    if (isOpen && graphId && projectStore.currentProject) {
        const graph = projectStore.currentProject.graphs.find(g => g.id === graphId);
        
        if (graph) {
            const needsInit = graph.dataPanelX === undefined || graph.dataPanelY === undefined;
            if (needsInit) {
                // Simple default dimensions
                const panelW = 400;
                const panelH = 300;
                
                // Position on the LEFT side relative to the graph view
                // Sidebar is ~300px + 16px margin.
                const leftSidebarOffset = isLeftSidebarOpen.value ? 320 : 20; 
                
                let targetScreenX = leftSidebarOffset + 20;
                
                // Top offset
                const targetScreenY = 90;

                projectStore.updateGraphLayout(projectStore.currentProject.id, graphId, {
                    dataPanelX: targetScreenX,
                    dataPanelY: targetScreenY,
                    dataPanelWidth: panelW,
                    dataPanelHeight: panelH
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

const handleViewportChanged = (v: { zoom: number, pan: { x: number, y: number } }) => {
    // Update local state immediately for smooth UI
    viewportState.value = v;
    
    // Debounce persistence
    if (saveViewportTimeout) clearTimeout(saveViewportTimeout);
    saveViewportTimeout = setTimeout(persistViewport, 200);
}

const smartFit = (cy: Core, animate: boolean = true) => {
    const eles = cy.elements();
    if (eles.length === 0) return;
    
    const padding = 50;
    const w = cy.width();
    const h = cy.height();
    const bb = eles.boundingBox();
    
    if (bb.w === 0 || bb.h === 0) return;

    const zoomX = (w - 2 * padding) / bb.w;
    const zoomY = (h - 2 * padding) / bb.h;
    let targetZoom = Math.min(zoomX, zoomY);
    targetZoom = Math.min(targetZoom, 0.8);
    
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
    
    const layoutOptionsMap: Record<string, LayoutOptions> = {
        dagre: { name: 'dagre', animate: true, animationDuration: 500, fit: false, padding: 50 } as unknown as LayoutOptions,
        fcose: { name: 'fcose', animate: true, animationDuration: 500, fit: false, padding: 50, randomize: false, quality: 'proof' } as unknown as LayoutOptions,
        cola: { name: 'cola', animate: true, fit: false, padding: 50, refresh: 1, avoidOverlap: true, infinite: false, centerGraph: true, flow: { axis: 'y', minSeparation: 30 }, handleDisconnected: false, randomize: false } as unknown as LayoutOptions,
        klay: { name: 'klay', animate: true, animationDuration: 500, fit: false, padding: 50, klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' } } as unknown as LayoutOptions,
        preset: { name: 'preset', fit: false, padding: 50 } as unknown as LayoutOptions
    };
    
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
        const cy = getCyInstance(graphStore.currentGraphId!);
        if (cy) {
            // Programmatically select node in Cytoscape for visual feedback
            cy.elements().removeClass('cy-selected');
            const cyNode = cy.getElementById(nodeId);
            cyNode.addClass('cy-selected');

            cy.animate({
                fit: { eles: cyNode, padding: 50 },
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

const handleFileUpload = (event: Event) => {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
        importJsonContent.value = e.target?.result as string;
    };
    reader.readAsText(file);
};

const createNewGraph = () => {
  if (projectStore.currentProject && newGraphName.value.trim()) {
    const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId!, newGraphName.value.trim());
    if (newGraphMeta) {
        if (importMode.value === 'json' && importJsonContent.value) {
            try {
                const importedElements = JSON.parse(importJsonContent.value);
                if (Array.isArray(importedElements)) {
                    graphStore.updateGraphElements(newGraphMeta.id, importedElements);
                    // Also try to layout if imported
                    setTimeout(() => {
                        graphStore.updateGraphLayout(newGraphMeta.id, 'preset');
                        const cy = getCyInstance(newGraphMeta.id);
                        if (cy) smartFit(cy, true);
                    }, 100);
                } else {
                    alert("Invalid JSON format. Expected an array of graph elements.");
                }
            } catch (e) {
                console.error(e);
                alert("Failed to parse JSON.");
            }
        }
    }
    showNewGraphModal.value = false;
    newGraphName.value = '';
    importJsonContent.value = '';
    importMode.value = 'blank';
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

const handleDownloadBugs = () => {
  const content = generatedCode.value;
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const fileName = 'model.bugs';
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
};

const handleConfirmExport = (options: ExportOptions) => {
  const cy = (graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null) as Core | null;
  if (!cy || !currentExportType.value) return;
  
  const fileName = `graph.${currentExportType.value}`;
  
  try {
    let blob: Blob;
    
    if (currentExportType.value === 'svg') {
      const svgOptions = { bg: options.bg, full: options.full, scale: options.scale };
      blob = new Blob([cy.svg(svgOptions)], { type: 'image/svg+xml;charset=utf-8' });
    } else {
      const baseOptions = {
        bg: options.bg,
        full: options.full,
        scale: options.scale,
        maxWidth: options.maxWidth,
        maxHeight: options.maxHeight,
        output: 'blob' as const
      };
      
      if (currentExportType.value === 'png') {
        blob = cy.png(baseOptions) as unknown as Blob;
      } else {
        blob = cy.jpg({ ...baseOptions, quality: options.quality }) as unknown as Blob;
      }
    }
    
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  } catch (err) {
    console.error(`Failed to export ${currentExportType.value}:`, err);
  }
};

const getScriptContent = () => {
    const dataPayload = parsedGraphData.value.data || {};
    const initsPayload = parsedGraphData.value.inits || {};
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
    });
};

const handleGenerateStandalone = () => {
    const script = getScriptContent();
    scriptStore.standaloneScript = script;
    uiStore.setActiveRightTab('script');
    uiStore.isRightSidebarOpen = true;
};

// Auto-update script if it exists or script panel is open
watch(
  [generatedCode, parsedGraphData, samplerSettings],
  () => {
    // Update if script already exists OR if the panel is open
    if (standaloneScript.value || (activeRightTab.value === 'script' && isRightSidebarOpen.value)) {
      scriptStore.standaloneScript = getScriptContent();
    }
  },
  { deep: true }
);

const handleScriptSettingsDone = () => {
    // Also regenerate immediately on settings close
    const script = getScriptContent();
    scriptStore.standaloneScript = script;
    showScriptSettingsModal.value = false;
};

const handleDownloadScript = () => {
    const content = standaloneScript.value;
    if (!content) return;
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const fileName = 'DoodleBUGS-Julia-Script.jl';
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

const handleOpenScriptSettings = () => {
    showScriptSettingsModal.value = true;
}

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
    
    graphStore.updateGraphLayout(newGraphMeta.id, 'preset');

    const jsonDataResponse = await fetch(`${baseUrl}examples/${exampleKey}/data.json`);
    if (jsonDataResponse.ok) {
      const fullData = await jsonDataResponse.json();
      dataStore.dataContent = JSON.stringify({ data: fullData.data || {}, inits: fullData.inits || {} }, null, 2);
    }
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

// When dragging starts, we capture the current Zoom/Pan state
const startDragCodeTouch = (e: TouchEvent) => {
    if ((e.target as HTMLElement).closest('.action-btn')) return;
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingCode.value = true;
    const touch = e.touches[0];
    dragStartCode.value = { x: touch.clientX, y: touch.clientY };
    
    // Use screen coordinates
    initialPanelPos.value = { 
        x: graph.codePanelX ?? 0,
        y: graph.codePanelY ?? 0
    };
    
    window.addEventListener('touchmove', onDragCodeTouch, { passive: false });
    window.addEventListener('touchend', stopDragCodeTouch);
};

const onDragCodeTouch = (e: TouchEvent) => {
    if (!isDraggingCode.value) return;
    e.preventDefault();
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
    if ((e.target as HTMLElement).closest('.action-btn')) return;
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingCode.value = true;
    dragStartCode.value = { x: e.clientX, y: e.clientY };
    initialPanelPos.value = { 
        x: graph.codePanelX ?? 0,
        y: graph.codePanelY ?? 0
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
    
    const screenX = graph.codePanelX ?? 0;
    const screenY = graph.codePanelY ?? 0;
    
    return {
        left: `${screenX}px`,
        top: `${screenY}px`,
        width: `${graph.codePanelWidth ?? 400}px`,
        height: `${graph.codePanelHeight ?? 300}px`
    };
});

// Resize Code Panel Logic (remains in pixels/screen coords)
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
        height: graph.codePanelHeight ?? 300 
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
        height: graph.codePanelHeight ?? 300 
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

// --- Data Panel Logic ---

const dataPanelRef = ref<HTMLElement | null>(null);
const isDraggingData = ref(false);
const dragStartData = ref({ x: 0, y: 0 });
const initialDataPanelPos = ref({ x: 0, y: 0 });

const startDragDataTouch = (e: TouchEvent) => {
    if ((e.target as HTMLElement).closest('.action-btn')) return;
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingData.value = true;
    const touch = e.touches[0];
    dragStartData.value = { x: touch.clientX, y: touch.clientY };
    
    initialDataPanelPos.value = { 
        x: graph.dataPanelX ?? 0,
        y: graph.dataPanelY ?? 0
    };
    
    window.addEventListener('touchmove', onDragDataTouch, { passive: false });
    window.addEventListener('touchend', stopDragDataTouch);
};

const onDragDataTouch = (e: TouchEvent) => {
    if (!isDraggingData.value) return;
    e.preventDefault();
    const touch = e.touches[0];
    const dx = touch.clientX - dragStartData.value.x;
    const dy = touch.clientY - dragStartData.value.y;
    
    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            dataPanelX: initialDataPanelPos.value.x + dx,
            dataPanelY: initialDataPanelPos.value.y + dy
        }, false);
    }
};

const stopDragDataTouch = () => {
    isDraggingData.value = false;
    window.removeEventListener('touchmove', onDragDataTouch);
    window.removeEventListener('touchend', stopDragDataTouch);
    projectStore.saveProjects();
};

const startDragData = (e: MouseEvent) => {
    if ((e.target as HTMLElement).closest('.action-btn')) return;
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    isDraggingData.value = true;
    dragStartData.value = { x: e.clientX, y: e.clientY };
    initialDataPanelPos.value = { 
        x: graph.dataPanelX ?? 0,
        y: graph.dataPanelY ?? 0
    };
    window.addEventListener('mousemove', onDragData);
    window.addEventListener('mouseup', stopDragData);
};

const onDragData = (e: MouseEvent) => {
    if (!isDraggingData.value) return;
    const dx = e.clientX - dragStartData.value.x;
    const dy = e.clientY - dragStartData.value.y;
    
    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            dataPanelX: initialDataPanelPos.value.x + dx,
            dataPanelY: initialDataPanelPos.value.y + dy
        }, false);
    }
};

const stopDragData = () => {
    isDraggingData.value = false;
    window.removeEventListener('mousemove', onDragData);
    window.removeEventListener('mouseup', stopDragData);
    projectStore.saveProjects();
};

const getDataPanelStyle = computed(() => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return {};
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return {};
    
    const screenX = graph.dataPanelX ?? 0;
    const screenY = graph.dataPanelY ?? 0;
    
    return {
        left: `${screenX}px`,
        top: `${screenY}px`,
        width: `${graph.dataPanelWidth ?? 400}px`,
        height: `${graph.dataPanelHeight ?? 300}px`
    };
});

const isResizingData = ref(false);
const initialDataPanelSize = ref({ width: 0, height: 0 });

const startResizeData = (e: MouseEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    e.stopPropagation();
    e.preventDefault();
    isResizingData.value = true;
    dragStartData.value = { x: e.clientX, y: e.clientY };
    initialDataPanelSize.value = { 
        width: graph.dataPanelWidth ?? 400, 
        height: graph.dataPanelHeight ?? 300 
    };
    window.addEventListener('mousemove', onResizeData);
    window.addEventListener('mouseup', stopResizeData);
};

const onResizeData = (e: MouseEvent) => {
    if (!isResizingData.value) return;
    const dx = e.clientX - dragStartData.value.x;
    const dy = e.clientY - dragStartData.value.y;
    const newWidth = Math.max(300, initialDataPanelSize.value.width + dx);
    const newHeight = Math.max(200, initialDataPanelSize.value.height + dy);

    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            dataPanelWidth: newWidth,
            dataPanelHeight: newHeight
        }, false);
    }
};

const stopResizeData = () => {
    isResizingData.value = false;
    window.removeEventListener('mousemove', onResizeData);
    window.removeEventListener('mouseup', stopResizeData);
    projectStore.saveProjects();
};

const startResizeDataTouch = (e: TouchEvent) => {
    if (!projectStore.currentProject || !graphStore.currentGraphId) return;
    const graph = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    if (!graph) return;

    e.stopPropagation();
    isResizingData.value = true;
    const touch = e.touches[0];
    dragStartData.value = { x: touch.clientX, y: touch.clientY };
    initialDataPanelSize.value = { 
        width: graph.dataPanelWidth ?? 400, 
        height: graph.dataPanelHeight ?? 300 
    };
    window.addEventListener('touchmove', onResizeDataTouch, { passive: false });
    window.addEventListener('touchend', stopResizeDataTouch);
};

const onResizeDataTouch = (e: TouchEvent) => {
    if (!isResizingData.value) return;
    e.preventDefault();
    const touch = e.touches[0];
    const dx = touch.clientX - dragStartData.value.x;
    const dy = touch.clientY - dragStartData.value.y;
    const newWidth = Math.max(300, initialDataPanelSize.value.width + dx);
    const newHeight = Math.max(200, initialDataPanelSize.value.height + dy);

    if (projectStore.currentProject && graphStore.currentGraphId) {
        projectStore.updateGraphLayout(projectStore.currentProject.id, graphStore.currentGraphId, {
            dataPanelWidth: newWidth,
            dataPanelHeight: newHeight
        }, false);
    }
};

const stopResizeDataTouch = () => {
    isResizingData.value = false;
    window.removeEventListener('touchmove', onResizeDataTouch);
    window.removeEventListener('touchend', stopResizeDataTouch);
    projectStore.saveProjects();
};

const handleSidebarContainerClick = (e: MouseEvent) => {
    if ((e.target as HTMLElement).closest('.theme-toggle-header')) return;
    if (!isLeftSidebarOpen.value) {
        toggleLeftSidebar();
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
        :activeAccordionTabs="activeAccordionTabs"
        :projectName="projectStore.currentProject?.name || null"
        :pinnedGraphTitle="pinnedGraphTitle"
        :isGridEnabled="isGridEnabled"
        :gridSize="gridSize"
        :showZoomControls="showZoomControls"
        :showDebugPanel="showDebugPanel"
        :isCodePanelOpen="isCodePanelOpen"
        @toggle-left-sidebar="toggleLeftSidebar"
        @new-project="showNewProjectModal = true"
        @new-graph="showNewGraphModal = true"
        @update:currentMode="currentMode = $event"
        @update:currentNodeType="currentNodeType = $event"
        @update:isGridEnabled="isGridEnabled = $event"
        @update:gridSize="gridSize = $event"
        @update:showZoomControls="showZoomControls = $event"
        @update:showDebugPanel="showDebugPanel = $event"
        @toggle-code-panel="toggleCodePanel"
        @load-example="handleLoadExample"
        @open-about-modal="showAboutModal = true"
        @open-faq-modal="showFaqModal = true"
        @share-graph="handleShareGraph"
        @share-project-url="handleShareProjectUrl"
    />

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
        @open-script-settings="handleOpenScriptSettings"
        @download-script="handleDownloadScript"
        @generate-script="handleGenerateStandalone"
        @share="handleShare"
        @open-export-modal="openExportModal"
        @export-json="handleExportJson"
        @export-data="handleExportData"
    />

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

    <div v-if="isCodePanelOpen && graphStore.currentGraphId" 
         ref="codePanelRef"
         class="code-panel-floating glass-panel"
         :style="getCodePanelStyle"
    >
        <div class="graph-header code-header"
             @mousedown="startDragCode"
             @touchstart="startDragCodeTouch"
        >
            <span class="graph-title"><i class="fas fa-code"></i> BUGS Code Preview</span>
            <div class="panel-actions">
                <button class="action-btn" @click.stop="handleDownloadBugs" title="Download BUGS Code" @mousedown.stop @touchstart.stop>
                    <i class="fas fa-download"></i>
                </button>
                <button class="close-btn" @click="toggleCodePanel()" @touchstart.stop="toggleCodePanel()" @mousedown.stop><i class="fas fa-times"></i></button>
            </div>
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

    <!-- Data Panel Pop-out -->
    <div v-if="isDataPanelOpen && graphStore.currentGraphId"
         ref="dataPanelRef"
         class="code-panel-floating glass-panel"
         :style="getDataPanelStyle"
    >
        <div class="graph-header code-header"
             @mousedown="startDragData"
             @touchstart="startDragDataTouch"
        >
            <span class="graph-title">
                <i class="fas fa-database"></i> Data & Inits 
                <span class="badge-json">JSON</span>
            </span>
            <div class="panel-actions">
                <button class="action-btn" @click.stop="triggerDataImport" title="Import JSON Data" @mousedown.stop @touchstart.stop>
                    <i class="fas fa-file-upload"></i>
                </button>
                <button class="close-btn" @click="toggleDataPanel()" @touchstart.stop="toggleDataPanel()" @mousedown.stop><i class="fas fa-times"></i></button>
            </div>
        </div>
        <div class="code-content">
            <DataInputPanel :is-active="true" />
        </div>
        <div class="resize-handle"
             @mousedown.stop="startResizeData"
             @touchstart.stop.prevent="startResizeDataTouch"
        >
            <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
        </div>
        <!-- Hidden file input for Data Import -->
        <input type="file" ref="dataImportInput" accept=".json" style="display:none" @change="handleDataImport" />
    </div>

    <FloatingBottomToolbar 
        :current-mode="currentMode"
        :current-node-type="currentNodeType"
        :show-code-panel="isCodePanelOpen"
        :show-data-panel="isDataPanelOpen"
        :show-json-panel="false"
        :show-zoom-controls="showZoomControls"
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
        @open-style-modal="showStyleModal = true"
        @share="handleShare"
    />

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
        <div class="flex-col gap-4">
          <div class="flex gap-2 mb-2">
              <BaseButton :type="importMode === 'blank' ? 'primary' : 'secondary'" size="small" @click="importMode = 'blank'" class="flex-1">Blank Graph</BaseButton>
              <BaseButton :type="importMode === 'json' ? 'primary' : 'secondary'" size="small" @click="importMode = 'json'" class="flex-1">Import JSON</BaseButton>
          </div>
          
          <div class="flex-col gap-2">
            <label>Graph Name:</label>
            <BaseInput v-model="newGraphName" placeholder="Enter graph name" @keyup.enter="createNewGraph" />
          </div>

          <div v-if="importMode === 'json'" class="flex-col gap-2">
              <label>Paste JSON or Upload File:</label>
              <textarea v-model="importJsonContent" class="json-textarea" placeholder="Paste graph JSON here..."></textarea>
              <div class="file-upload-wrapper">
                  <input type="file" accept=".json" @change="handleFileUpload" class="file-input"/>
              </div>
          </div>
        </div>
      </template>
      <template #footer>
        <BaseButton @click="showNewGraphModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewGraph" type="primary">Create</BaseButton>
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
    <ExportModal :is-open="showExportModal" :export-type="currentExportType" @close="showExportModal = false" @confirm-export="handleConfirmExport" />
    <ValidationIssuesModal :is-open="showValidationModal" :validation-errors="validationErrors" :elements="elements" @select-node="handleSelectNodeFromModal" @close="showValidationModal = false" />
    <GraphStyleModal :is-open="showStyleModal" @close="showStyleModal = false" />
    <ShareModal :is-open="showShareModal" :url="shareUrl" @close="showShareModal = false" />
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

.badge-json {
    font-size: 0.7em;
    background-color: var(--theme-primary);
    color: white;
    padding: 2px 4px;
    border-radius: 3px;
    margin-left: 6px;
    font-weight: normal;
    vertical-align: middle;
}

.panel-actions {
    display: flex;
    align-items: center;
    gap: 4px;
}

.action-btn {
    background: transparent;
    border: none;
    color: var(--theme-text-secondary);
    cursor: pointer;
    font-size: 13px;
    padding: 4px;
    display: flex;
    align-items: center;
    transition: color 0.2s;
}

.action-btn:hover {
    color: var(--theme-text-primary);
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

.code-content :deep(.code-preview-panel), 
.code-content :deep(.data-input-panel),
.code-content :deep(.json-editor-panel) {
    height: 100%;
    padding: 0;
}
.code-content :deep(.header-section) {
    display: none; 
}

.code-content :deep(.header-controls) {
    display: none;
}

.code-content :deep(.panel-title),
.code-content :deep(.description) {
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

.desktop-text { display: inline; }
.mobile-text { display: none; }

@media (max-width: 768px) {
    .desktop-text { display: none; }
    .mobile-text { display: inline; }

    .collapsed-sidebar-trigger {
        min-width: auto !important;
        max-width: 42%;
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
        display: block;
    }
    
    .sidebar-trigger-content {
        gap: 4px;
    }
}
</style>
