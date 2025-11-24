<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import ToggleSwitch from 'primevue/toggleswitch';
import BaseSelect from '../ui/BaseSelect.vue';
import InputNumber from 'primevue/inputnumber';
import GraphEditor from './GraphEditor.vue';
import GraphPreview from './GraphPreview.vue';
import FloatingBottomToolbar from './FloatingBottomToolbar.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import { useProjectStore, type GraphMeta } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore, type GridStyle } from '../../stores/uiStore';
import type { GraphElement, GraphNode, NodeType, ValidationError } from '../../types';
import DropdownMenu from '../common/DropdownMenu.vue';
import { useGraphInstance } from '../../composables/useGraphInstance';

const props = defineProps<{
  isGridEnabled: boolean; 
  gridSize: number;       
  currentMode: string;
  currentNodeType: NodeType;
  validationErrors: Map<string, ValidationError[]>;
  showZoomControls: boolean;
}>();

const emit = defineEmits<{
  (e: 'element-selected', element: GraphElement | null): void;
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'layout-updated', layoutName: string): void;
  (e: 'update:show-zoom-controls', value: boolean): void;
  (e: 'update:isGridEnabled', value: boolean): void;
  (e: 'update:gridSize', value: number): void;
  (e: 'new-graph'): void;
  (e: 'open-export-modal', format: 'png' | 'jpg' | 'svg'): void;
  (e: 'pinned-graph-change', payload: { id: string | null; name: string | null }): void;
}>();

const projectStore = useProjectStore();
const graphStore = useGraphStore();
const uiStore = useUiStore();
const { currentProject } = storeToRefs(projectStore);
const { currentGraphId, elementToFocus } = storeToRefs(graphStore);
const { pinnedGraphId } = storeToRefs(uiStore);
const { getCyInstance, getUndoRedoInstance } = useGraphInstance();

// --- Workspace State ---
const workspaceX = ref(0);
const workspaceY = ref(0);
const workspaceScale = ref(1);
const isPanning = ref(false);
const lastMousePos = ref({ x: 0, y: 0 });
const containerRef = ref<HTMLElement | null>(null);
const workspaceDivRef = ref<HTMLElement | null>(null);

// --- Graph/Panel Drag/Resize State ---
const dragTarget = ref<string | null>(null); 
const dragType = ref<'graph' | 'code' | null>(null);
const resizeTarget = ref<string | null>(null);
const resizeType = ref<'graph' | 'code' | null>(null);
const dragStart = ref({ x: 0, y: 0 });
const initialLayout = ref({ x: 0, y: 0, width: 0, height: 0 });

// --- Tooltip State ---
const hoveredGraphId = ref<string | null>(null);
const tooltipPos = ref({ x: 0, y: 0 });
const showTooltip = ref(false);

const gridStyleOptions = [
    { label: 'Dots', value: 'dots' },
    { label: 'Lines', value: 'lines' }
];

const graphs = computed(() => currentProject.value?.graphs || []);

// Helper: Resolve Grid Settings 
const resolveGrid = (graph: GraphMeta) => {
    const enabled = graph.gridEnabled !== undefined ? graph.gridEnabled : props.isGridEnabled;
    const size = graph.gridSize !== undefined ? graph.gridSize : props.gridSize;
    const style = graph.gridStyle !== undefined ? graph.gridStyle : uiStore.canvasGridStyle;
    return { enabled, size, style };
};

// --- Graph Loading ---
watch(graphs, (newGraphs) => {
  if (!newGraphs) return;
  newGraphs.forEach(graph => {
    try {
      if (!graphStore.graphContents.has(graph.id)) {
        const loaded = graphStore.loadGraph(graph.id);
        if (!loaded) {
          graphStore.createNewGraphContent(graph.id);
        }
      }
    } catch (e) {
      console.error(`Failed to load graph ${graph.id}:`, e);
    }
  });
}, { immediate: true, deep: true });

const getElementsForGraph = (graphId: string): GraphElement[] => {
  const content = graphStore.graphContents.get(graphId);
  return content?.elements || [];
};

const getNodeBreakdownArray = (graphId: string) => {
    const elements = getElementsForGraph(graphId);
    const counts: Record<string, number> = {};
    let total = 0;
    elements.forEach(el => {
        if (el.type === 'node') {
            const type = (el as GraphNode).nodeType;
            const label = type.charAt(0).toUpperCase() + type.slice(1);
            counts[label] = (counts[label] || 0) + 1;
            total++;
        }
    });
    if (total === 0) return [];
    return Object.entries(counts).map(([type, count]) => ({ type, count }));
};

const handleBadgeEnter = (e: MouseEvent, graphId: string) => {
    hoveredGraphId.value = graphId;
    tooltipPos.value = { x: e.clientX, y: e.clientY };
    showTooltip.value = true;
};

const handleBadgeMove = (e: MouseEvent) => {
    if (showTooltip.value) {
        tooltipPos.value = { x: e.clientX, y: e.clientY };
    }
};

const handleBadgeLeave = () => {
    showTooltip.value = false;
    hoveredGraphId.value = null;
};

const zoomGraph = (graphId: string, factor: number) => {
    const cy = getCyInstance(graphId);
    if (cy) {
        const currentZoom = cy.zoom();
        const newZoom = currentZoom * factor;
        cy.animate({
            zoom: {
                level: newZoom,
                position: { x: cy.width() / 2, y: cy.height() / 2 }
            },
            duration: 200,
            easing: 'ease-out'
        });
    }
};

const fitGraph = (graphId: string) => {
    const cy = getCyInstance(graphId);
    if (cy) {
        cy.resize(); // Ensure resize is called before fitting, especially on display change
        cy.animate({
            fit: {
                eles: cy.elements(),
                padding: 50
            },
            duration: 300,
            easing: 'ease-in-out-cubic'
        });
    }
};

