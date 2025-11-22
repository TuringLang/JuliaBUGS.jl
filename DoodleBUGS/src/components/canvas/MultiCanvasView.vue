<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { storeToRefs } from 'pinia';
import GraphEditor from './GraphEditor.vue';
import GraphPreview from './GraphPreview.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import { useProjectStore, type GraphMeta } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import type { GraphElement, GraphNode, NodeType, ValidationError } from '../../types';
import DropdownMenu from '../common/DropdownMenu.vue';

defineProps<{
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
}>();

const projectStore = useProjectStore();
const graphStore = useGraphStore();
const uiStore = useUiStore();
const { currentProject } = storeToRefs(projectStore);
const { currentGraphId } = storeToRefs(graphStore);

// --- Workspace State ---
const workspaceX = ref(0);
const workspaceY = ref(0);
const workspaceScale = ref(1);
const isPanning = ref(false);
const lastMousePos = ref({ x: 0, y: 0 });
const containerRef = ref<HTMLElement | null>(null);

// --- Controls State ---
const controlsRef = ref<HTMLElement | null>(null);
const isControlsDragging = ref(false);
const controlsPos = ref({ left: '50%', bottom: '20px', top: 'auto', transform: 'translateX(-50%)' });
const controlsDragOffset = ref({ x: 0, y: 0 });

// --- Graph/Panel Drag/Resize State ---
const dragTarget = ref<string | null>(null); // ID of graph or code panel
const dragType = ref<'graph' | 'code' | null>(null);
const resizeTarget = ref<string | null>(null);
const resizeType = ref<'graph' | 'code' | null>(null);
const dragStart = ref({ x: 0, y: 0 });
const initialLayout = ref({ x: 0, y: 0, width: 0, height: 0 });

// --- Tooltip State ---
const hoveredGraphId = ref<string | null>(null);
const tooltipPos = ref({ x: 0, y: 0 });
const showTooltip = ref(false);

const graphs = computed(() => currentProject.value?.graphs || []);

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

// --- Workspace Interactions ---

const handleWheel = (e: WheelEvent) => {
  const target = e.target as HTMLElement;
  const closestCard = target.closest('.graph-card') || target.closest('.code-panel-card');
  
  // If over an active card content, allow internal scroll/zoom
  if (closestCard && closestCard.classList.contains('active') && (target.closest('.graph-content') || target.closest('.code-preview-wrapper'))) {
      return; 
  }

  if (e.ctrlKey || e.metaKey) {
    e.preventDefault();
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
  } else {
    e.preventDefault();
    workspaceX.value -= e.deltaX;
    workspaceY.value -= e.deltaY;
  }
};

const startPan = (e: MouseEvent) => {
  if ((e.target as HTMLElement).classList.contains('infinite-canvas') || (e.target as HTMLElement).tagName === 'svg') {
    isPanning.value = true;
    lastMousePos.value = { x: e.clientX, y: e.clientY };
    document.body.style.cursor = 'grabbing';
    window.addEventListener('mousemove', onPan);
    window.addEventListener('mouseup', stopPan);
  }
};

const onPan = (e: MouseEvent) => {
  if (!isPanning.value) return;
  const dx = e.clientX - lastMousePos.value.x;
  const dy = e.clientY - lastMousePos.value.y;
  workspaceX.value += dx;
  workspaceY.value += dy;
  lastMousePos.value = { x: e.clientX, y: e.clientY };
};

const stopPan = () => {
  isPanning.value = false;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onPan);
  window.removeEventListener('mouseup', stopPan);
};

// --- Controls Dragging ---

const startControlsDrag = (e: MouseEvent) => {
    if (!controlsRef.value) return;
    if ((e.target as HTMLElement).closest('button')) return;

    isControlsDragging.value = true;
    const rect = controlsRef.value.getBoundingClientRect();
    
    if (controlsPos.value.transform) {
        controlsPos.value = {
            left: `${rect.left}px`,
            top: `${rect.top}px`,
            bottom: 'auto',
            transform: 'none'
        };
    }

    controlsDragOffset.value = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
    };

    window.addEventListener('mousemove', onControlsDrag);
    window.addEventListener('mouseup', stopControlsDrag);
};