const handleGraphLayout = (layoutName: string, graphId?: string) => {
    const targetId = graphId || pinnedGraphId.value || currentGraphId.value;
    if (targetId) {
        const cy = getCyInstance(targetId);
        if (cy) {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const layoutOptionsMap: Record<string, any> = {
                dagre: { name: 'dagre', animate: true, animationDuration: 500, fit: true, padding: 30 },
                fcose: { name: 'fcose', animate: true, animationDuration: 500, fit: true, padding: 30, randomize: false, quality: 'proof' },
                cola: { name: 'cola', animate: true, fit: true, padding: 30, refresh: 1, avoidOverlap: true, infinite: false, centerGraph: true, flow: { axis: 'y', minSeparation: 30 }, handleDisconnected: false, randomize: false },
                klay: { name: 'klay', animate: true, animationDuration: 500, fit: true, padding: 30, klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' } },
                preset: { name: 'preset' }
            };
            const options = layoutOptionsMap[layoutName] || layoutOptionsMap.preset;
            cy.layout(options).run();
            emit('layout-updated', layoutName);
        }
    }
};

const updateGraphGridEnabled = (graphId: string, enabled: boolean) => {
    if (currentProject.value) {
        projectStore.updateGraphLayout(currentProject.value.id, graphId, { gridEnabled: enabled });
    }
};

const updateGraphGridStyle = (graphId: string, style: GridStyle) => {
    if (currentProject.value) {
        projectStore.updateGraphLayout(currentProject.value.id, graphId, { gridStyle: style });
    }
};

const updateGraphGridSize = (graphId: string, size: number) => {
    if (currentProject.value) {
        projectStore.updateGraphLayout(currentProject.value.id, graphId, { gridSize: size });
    }
};

// --- Performance Optimized Pan/Zoom ---
let rAF: number | null = null;

const handleWheel = (e: WheelEvent) => {
  if (pinnedGraphId.value) return; 

  const target = e.target as HTMLElement;
  const closestCard = target.closest('.graph-card') || target.closest('.code-panel-card');
  if (closestCard && closestCard.classList.contains('active') && (target.closest('.graph-content') || target.closest('.code-preview-wrapper'))) {
      return; 
  }

  if (e.ctrlKey || e.metaKey) {
    e.preventDefault();
    if (rAF) return; 

    rAF = requestAnimationFrame(() => {
        const zoomSensitivity = 0.001;
        const delta = -e.deltaY * zoomSensitivity;
        const newScale = Math.min(Math.max(0.1, workspaceScale.value + delta), 5);
        
        if (containerRef.value) {
          const rect = containerRef.value.getBoundingClientRect();
          const mouseX = e.clientX - rect.left;
          const mouseY = e.clientY - rect.top;
          const scaleRatio = newScale / workspaceScale.value;
          workspaceX.value = mouseX - (mouseX - workspaceX.value) * scaleRatio;
          workspaceY.value = mouseY - (mouseY - workspaceY.value) * scaleRatio;
          workspaceScale.value = newScale;
        }
        rAF = null;
    });
  } else {
    e.preventDefault();
    if (rAF) return;
    rAF = requestAnimationFrame(() => {
        workspaceX.value -= e.deltaX;
        workspaceY.value -= e.deltaY;
        rAF = null;
    });
  }
};

// --- Pan Logic with Direct DOM Manipulation for Performance ---
const panStartState = { x: 0, y: 0 };

const startPan = (e: MouseEvent) => {
  if (pinnedGraphId.value) return;
  if ((e.target as HTMLElement).classList.contains('infinite-canvas') || (e.target as HTMLElement).tagName === 'svg') {
    isPanning.value = true;
    lastMousePos.value = { x: e.clientX, y: e.clientY };
    panStartState.x = workspaceX.value;
    panStartState.y = workspaceY.value;
    
    document.body.style.cursor = 'grabbing';
    window.addEventListener('mousemove', onPan);
    window.addEventListener('mouseup', stopPan);
  }
};

const onPan = (e: MouseEvent) => {
  if (!isPanning.value || !workspaceDivRef.value) return;
  
  const dx = e.clientX - lastMousePos.value.x;
  const dy = e.clientY - lastMousePos.value.y;
  const currentX = panStartState.x + dx;
  const currentY = panStartState.y + dy;
  
  // Update start state for next frame
  panStartState.x = currentX;
  panStartState.y = currentY;
  lastMousePos.value = { x: e.clientX, y: e.clientY };

  // Direct DOM update for Workspace
  workspaceDivRef.value.style.transform = `translate(${currentX}px, ${currentY}px) scale(${workspaceScale.value})`;
  // Direct DOM update for Grid Background (Syncing)
  if (containerRef.value) {
      containerRef.value.style.backgroundPosition = `${currentX}px ${currentY}px`;
  }
};

const stopPan = () => {
  isPanning.value = false;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onPan);
  window.removeEventListener('mouseup', stopPan);
  
  // Sync reactive state with final DOM state
  workspaceX.value = panStartState.x;
  workspaceY.value = panStartState.y;
};

// --- Touch Panning & Zooming Logic ---
const initialPinchDist = ref(0);
const initialPinchScale = ref(1);

const startPanTouch = (e: TouchEvent) => {
  if (pinnedGraphId.value) return;
  
  // Only pan/zoom if interacting with the canvas background
  const target = e.target as HTMLElement;
  const isBackground = target.classList.contains('infinite-canvas') || target.tagName === 'svg' || target.classList.contains('workspace');
  
  if (isBackground) {
    isPanning.value = true;
    // Do not call e.preventDefault() here immediately if it blocks pinch-start, but for panning it's usually needed.
    // However, Vue's passive defaults might interfere.
    // e.preventDefault(); 

    if (e.touches.length === 2) {
      // Initial Pinch State
      initialPinchDist.value = Math.hypot(
        e.touches[0].clientX - e.touches[1].clientX,
        e.touches[0].clientY - e.touches[1].clientY
      );
      initialPinchScale.value = workspaceScale.value;
    } else {
      // Initial Pan State
      const touch = e.touches[0];
      lastMousePos.value = { x: touch.clientX, y: touch.clientY };
    }
    
    window.addEventListener('touchmove', onPanTouch, { passive: false });
    window.addEventListener('touchend', stopPanTouch);
  }
};

const onPanTouch = (e: TouchEvent) => {
  if (!isPanning.value || !workspaceDivRef.value) return;
  if (e.cancelable) e.preventDefault();
  
  if (e.touches.length === 2) {
    // Handle Pinch Zoom
    const dist = Math.hypot(
      e.touches[0].clientX - e.touches[1].clientX,
      e.touches[0].clientY - e.touches[1].clientY
    );
    
    if (initialPinchDist.value > 0) {
      const scale = dist / initialPinchDist.value;
      const newScale = Math.min(Math.max(0.1, initialPinchScale.value * scale), 5);
      
      // Zoom towards the center of the pinch
      const rect = containerRef.value!.getBoundingClientRect();
      const pinchCenter = {
        x: (e.touches[0].clientX + e.touches[1].clientX) / 2 - rect.left,
        y: (e.touches[0].clientY + e.touches[1].clientY) / 2 - rect.top
      };
      
      const worldX = (pinchCenter.x - workspaceX.value) / workspaceScale.value;
      const worldY = (pinchCenter.y - workspaceY.value) / workspaceScale.value;
      
      workspaceScale.value = newScale;
      workspaceX.value = pinchCenter.x - worldX * newScale;
      workspaceY.value = pinchCenter.y - worldY * newScale;
    }
  } else if (e.touches.length === 1) {
    // Handle Pan
    const touch = e.touches[0];
    const dx = touch.clientX - lastMousePos.value.x;
    const dy = touch.clientY - lastMousePos.value.y;
    
    workspaceX.value += dx;
    workspaceY.value += dy;
    
    lastMousePos.value = { x: touch.clientX, y: touch.clientY };
  }

  // Sync DOM
  workspaceDivRef.value.style.transform = `translate(${workspaceX.value}px, ${workspaceY.value}px) scale(${workspaceScale.value})`;
  if (containerRef.value) {
      containerRef.value.style.backgroundPosition = `${workspaceX.value}px ${workspaceY.value}px`;
      containerRef.value.style.backgroundSize = `${uiStore.workspaceGridSize * workspaceScale.value}px ${uiStore.workspaceGridSize * workspaceScale.value}px`;
  }
};

const stopPanTouch = (e: TouchEvent) => {
  // If fingers are lifted but one remains, reset lastMousePos for smooth continuation
  if (e.touches.length === 1) {
      lastMousePos.value = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      // Reset pinch dist as we are back to single finger
      initialPinchDist.value = 0;
      return;
  }
  if (e.touches.length === 0) {
      isPanning.value = false;
      window.removeEventListener('touchmove', onPanTouch);
      window.removeEventListener('touchend', stopPanTouch);
  }
};

const arrangeGraphs = (type: 'grid' | 'horizontal' | 'vertical') => {
    if (!currentProject.value || pinnedGraphId.value) return;
    const graphsToArrange = [...currentProject.value.graphs];
    if (graphsToArrange.length === 0) return;
    const gap = 40;
    let currentX = 100; 
    let currentY = 100;
    
    if (type === 'horizontal') {
        graphsToArrange.forEach(g => {
            projectStore.updateGraphLayout(currentProject.value!.id, g.id, { x: currentX, y: 100 });
            if (g.showCodePanel) {
                projectStore.updateGraphLayout(currentProject.value!.id, g.id, { 
                    codePanelX: currentX, 
                    codePanelY: 100 + g.height + gap 
                });
            }
            currentX += Math.max(g.width, (g.showCodePanel ? (g.codePanelWidth || 400) : 0)) + gap;
        });
    } else if (type === 'vertical') {
        graphsToArrange.forEach(g => {
            projectStore.updateGraphLayout(currentProject.value!.id, g.id, { x: 100, y: currentY });
            if (g.showCodePanel) {
                projectStore.updateGraphLayout(currentProject.value!.id, g.id, { 
                    codePanelX: 100 + g.width + gap, 
                    codePanelY: currentY 
                });
            }
            currentY += Math.max(g.height, (g.showCodePanel ? (g.codePanelHeight || 400) : 0)) + gap;
        });
    } else if (type === 'grid') {
        const cols = Math.ceil(Math.sqrt(graphsToArrange.length));
        let rowHeight = 0;
        
        graphsToArrange.forEach((g, i) => {
            if (i > 0 && i % cols === 0) {
                currentX = 100;
                currentY += rowHeight + gap;
                rowHeight = 0;
            }
            
            projectStore.updateGraphLayout(currentProject.value!.id, g.id, { x: currentX, y: currentY });
            if (g.showCodePanel) {
                 projectStore.updateGraphLayout(currentProject.value!.id, g.id, {
                     codePanelX: currentX + g.width + 20,
                     codePanelY: currentY
                 });
                 currentX += (g.codePanelWidth || 400) + 20;
            }
            
            currentX += g.width + gap;
            const totalH = Math.max(g.height, g.showCodePanel ? (g.codePanelHeight || 400) : 0);
            if (totalH > rowHeight) rowHeight = totalH;
        });
    }
    
    workspaceX.value = 50;
    workspaceY.value = 50;
    workspaceScale.value = Math.min(1, window.innerWidth / (currentX + 200)); 
};

const startDragItem = (e: MouseEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
  if (pinnedGraphId.value) return;
  e.stopPropagation();
  if (type === 'graph' && currentGraphId.value !== id) {
    graphStore.selectGraph(id);
  }
  dragTarget.value = id;
  dragType.value = type;
  dragStart.value = { x: e.clientX, y: e.clientY };
  initialLayout.value = itemLayout;
  window.addEventListener('mousemove', onDragItem);
  window.addEventListener('mouseup', stopDragItem);
};

const onDragItem = (e: MouseEvent) => {
  if (!dragTarget.value || !dragType.value) return;
  
  if (rAF) return;
  
  rAF = requestAnimationFrame(() => {
      const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
      const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
      if (currentProject.value) {
        // Use { save: false } to prevent JSON stringify on every frame
        if (dragType.value === 'graph') {
            projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value!, {
                x: initialLayout.value.x + dx,
                y: initialLayout.value.y + dy
            }, false);
        } else {
            projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value!, {
                codePanelX: initialLayout.value.x + dx,
                codePanelY: initialLayout.value.y + dy
            }, false);
        }
      }
      rAF = null;
  });
};