const onControlsDrag = (e: MouseEvent) => {
    if (!isControlsDragging.value) return;
    const x = e.clientX - controlsDragOffset.value.x;
    const y = e.clientY - controlsDragOffset.value.y;
    
    controlsPos.value = {
        left: `${x}px`,
        top: `${y}px`,
        bottom: 'auto',
        transform: 'none'
    };
};

const stopControlsDrag = () => {
    isControlsDragging.value = false;
    window.removeEventListener('mousemove', onControlsDrag);
    window.removeEventListener('mouseup', stopControlsDrag);
};

// --- Layout Arrangement ---

const arrangeGraphs = (type: 'grid' | 'horizontal' | 'vertical') => {
    if (!currentProject.value) return;
    
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

// --- Generic Drag/Resize Logic ---

const startDragItem = (e: MouseEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
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
  const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
  const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
  
  if (currentProject.value) {
    if (dragType.value === 'graph') {
        projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value, {
            x: initialLayout.value.x + dx,
            y: initialLayout.value.y + dy
        });
    } else {
        projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value, {
            codePanelX: initialLayout.value.x + dx,
            codePanelY: initialLayout.value.y + dy
        });
    }
  }
};

const stopDragItem = () => {
  dragTarget.value = null;
  dragType.value = null;
  window.removeEventListener('mousemove', onDragItem);
  window.removeEventListener('mouseup', stopDragItem);
};

const startResizeItem = (e: MouseEvent, id: string, type: 'graph' | 'code', itemLayout: {x: number, y: number, width: number, height: number}) => {
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
  const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
  const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
  
  const newWidth = Math.max(300, initialLayout.value.width + dx);
  const newHeight = Math.max(200, initialLayout.value.height + dy);
  
  if (currentProject.value) {
      if (resizeType.value === 'graph') {
        projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value, {
            width: newWidth,
            height: newHeight
        });
      } else {
        projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value, {
            codePanelWidth: newWidth,
            codePanelHeight: newHeight
        });
      }
  }
};

const stopResizeItem = () => {
  resizeTarget.value = null;
  resizeType.value = null;
  window.removeEventListener('mousemove', onResizeItem);
  window.removeEventListener('mouseup', stopResizeItem);
};

const activateGraph = (graphId: string) => {
  if (currentGraphId.value !== graphId) {
    graphStore.selectGraph(graphId);
  }
};

const handleNewGraph = () => emit('new-graph');

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

// --- SVG Connectors (Smart Arrows) ---
const connectorPath = (g: GraphMeta) => {
    if (!g.showCodePanel) return '';

    // Source (Graph) Geometry
    const sX = g.x;
    const sY = g.y;
    const sW = g.width;
    const sH = g.height;

    // Target (Code Panel) Geometry
    const tX = g.codePanelX ?? (g.x + g.width + 20);
    const tY = g.codePanelY ?? g.y;
    const tW = g.codePanelWidth ?? 400;
    const tH = g.codePanelHeight ?? (g.height || 400);

    // Centers
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

    // Determine "nearest" edge connection
    // Bias horizontal slightly because panels are usually side-by-side
    if (Math.abs(dx) > Math.abs(dy) * 1.2) {
        // Horizontal connection
        if (dx > 0) {
            // Source Right -> Target Left
            start = { x: sX + sW, y: sCy };
            end = { x: tX, y: tCy };
            // Control points for Bezier
            const dist = (end.x - start.x) / 2;
            control1 = { x: start.x + dist, y: start.y };
            control2 = { x: end.x - dist, y: end.y };
        } else {
            // Source Left -> Target Right
            start = { x: sX, y: sCy };
            end = { x: tX + tW, y: tCy };
            const dist = (start.x - end.x) / 2;
            control1 = { x: start.x - dist, y: start.y };
            control2 = { x: end.x + dist, y: end.y };
        }
    } else {
        // Vertical connection
        if (dy > 0) {
            // Source Bottom -> Target Top
            start = { x: sCx, y: sY + sH };
            end = { x: tCx, y: tY };
            const dist = (end.y - start.y) / 2;
            control1 = { x: start.x, y: start.y + dist };
            control2 = { x: end.x, y: end.y - dist };
        } else {
            // Source Top -> Target Bottom
            start = { x: sCx, y: sY };
            end = { x: tCx, y: tY + tH };
            const dist = (start.y - end.y) / 2;
            control1 = { x: start.x, y: start.y - dist };
            control2 = { x: end.x, y: end.y + dist };
        }
    }

    return `M ${start.x} ${start.y} C ${control1.x} ${control1.y}, ${control2.x} ${control2.y}, ${end.x} ${end.y}`;
};