const stopDragItem = () => {
  // Save project state once at the end of the drag
  const targetId = dragTarget.value;
  const type = dragType.value;

  if (targetId) {
      projectStore.saveProjects();
      
      // Fix for Cytoscape hit detection after move: force resize to update container bounds in Cytoscape's cache
      if (type === 'graph') {
          const cy = getCyInstance(targetId);
          if (cy) {
              cy.resize();
          }
      }
  }
  dragTarget.value = null;
  dragType.value = null;
  if (rAF) { cancelAnimationFrame(rAF); rAF = null; }
  window.removeEventListener('mousemove', onDragItem);
  window.removeEventListener('mouseup', stopDragItem);
};

// --- Touch Dragging Logic ---
const startDragItemTouch = (e: TouchEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
  if (pinnedGraphId.value) return;
  e.stopPropagation();
  if (type === 'graph' && currentGraphId.value !== id) {
    graphStore.selectGraph(id);
  }
  dragTarget.value = id;
  dragType.value = type;
  const touch = e.touches[0];
  dragStart.value = { x: touch.clientX, y: touch.clientY };
  initialLayout.value = itemLayout;
  window.addEventListener('touchmove', onDragItemTouch, { passive: false });
  window.addEventListener('touchend', stopDragItemTouch);
};

const onDragItemTouch = (e: TouchEvent) => {
  if (!dragTarget.value || !dragType.value) return;
  if (e.cancelable) e.preventDefault();
  if (rAF) return;
  
  const touch = e.touches[0];
  rAF = requestAnimationFrame(() => {
      const dx = (touch.clientX - dragStart.value.x) / workspaceScale.value;
      const dy = (touch.clientY - dragStart.value.y) / workspaceScale.value;
      if (currentProject.value) {
        if (dragType.value === 'graph') {
            projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value!, {
                x: initialLayout.value.x + dx,
                y: initialLayout.value.y + dy
            }, false);
        } else {
            projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value!, {
                codePanelX: initialLayout.value.x + dx,
                codePanelY: initialLayout.value.y + dy
            }, false);
        }
      }
      rAF = null;
  });
};

const stopDragItemTouch = () => {
  const targetId = dragTarget.value;
  const type = dragType.value;

  if (targetId) {
      projectStore.saveProjects();
      
      // Fix for Cytoscape hit detection after move
      if (type === 'graph') {
          const cy = getCyInstance(targetId);
          if (cy) {
              cy.resize();
          }
      }
  }
  dragTarget.value = null;
  dragType.value = null;
  if (rAF) { cancelAnimationFrame(rAF); rAF = null; }
  window.removeEventListener('touchmove', onDragItemTouch);
  window.removeEventListener('touchend', stopDragItemTouch);
};

const startResizeItem = (e: MouseEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
  if (pinnedGraphId.value) return;
  e.stopPropagation();
  e.preventDefault();
  resizeTarget.value = id;
  resizeType.value = type;
  dragStart.value = { x: e.clientX, y: e.clientY };
  initialLayout.value = itemLayout;
  window.addEventListener('mousemove', onResizeItem);
  window.addEventListener('mouseup', stopResizeItem);
};

const onResizeItem = (e: MouseEvent) => {
  if (!resizeTarget.value || !resizeType.value) return;
  if (rAF) return;

  rAF = requestAnimationFrame(() => {
      const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
      const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
      const newWidth = Math.max(300, initialLayout.value.width + dx);
      const newHeight = Math.max(200, initialLayout.value.height + dy);
      if (currentProject.value) {
          // Skip save
          if (resizeType.value === 'graph') {
            projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value!, {
                width: newWidth,
                height: newHeight
            }, false);
          } else {
            projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value!, {
                codePanelWidth: newWidth,
                codePanelHeight: newHeight
            }, false);
          }
      }
      rAF = null;
  });
};

const stopResizeItem = () => {
  // Save on stop
  if (resizeTarget.value) {
      projectStore.saveProjects();
  }
  resizeTarget.value = null;
  resizeType.value = null;
  if (rAF) { cancelAnimationFrame(rAF); rAF = null; }
  window.removeEventListener('mousemove', onResizeItem);
  window.removeEventListener('mouseup', stopResizeItem);
};

// --- Touch Resizing Logic ---
const startResizeItemTouch = (e: TouchEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
  if (pinnedGraphId.value) return;
  e.stopPropagation();
  resizeTarget.value = id;
  resizeType.value = type;
  const touch = e.touches[0];
  dragStart.value = { x: touch.clientX, y: touch.clientY };
  initialLayout.value = itemLayout;
  window.addEventListener('touchmove', onResizeItemTouch, { passive: false });
  window.addEventListener('touchend', stopResizeItemTouch);
};

const onResizeItemTouch = (e: TouchEvent) => {
  if (!resizeTarget.value || !resizeType.value) return;
  if (e.cancelable) e.preventDefault();
  if (rAF) return;

  const touch = e.touches[0];
  rAF = requestAnimationFrame(() => {
      const dx = (touch.clientX - dragStart.value.x) / workspaceScale.value;
      const dy = (touch.clientY - dragStart.value.y) / workspaceScale.value;
      const newWidth = Math.max(300, initialLayout.value.width + dx);
      const newHeight = Math.max(200, initialLayout.value.height + dy);
      if (currentProject.value) {
          if (resizeType.value === 'graph') {
            projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value!, {
                width: newWidth,
                height: newHeight
            }, false);
          } else {
            projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value!, {
                codePanelWidth: newWidth,
                codePanelHeight: newHeight
            }, false);
          }
      }
      rAF = null;
  });
};

const stopResizeItemTouch = () => {
  if (resizeTarget.value) {
      projectStore.saveProjects();
  }
  resizeTarget.value = null;
  resizeType.value = null;
  if (rAF) { cancelAnimationFrame(rAF); rAF = null; }
  window.removeEventListener('touchmove', onResizeItemTouch);
  window.removeEventListener('touchend', stopResizeItemTouch);
};

const activateGraph = (graphId: string) => {
  if (currentGraphId.value !== graphId) {
    graphStore.selectGraph(graphId);
  }
};

const togglePinGraph = (graphId: string) => {
    if (pinnedGraphId.value === graphId) {
        uiStore.setPinnedGraph(null); // Unpin via store
    } else {
        uiStore.setPinnedGraph(graphId); // Pin via store
        graphStore.selectGraph(graphId);
    }
};

const connectorPath = (g: GraphMeta) => {
    if (!g.showCodePanel || pinnedGraphId.value) return '';
    const sX = g.x;
    const sY = g.y;
    const sW = g.width;
    const sH = g.height;
    const tX = g.codePanelX ?? (g.x + g.width + 20);
    const tY = g.codePanelY ?? g.y;
    const tW = g.codePanelWidth ?? 400;
    const tH = g.codePanelHeight ?? (g.height || 400);
    const sCx = sX + sW / 2;
    const sCy = sY + sH / 2;
    const tCx = tX + tW / 2;
    const tCy = tY + tH / 2;
    const dx = tCx - sCx;
    const dy = tCy - sCy;
    let start = { x: 0, y: 0 };
    let end = { x: 0, y: 0 };
    let control1 = { x: 0, y: 0 };
    let control2 = { x: 0, y: 0 };
    if (Math.abs(dx) > Math.abs(dy) * 1.2) {
        if (dx > 0) {
            start = { x: sX + sW, y: sCy };
            end = { x: tX, y: tCy };
            const dist = (end.x - start.x) / 2;
            control1 = { x: start.x + dist, y: start.y };
            control2 = { x: end.x - dist, y: end.y };
        } else {
            start = { x: sX, y: sCy };
            end = { x: tX + tW, y: tCy };
            const dist = (start.x - end.x) / 2;
            control1 = { x: start.x - dist, y: start.y };
            control2 = { x: end.x + dist, y: end.y };
        }
    } else {
        if (dy > 0) {
            start = { x: sCx, y: sY + sH };
            end = { x: tCx, y: tY };
            const dist = (end.y - start.y) / 2;
            control1 = { x: start.x, y: start.y + dist };
            control2 = { x: end.x, y: end.y - dist };
        } else {
            start = { x: sCx, y: sY };
            end = { x: tCx, y: tY + tH };
            const dist = (start.y - end.y) / 2;
            control1 = { x: start.x, y: start.y - dist };
            control2 = { x: end.x, y: end.y + dist };
        }
    }
    return `M ${start.x} ${start.y} C ${control1.x} ${control1.y}, ${control2.x} ${control2.y}, ${end.x} ${end.y}`;
};

const toggleCodePanel = (graph: GraphMeta) => {
    if (currentProject.value) {
        projectStore.updateGraphLayout(currentProject.value.id, graph.id, { showCodePanel: !graph.showCodePanel });
    }
};

const exportGraph = (graphId: string, format: 'png' | 'jpg' | 'svg') => {
    graphStore.selectGraph(graphId);
    emit('open-export-modal', format);
};

// Workspace Controls
const zoomIn = () => {
    if (pinnedGraphId.value) {
        zoomGraph(pinnedGraphId.value, 1.2);
    } else {
        workspaceScale.value = Math.min(workspaceScale.value + 0.1, 5);
    }
};
const zoomOut = () => {
    if (pinnedGraphId.value) {
        zoomGraph(pinnedGraphId.value, 0.8);
    } else {
        workspaceScale.value = Math.max(workspaceScale.value - 0.1, 0.1);
    }
};
const handleFit = () => {
    if (pinnedGraphId.value) {
        fitGraph(pinnedGraphId.value);
    } else {
        fitAll();
    }
};

const fitAll = () => {
    if (graphs.value.length === 0) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    
    graphs.value.forEach(g => {
        const gx2 = g.x + g.width;
        const gy2 = g.y + g.height;
        if (g.x < minX) minX = g.x;
        if (g.y < minY) minY = g.y;
        if (gx2 > maxX) maxX = gx2;
        if (gy2 > maxY) maxY = gy2;

        if (g.showCodePanel) {
            const cx = g.codePanelX || (g.x + g.width + 20);
            const cy = g.codePanelY || g.y;
            const cw = g.codePanelWidth || 400;
            const ch = g.codePanelHeight || g.height;
            if (cx < minX) minX = cx;
            if (cy < minY) minY = cy;
            if (cx + cw > maxX) maxX = cx + cw;
            if (cy + ch > maxY) maxY = cy + ch;
        }
    });
    
    const padding = 50;
    const width = maxX - minX + padding * 2;
    const height = maxY - minY + padding * 2;
    
    if (containerRef.value) {
        const containerW = containerRef.value.clientWidth;
        const containerH = containerRef.value.clientHeight;
        
        const scaleX = containerW / width;
        const scaleY = containerH / height;
        
        workspaceScale.value = Math.min(scaleX, scaleY, 1);
        workspaceX.value = -minX * workspaceScale.value + padding;
        workspaceY.value = -minY * workspaceScale.value + padding;
    }
};

// Handle Undo/Redo at MultiView level to distribute to active graph
const handleUndo = () => {
    if (currentGraphId.value) {
        const ur = getUndoRedoInstance(currentGraphId.value);
        if (ur) ur.undo();
    }
};

const handleRedo = () => {
    if (currentGraphId.value) {
        const ur = getUndoRedoInstance(currentGraphId.value);
        if (ur) ur.redo();
    }
};

// Watch elementToFocus to trigger zoom (Validation click logic)
// This only triggers when explicitly asked to focus on an element (e.g. via validation panel)
watch(elementToFocus, (newEl) => {
    if (newEl && newEl.type === 'node') {
        // If we have a focus request, verify if we need to switch contexts
        // If currently pinned, and target element belongs to another graph, unpin
        if (pinnedGraphId.value && currentGraphId.value && pinnedGraphId.value !== currentGraphId.value) {
             togglePinGraph(pinnedGraphId.value); // Unpin
        }

        // Zoom logic
        // For multi-view workspace:
        if (!pinnedGraphId.value && currentGraphId.value) {
            const graph = currentProject.value?.graphs.find(g => g.id === currentGraphId.value);
            if (graph) {
                // Center workspace on the graph card
                const containerW = containerRef.value?.clientWidth || 1000;
                const containerH = containerRef.value?.clientHeight || 800;
                
                const targetX = -(graph.x + graph.width / 2) * workspaceScale.value + containerW / 2;
                const targetY = -(graph.y + graph.height / 2) * workspaceScale.value + containerH / 2;
                
                // Animate workspace pan
                workspaceX.value = targetX;
                workspaceY.value = targetY;
                
                // Trigger internal graph zoom to node
                const cy = getCyInstance(currentGraphId.value);
                if (cy) {
                    cy.animate({
                        fit: { eles: cy.getElementById(newEl.id), padding: 50 },
                        duration: 500
                    });
                }
            }
        } else if (pinnedGraphId.value && currentGraphId.value === pinnedGraphId.value) {
             // We are inside the pinned graph, just zoom to node
             const cy = getCyInstance(pinnedGraphId.value);
             if (cy) {
                 cy.animate({
                     fit: { eles: cy.getElementById(newEl.id), padding: 50 },
                     duration: 500
                 });
             }
        }
    }
});