// --- Menu Handlers ---
const toggleCodePanel = (graph: GraphMeta) => {
    if (currentProject.value) {
        projectStore.updateGraphLayout(currentProject.value.id, graph.id, { showCodePanel: !graph.showCodePanel });
    }
};

const exportGraph = (graphId: string, format: 'png' | 'jpg' | 'svg') => {
    graphStore.selectGraph(graphId);
    emit('open-export-modal', format);
};

onMounted(() => {
    if (graphs.value.length > 0) {
        workspaceX.value = 50;
        workspaceY.value = 50;
    }
});

onUnmounted(() => {
    window.removeEventListener('mousemove', onPan);
    window.removeEventListener('mouseup', stopPan);
    window.removeEventListener('mousemove', onDragItem);
    window.removeEventListener('mouseup', stopDragItem);
    window.removeEventListener('mousemove', onResizeItem);
    window.removeEventListener('mouseup', stopResizeItem);
    window.removeEventListener('mousemove', onControlsDrag);
    window.removeEventListener('mouseup', stopControlsDrag);
});

const showArrangeMenu = ref(false);
</script>

<template>
  <div class="infinite-canvas-container" ref="containerRef">
    <div 
      class="infinite-canvas" 
      @mousedown="startPan" 
      @wheel="handleWheel"
      :class="{'grid-dots': uiStore.workspaceGridStyle === 'dots', 'grid-lines': uiStore.workspaceGridStyle === 'lines'}"
      :style="{
        backgroundPosition: `${workspaceX}px ${workspaceY}px`,
        backgroundSize: `${uiStore.workspaceGridSize * workspaceScale}px ${uiStore.workspaceGridSize * workspaceScale}px`
      }"
    >
      <div 
        class="workspace"
        :style="{
          transform: `translate(${workspaceX}px, ${workspaceY}px) scale(${workspaceScale})`
        }"
      >
        <!-- Connectors -->
        <svg class="connectors-layer">
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
          class="graph-card"
          :class="{ 'active': currentGraphId === graph.id }"
          :style="{
            left: `${graph.x}px`,
            top: `${graph.y}px`,
            width: `${graph.width}px`,
            height: `${graph.height}px`,
            zIndex: currentGraphId === graph.id ? 10 : 1
          }"
          @mousedown="activateGraph(graph.id)"
        >
          <div class="graph-header" @mousedown="startDragItem($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})">
            <span class="graph-title">{{ graph.name }}</span>
            <div class="header-actions">
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
              v-if="currentGraphId === graph.id"
              :graph-id="graph.id"
              :is-grid-enabled="isGridEnabled"
              @update:is-grid-enabled="$emit('update:isGridEnabled', $event)"
              :grid-size="gridSize"
              @update:grid-size="$emit('update:gridSize', $event)"
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
                />
            </div>
          </div>

          <div class="resize-handle" @mousedown="startResizeItem($event, graph.id, 'graph', {x: graph.x, y: graph.y, width: graph.width, height: graph.height})">
            <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
          </div>
        </div>

        <!-- Pop-out Code Panels -->
        <template v-for="graph in graphs" :key="graph.id + 'code'">
            <div v-if="graph.showCodePanel" 
                 class="code-panel-card"
                 :class="{ 'active': currentGraphId === graph.id }"
                 :style="{
                    left: `${graph.codePanelX ?? (graph.x + graph.width + 20)}px`,
                    top: `${graph.codePanelY ?? graph.y}px`,
                    width: `${graph.codePanelWidth ?? 400}px`,
                    height: `${graph.codePanelHeight ?? graph.height}px`,
                    zIndex: currentGraphId === graph.id ? 9 : 1
                 }"
                 @mousedown="activateGraph(graph.id)"
            >
                <div class="graph-header code-header" @mousedown="startDragItem($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})">
                    <span class="graph-title"><i class="fas fa-code"></i> {{ graph.name }} (Code)</span>
                    <button class="close-btn" @click="toggleCodePanel(graph)"><i class="fas fa-times"></i></button>
                </div>
                <div class="code-content">
                    <CodePreviewPanel :is-active="true" :graph-id="graph.id" />
                </div>
                <div class="resize-handle" @mousedown="startResizeItem($event, graph.id, 'code', {x: graph.codePanelX ?? 0, y: graph.codePanelY ?? 0, width: graph.codePanelWidth ?? 400, height: graph.codePanelHeight ?? 400})">
                    <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
                </div>
            </div>
        </template>

      </div>
    </div>

    <!-- Node Count Tooltip -->
    <div v-if="showTooltip" class="node-tooltip" :style="{ left: tooltipPos.x + 15 + 'px', top: tooltipPos.y + 15 + 'px' }">
        <div v-if="hoveredGraphId && getNodeBreakdownArray(hoveredGraphId).length === 0">No nodes</div>
        <div v-else>
            <div v-for="item in getNodeBreakdownArray(hoveredGraphId!)" :key="item.type">
                <strong>{{ item.type }}:</strong> {{ item.count }}
            </div>
        </div>
    </div>

    <!-- Workspace Overlay Controls -->
    <div 
        class="workspace-controls" 
        ref="controlsRef"
        @mousedown="startControlsDrag"
        :style="controlsPos"
    >
        <div class="drag-indicator" title="Drag controls"><i class="fas fa-grip-vertical"></i></div>
        
        <div class="zoom-indicator">{{ Math.round(workspaceScale * 100) }}%</div>
        <button @click="workspaceScale = Math.min(workspaceScale + 0.1, 5)" title="Zoom In"><i class="fas fa-plus"></i></button>
        <button @click="workspaceScale = Math.max(workspaceScale - 0.1, 0.1)" title="Zoom Out"><i class="fas fa-minus"></i></button>
        <button @click="fitAll" title="Fit All Graphs"><i class="fas fa-compress-arrows-alt"></i></button>
        
        <div class="divider"></div>
        
        <div class="arrange-menu-trigger">
            <button @click="showArrangeMenu = !showArrangeMenu" title="Auto Arrange"><i class="fas fa-th"></i></button>
            <div v-if="showArrangeMenu" class="arrange-menu">
                <div class="menu-item" @click="arrangeGraphs('grid'); showArrangeMenu = false"><i class="fas fa-th-large"></i> Grid</div>
                <div class="menu-item" @click="arrangeGraphs('horizontal'); showArrangeMenu = false"><i class="fas fa-ellipsis-h"></i> Horizontal</div>
                <div class="menu-item" @click="arrangeGraphs('vertical'); showArrangeMenu = false"><i class="fas fa-ellipsis-v"></i> Vertical</div>
            </div>
        </div>

        <div class="divider"></div>
        
        <button @click="handleNewGraph" class="primary-action" title="Add New Graph"><i class="fas fa-plus"></i> Graph</button>
    </div>
  </div>