watch(pinnedGraphId, (newId) => {
    nextTick(() => {
        if (newId) {
            const cy = getCyInstance(newId);
            if (cy) {
                cy.resize();
                cy.fit(undefined, 50);
            }
        } else {
            setTimeout(() => fitAll(), 100);
        }
    });
});

onMounted(() => {
    if (graphs.value.length > 0) {
        workspaceX.value = 50;
        workspaceY.value = 50;
    }
    if (pinnedGraphId.value) {
        setTimeout(() => {
            const cy = getCyInstance(pinnedGraphId.value!);
            if (cy) {
                cy.resize();
                cy.fit(undefined, 50);
            }
        }, 300);
    } else {
        // Ensure graphs are visible on load if unpinned
        setTimeout(() => fitAll(), 100);
    }
});

onUnmounted(() => {
    if (rAF) cancelAnimationFrame(rAF);
    window.removeEventListener('mousemove', onPan);
    window.removeEventListener('mouseup', stopPan);
    window.removeEventListener('mousemove', onDragItem);
    window.removeEventListener('mouseup', stopDragItem);
    window.removeEventListener('mousemove', onResizeItem);
    window.removeEventListener('mouseup', stopResizeItem);
    
    window.removeEventListener('touchmove', onPanTouch);
    window.removeEventListener('touchend', stopPanTouch);
    window.removeEventListener('touchmove', onDragItemTouch);
    window.removeEventListener('touchend', stopDragItemTouch);
    window.removeEventListener('touchmove', onResizeItemTouch);
    window.removeEventListener('touchend', stopResizeItemTouch);
});
</script>