</template>

<style scoped>
.infinite-canvas-container {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background-color: var(--color-workspace-bg);
}

.infinite-canvas {
  width: 100%;
  height: 100%;
  cursor: grab;
}

.infinite-canvas.grid-dots {
    background-image: radial-gradient(circle, var(--color-workspace-grid) 1px, transparent 1px);
}

.infinite-canvas.grid-lines {
    background-image: 
        linear-gradient(to right, var(--color-workspace-grid) 1px, transparent 1px),
        linear-gradient(to bottom, var(--color-workspace-grid) 1px, transparent 1px);
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
  background-color: var(--color-background);
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  display: flex;
  flex-direction: column;
  border: 1px solid var(--color-border);
  overflow: visible; 
  transition: box-shadow 0.2s;
}

.graph-card.active, .code-panel-card.active {
  box-shadow: 0 5px 20px rgba(0,0,0,0.2);
  border-color: var(--color-primary);
  outline: 2px solid rgba(66, 153, 225, 0.3);
}

.graph-header {
  height: 36px; /* Compact header */
  background-color: var(--color-background-soft);
  border-bottom: 1px solid var(--color-border);
  display: flex;
  align-items: center;
  padding: 0 10px;
  cursor: move;
  user-select: none;
  justify-content: space-between;
  border-top-left-radius: 8px;
  border-top-right-radius: 8px;
}