<template>
  <div class="infinite-canvas-container" ref="containerRef">
    <div 
      class="infinite-canvas" 
      @mousedown="startPan"
      @touchstart="startPanTouch"
      @wheel="handleWheel"
      :class="{
        'grid-dots': uiStore.isWorkspaceGridEnabled && uiStore.workspaceGridStyle === 'dots' && !pinnedGraphId, 
        'grid-lines': uiStore.isWorkspaceGridEnabled && uiStore.workspaceGridStyle === 'lines' && !pinnedGraphId
      }"
      :style="{
        backgroundPosition: pinnedGraphId ? '0 0' : `${workspaceX}px ${workspaceY}px`,
        backgroundSize: pinnedGraphId ? 'auto' : `${uiStore.workspaceGridSize * workspaceScale}px ${uiStore.workspaceGridSize * workspaceScale}px`,
        backgroundColor: pinnedGraphId ? 'var(--theme-bg-canvas)' : 'var(--theme-bg-canvas)'
      }"
    >
      <div 
        class="workspace"
        ref="workspaceDivRef"
        :style="{
          transform: pinnedGraphId ? 'none' : `translate(${workspaceX}px, ${workspaceY}px) scale(${workspaceScale})`,
          width: pinnedGraphId ? '100%' : '0',
          height: pinnedGraphId ? '100%' : '0',
          position: pinnedGraphId ? 'fixed' : 'absolute'
        }"
      >
        <!-- Connectors (Only in multi view) -->
        <svg class="connectors-layer" v-if="!pinnedGraphId">
            <path v-for="graph in graphs" :key="graph.id + 'path'"
                  :d="connectorPath(graph)"
                  fill="none"
                  stroke="#4299e1"
                  stroke-width="2"
                  stroke-dasharray="5,5"
                  marker-end="url(#arrowhead)"
            />
            <defs>
                <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
                    <polygon points="0 0, 10 3.5, 0 7" fill="#4299e1" />
                </marker>
            </defs>
        </svg>

        <div 
          v-for="graph in graphs" 
          :key="graph.id"
          class="graph-card glass-panel"
          :class="{ 
              'active': currentGraphId === graph.id, 
              'fixed-fullscreen': pinnedGraphId === graph.id,
              'hidden': pinnedGraphId && pinnedGraphId !== graph.id 
          }"
          :style="pinnedGraphId === graph.id ? {} : {
            left: `${graph.x}px`,
            top: `${graph.y}px`,
            width: `${graph.width}px`,
            height: `${graph.height}px`,
            zIndex: currentGraphId === graph.id ? 10 : 1
          }"
          @mousedown="activateGraph(graph.id)"
          @touchstart="activateGraph(graph.id)"
        >
          <!-- Header: Hidden when pinned -->
          <div class="graph-header" v-if="!pinnedGraphId" 
               @mousedown="startDragItem($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})"
               @touchstart.stop="startDragItemTouch($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})"
          >
            <span class="graph-title">{{ graph.name }}</span>
            <div class="header-actions">
                <button class="icon-btn pin-btn" 
                        @click.stop="togglePinGraph(graph.id)" 
                        @touchstart.stop="togglePinGraph(graph.id)"
                        title="Pin to Fullscreen">
                    <i class="fas fa-expand"></i>
                </button>
                
                <!-- Graph Layout Dropdown -->
                <DropdownMenu class="layout-menu">
                    <template #trigger>
                        <button class="icon-btn" title="Graph Layout" @mousedown.stop @touchstart.stop>
                            <i class="fas fa-sitemap"></i>
                        </button>
                    </template>
                    <template #content>
                        <div class="dropdown-section-title">Layout</div>
                        <a href="#" @click.prevent="handleGraphLayout('dagre', graph.id)">Dagre</a>
                        <a href="#" @click.prevent="handleGraphLayout('fcose', graph.id)">fCoSE</a>
                        <a href="#" @click.prevent="handleGraphLayout('cola', graph.id)">Cola</a>
                        <a href="#" @click.prevent="handleGraphLayout('klay', graph.id)">KLay</a>
                        <a href="#" @click.prevent="handleGraphLayout('preset', graph.id)">Reset</a>
                    </template>
                </DropdownMenu>

                <span class="node-count-badge"
                      @mouseenter="handleBadgeEnter($event, graph.id)" 
                      @mousemove="handleBadgeMove"
                      @mouseleave="handleBadgeLeave">
                    {{ getElementsForGraph(graph.id).filter(el => el.type === 'node').length }} nodes
                </span>
                
                <DropdownMenu class="header-menu">
                    <template #trigger>
                        <button class="icon-btn"><i class="fas fa-ellipsis-v"></i></button>
                    </template>
                    <template #content>
                        <div class="dropdown-section-title">Grid Settings</div>
                        <div class="grid-settings-menu p-2" @click.stop>
                            <div class="grid-settings-item">
                                <label class="text-sm font-medium text-left flex-grow">Show Grid</label>
                                <ToggleSwitch 
                                    :modelValue="resolveGrid(graph).enabled" 
                                    @update:modelValue="(val: boolean) => updateGraphGridEnabled(graph.id, val)" 
                                />
                            </div>
                            <div class="grid-settings-item">
                                <label class="text-sm font-medium text-left flex-grow">Style</label>
                                <BaseSelect 
                                    :modelValue="resolveGrid(graph).style" 
                                    :options="gridStyleOptions" 
                                    @update:modelValue="(val: string) => updateGraphGridStyle(graph.id, val as GridStyle)"
                                    class="compact-select w-24"
                                />
                            </div>
                            <div class="grid-settings-item">
                                <label class="text-sm font-medium text-left flex-grow">Size</label>
                                <InputNumber 
                                    :modelValue="resolveGrid(graph).size" 
                                    @update:modelValue="(val: number) => updateGraphGridSize(graph.id, val)" 
                                    showButtons 
                                    buttonLayout="stacked" 
                                    :step="5" :min="5" :max="100" 
                                    decrementButtonIcon="pi pi-angle-down"
                                    incrementButtonIcon="pi pi-angle-up"
                                    class="grid-size-input-small w-16"
                                />
                            </div>
                        </div>
                        <div class="dropdown-divider"></div>
                        <a href="#" @click.prevent="toggleCodePanel(graph)">
                            <i :class="graph.showCodePanel ? 'fas fa-eye-slash' : 'fas fa-code'"></i> {{ graph.showCodePanel ? 'Hide Code' : 'Pop-out Code' }}
                        </a>
                        <div class="dropdown-divider"></div>
                        <a href="#" @click.prevent="exportGraph(graph.id, 'png')"><i class="fas fa-image"></i> Export PNG</a>
                        <a href="#" @click.prevent="exportGraph(graph.id, 'svg')"><i class="fas fa-vector-square"></i> Export SVG</a>
                        <a href="#" @click.prevent="exportGraph(graph.id, 'jpg')"><i class="fas fa-file-image"></i> Export JPG</a>
                    </template>
                </DropdownMenu>
            </div>
          </div>
          
          <div class="graph-content">
            <GraphEditor 
              v-if="pinnedGraphId === graph.id || currentGraphId === graph.id"
              :graph-id="graph.id"
              :is-grid-enabled="resolveGrid(graph).enabled"
              @update:is-grid-enabled="(val: boolean) => updateGraphGridEnabled(graph.id, val)"
              :grid-size="resolveGrid(graph).size"
              @update:grid-size="(val: number) => updateGraphGridSize(graph.id, val)"
              :grid-style="resolveGrid(graph).style"
              :current-mode="currentMode"
              :elements="getElementsForGraph(graph.id)"
              :current-node-type="currentNodeType"
              :validation-errors="validationErrors"
              :show-zoom-controls="false" 
              @update:current-mode="$emit('update:currentMode', $event)"
              @update:current-node-type="$emit('update:currentNodeType', $event)"
              @element-selected="$emit('element-selected', $event)"
              @layout-updated="$emit('layout-updated', $event)"
            />
            <div v-else class="preview-wrapper">
                <div class="preview-blocker"></div>
                <GraphPreview 
                  :elements="getElementsForGraph(graph.id)"
                  :graph-id="graph.id" 
                  :is-grid-enabled="resolveGrid(graph).enabled"
                  :grid-size="resolveGrid(graph).size"
                  :grid-style="resolveGrid(graph).style"
                />
            </div>
          </div>

          <div class="resize-handle" v-if="!pinnedGraphId" 
               @mousedown="startResizeItem($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})"
               @touchstart.stop.prevent="startResizeItemTouch($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})"
          >
            <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
          </div>
        </div>

        <!-- Pop-out Code Panels (Hidden in Pinned Mode) -->
        <template v-if="!pinnedGraphId">
            <template v-for="graph in graphs" :key="graph.id + 'code'">
                <div v-if="graph.showCodePanel" 
                     class="code-panel-card glass-panel"
                     :class="{ 'active': currentGraphId === graph.id }"
                     :style="{
                        left: `${graph.codePanelX ?? (graph.x + graph.width + 20)}px`,
                        top: `${graph.codePanelY ?? graph.y}px`,
                        width: `${graph.codePanelWidth ?? 400}px`,
                        height: `${graph.codePanelHeight ?? graph.height}px`,
                        zIndex: currentGraphId === graph.id ? 9 : 1
                     }"
                     @mousedown="activateGraph(graph.id)"
                     @touchstart="activateGraph(graph.id)"
                >
                    <div class="graph-header code-header" 
                         @mousedown="startDragItem($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})"
                         @touchstart.stop="startDragItemTouch($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})"
                    >
                        <span class="graph-title"><i class="fas fa-code"></i> {{ graph.name }} (Code)</span>
                        <button class="close-btn" @click="toggleCodePanel(graph)"><i class="fas fa-times"></i></button>
                    </div>
                    <div class="code-content">
                        <CodePreviewPanel :is-active="true" :graph-id="graph.id" />
                    </div>
                    <div class="resize-handle" 
                         @mousedown="startResizeItem($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})"
                         @touchstart.stop.prevent="startResizeItemTouch($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})"
                    >
                        <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
                    </div>
                </div>
            </template>
        </template>

      </div>
    </div>

    <!-- Node Count Tooltip -->
    <div v-if="showTooltip && !pinnedGraphId" class="node-tooltip" :style="{ left: tooltipPos.x + 15 + 'px', top: tooltipPos.y + 15 + 'px' }">
        <div v-if="hoveredGraphId && getNodeBreakdownArray(hoveredGraphId).length === 0">No nodes</div>
        <div v-else>
            <div v-for="item in getNodeBreakdownArray(hoveredGraphId!)" :key="item.type">
                <strong>{{ item.type }}:</strong> {{ item.count }}
            </div>
        </div>
    </div>

    <!-- Bottom Floating Tool Dock -->
    <FloatingBottomToolbar 
        :current-mode="currentMode"
        :current-node-type="currentNodeType"
        :show-workspace-controls="true"
        :is-pinned="!!pinnedGraphId"
        @update:current-mode="$emit('update:currentMode', $event)"
        @update:current-node-type="$emit('update:currentNodeType', $event)"
        @undo="handleUndo"
        @redo="handleRedo"
        @zoom-in="zoomIn"
        @zoom-out="zoomOut"
        @fit="handleFit"
        @arrange="arrangeGraphs"
        @layout-graph="handleGraphLayout"
    />
  </div>