.code-header {
    background-color: #2d3748;
    color: white;
}
.code-header .graph-title {
    color: white;
}

.graph-title {
  font-weight: 600;
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--color-text);
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
    background: var(--color-background-mute);
    padding: 2px 6px;
    border-radius: 4px;
    color: var(--color-secondary);
    cursor: help;
    user-select: none;
}

.icon-btn {
    background: transparent;
    border: none;
    color: var(--color-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: 4px;
    font-size: 13px;
}
.icon-btn:hover {
    background: var(--color-background-mute);
    color: var(--color-text);
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
  background-color: var(--color-background);
  display: flex;
  flex-direction: column;
  border-bottom-left-radius: 8px;
  border-bottom-right-radius: 8px;
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
  color: var(--color-secondary);
  font-size: 9px;
  z-index: 20;
  background: var(--color-background-soft);
  border-top-left-radius: 4px;
  border-bottom-right-radius: 8px;
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
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
}

/* Workspace Controls */
.workspace-controls {
    position: fixed;
    background: var(--color-background);
    padding: 6px 12px;
    border-radius: 30px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    display: flex;
    align-items: center;
    gap: 8px;
    z-index: 100;
    border: 1px solid var(--color-border);
    cursor: grab;
}

.workspace-controls:active {
    cursor: grabbing;
}

.workspace-controls button {
    background: transparent;
    border: none;
    color: var(--color-text);
    cursor: pointer;
    padding: 6px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    transition: background 0.2s;
}

.workspace-controls button:hover {
    background: var(--color-background-mute);
}

.workspace-controls .primary-action {
    background: var(--color-primary);
    color: white;
    border-radius: 16px;
    width: auto;
    padding: 4px 10px;
    font-size: 12px;
    font-weight: 500;
    gap: 6px;
}

.workspace-controls .primary-action:hover {
    background: var(--color-primary-hover);
}

.zoom-indicator {
    font-variant-numeric: tabular-nums;
    font-size: 12px;
    color: var(--color-secondary);
    width: 36px;
    text-align: center;
    user-select: none;
}

.drag-indicator {
    color: var(--color-border-dark);
    cursor: grab;
    margin-right: 2px;
    font-size: 12px;
}

.divider {
    width: 1px;
    height: 16px;
    background: var(--color-border);
}

.arrange-menu-trigger {
    position: relative;
}

.arrange-menu {
    position: absolute;
    bottom: 40px;
    left: 50%;
    transform: translateX(-50%);
    background: var(--color-background);
    border: 1px solid var(--color-border);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    padding: 4px;
    min-width: 120px;
    display: flex;
    flex-direction: column;
    z-index: 101;
}

.menu-item {
    padding: 6px 10px;
    font-size: 12px;
    color: var(--color-text);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 8px;
    border-radius: 4px;
}

.menu-item:hover {
    background: var(--color-background-mute);
}

.menu-item i {
    width: 14px;
    text-align: center;
    color: var(--color-secondary);
}
</style>