</template>

<style scoped>
.infinite-canvas-container {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background-color: var(--theme-bg-canvas);
}

.infinite-canvas {
  width: 100%;
  height: 100%;
  cursor: grab;
  touch-action: none; /* Critical for iPad touch handling */
}

.infinite-canvas.grid-dots {
    background-image: radial-gradient(circle, var(--theme-grid-line) 1px, transparent 1px);
}

.infinite-canvas.grid-lines {
    background-image: 
        linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
        linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px);
}

.infinite-canvas:active {
  cursor: grabbing;
}

.workspace {
  position: absolute;
  top: 0;
  left: 0;
  transform-origin: 0 0;
  width: 0; 
  height: 0;
}

.connectors-layer {
    position: absolute;
    top: 0;
    left: 0;
    width: 100000px;
    height: 100000px;
    pointer-events: none;
    overflow: visible;
    z-index: 0;
}

.graph-card, .code-panel-card {
  position: absolute;
  background-color: var(--theme-bg-panel);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-md);
  display: flex;
  flex-direction: column;
  border: 1px solid var(--theme-border);
  overflow: visible; 
  transition: box-shadow 0.2s;
  /* Removed top/left transitions for drag performance */
}

/* Fixed Fullscreen Mode */
.fixed-fullscreen {
    position: fixed !important;
    top: 0 !important;
    left: 0 !important;
    width: 100vw !important;
    height: 100vh !important;
    z-index: 10 !important;
    border-radius: 0 !important;
    border: none !important;
}

.hidden {
    display: none;
}

.graph-card.active, .code-panel-card.active {
  box-shadow: var(--shadow-floating);
  border-color: var(--theme-primary);
  outline: 2px solid rgba(59, 130, 246, 0.2);
}

.fixed-fullscreen.active {
    outline: none;
    box-shadow: none;
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

.code-header {
    background-color: #1f2937;
    color: white;
}
.code-header .graph-title {
    color: white;
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

.header-actions {
    display: flex;
    align-items: center;
    gap: 6px;
}

.node-count-badge {
    font-size: 10px;
    background: var(--theme-bg-active);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    color: var(--theme-text-secondary);
    cursor: help;
    user-select: none;
}

.icon-btn {
    background: transparent;
    border: none;
    color: var(--theme-text-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: var(--radius-sm);
    font-size: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
}
.icon-btn:hover {
    background: var(--theme-bg-active);
    color: var(--theme-text-primary);
}

.pin-active {
    width: auto;
    padding: 4px 8px;
    gap: 4px;
    color: var(--theme-primary);
}

.pin-btn:hover, .pin-btn.active {
    color: var(--theme-primary);
    background: var(--theme-bg-active);
}

.close-btn {
    background: transparent;
    border: none;
    color: rgba(255,255,255,0.7);
    cursor: pointer;
    font-size: 13px;
}
.close-btn:hover {
    color: white;
}

.graph-content, .code-content {
  flex: 1;
  position: relative;
  overflow: hidden;
  background-color: var(--theme-bg-panel);
  display: flex;
  flex-direction: column;
  border-bottom-left-radius: var(--radius-md);
  border-bottom-right-radius: var(--radius-md);
}

/* Remove border radius when fullscreen */
.fixed-fullscreen .graph-content {
    border-radius: 0;
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

.preview-wrapper {
    width: 100%;
    height: 100%;
    position: relative;
    display: flex;
    flex-direction: column;
    flex-grow: 1;
}

.preview-blocker {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 2; 
    background: transparent; 
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

/* Node Tooltip */
.node-tooltip {
    position: fixed;
    background: rgba(0, 0, 0, 0.85);
    color: white;
    padding: 8px 12px;
    border-radius: 6px;
    font-size: 12px;
    z-index: 1000;
    pointer-events: none;
    box-shadow: var(--shadow-floating);
}

/* Dropdown grid settings */
.grid-settings-menu {
    font-size: 0.85rem;
    min-width: 200px;
}

.grid-settings-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
    gap: 8px;
}

.compact-select {
    width: auto !important;
    min-width: 80px;
}

.compact-select :deep(.p-select-label) {
    padding: 4px 8px;
    font-size: 0.8rem;
}

.grid-size-input-small {
    height: 30px;
    width: 3rem !important;
}

.grid-size-input-small :deep(.p-inputnumber-input) {
    width: 100% !important;
    padding: 0 0.25rem !important;
    font-size: 0.8rem;
    text-align: left;
}

.grid-size-input-small :deep(.p-inputnumber-button) {
    width: 1.2rem !important;
    padding: 0 !important;
}
</style>
