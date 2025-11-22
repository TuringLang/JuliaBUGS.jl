<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { storeToRefs } from 'pinia';
import GraphEditor from './GraphEditor.vue';
import GraphPreview from './GraphPreview.vue';
import { useProjectStore, type GraphMeta } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import type { GraphElement, GraphNode, NodeType, ValidationError } from '../../types';
import DropdownMenu from '../common/DropdownMenu.vue'; // Assuming this component exists or similar dropdown logic is needed

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
}>();

const projectStore = useProjectStore();
const graphStore = useGraphStore();
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

// --- Graph Drag/Resize State ---
const dragTarget = ref<string | null>(null); // graphId
const resizeTarget = ref<string | null>(null); // graphId
const dragStart = ref({ x: 0, y: 0 });
const initialLayout = ref({ x: 0, y: 0, width: 0, height: 0 });

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

const getNodeBreakdown = (graphId: string) => {
    const elements = getElementsForGraph(graphId);
    const counts: Record<string, number> = {};
    elements.forEach(el => {
        if (el.type === 'node') {
            const type = (el as GraphNode).nodeType;
            const label = type.charAt(0).toUpperCase() + type.slice(1);
            counts[label] = (counts[label] || 0) + 1;
        }
    });
    if (Object.keys(counts).length === 0) return 'No nodes';
    return Object.entries(counts)
        .map(([type, count]) => `${type}: ${count}`)
        .join('\n');
};

// --- Workspace Interactions ---

const handleWheel = (e: WheelEvent) => {
  // Check if mouse is over an active graph card content
  const target = e.target as HTMLElement;
  const closestCard = target.closest('.graph-card');
  
  // If over an active graph card, allow default behavior (zooming inside the graph editor)
  // But only if we are actually over the content part, not the header
  if (closestCard && closestCard.classList.contains('active') && target.closest('.graph-content')) {
      // If ctrl key is pressed, standard behavior is zooming. 
      // If we want strict separation:
      // Active Graph + Wheel -> Zoom Graph
      // Background/Inactive + Wheel -> Zoom Workspace
      return; 
  }

  // Ctrl+Wheel to zoom workspace
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
    // Regular wheel to pan workspace
    e.preventDefault();
    workspaceX.value -= e.deltaX;
    workspaceY.value -= e.deltaY;
  }
};

const startPan = (e: MouseEvent) => {
  // Only pan if clicking on background (infinite-canvas)
  if ((e.target as HTMLElement).classList.contains('infinite-canvas')) {
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
    // Don't drag if clicking buttons
    if ((e.target as HTMLElement).closest('button')) return;

    isControlsDragging.value = true;
    const rect = controlsRef.value.getBoundingClientRect();
    
    // Switch to absolute positioning if not already
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

// --- Graph Layout Arrangement ---

const arrangeGraphs = (type: 'grid' | 'horizontal' | 'vertical') => {
    if (!currentProject.value) return;
    
    const graphsToArrange = [...currentProject.value.graphs];
    if (graphsToArrange.length === 0) return;

    const gap = 40;
    let currentX = 100; // Start with some padding
    let currentY = 100;
    
    // Find top-leftmost graph to use as anchor start? 
    // Or just reset to 100,100 relative to current view? 
    // Let's use a fixed start relative to workspace 0,0 for predictability
    
    if (type === 'horizontal') {
        graphsToArrange.forEach(g => {
            projectStore.updateGraphLayout(currentProject.value!.id, g.id, { x: currentX, y: 100 });
            currentX += g.width + gap;
        });
    } else if (type === 'vertical') {
        graphsToArrange.forEach(g => {
            projectStore.updateGraphLayout(currentProject.value!.id, g.id, { x: 100, y: currentY });
            currentY += g.height + gap;
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
            
            currentX += g.width + gap;
            if (g.height > rowHeight) rowHeight = g.height;
        });
    }
    
    // Reset view to see the start
    workspaceX.value = 50;
    workspaceY.value = 50;
    workspaceScale.value = Math.min(1, window.innerWidth / (currentX + 200)); 
};

// --- Graph Dragging ---

const startGraphDrag = (e: MouseEvent, graph: GraphMeta) => {
  e.stopPropagation(); // Prevent workspace pan
  
  // Select if not active
  if (currentGraphId.value !== graph.id) {
    graphStore.selectGraph(graph.id);
  }

  dragTarget.value = graph.id;
  dragStart.value = { x: e.clientX, y: e.clientY };
  initialLayout.value = { x: graph.x, y: graph.y, width: graph.width, height: graph.height };
  
  window.addEventListener('mousemove', onGraphDrag);
  window.addEventListener('mouseup', stopGraphDrag);
};

const onGraphDrag = (e: MouseEvent) => {
  if (!dragTarget.value) return;
  const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
  const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
  
  if (currentProject.value) {
    projectStore.updateGraphLayout(currentProject.value.id, dragTarget.value, {
      x: initialLayout.value.x + dx,
      y: initialLayout.value.y + dy
    });
  }
};

const stopGraphDrag = () => {
  dragTarget.value = null;
  window.removeEventListener('mousemove', onGraphDrag);
  window.removeEventListener('mouseup', stopGraphDrag);
};

// --- Graph Resizing ---

const startResize = (e: MouseEvent, graph: GraphMeta) => {
  e.stopPropagation();
  e.preventDefault();
  
  resizeTarget.value = graph.id;
  dragStart.value = { x: e.clientX, y: e.clientY };
  initialLayout.value = { x: graph.x, y: graph.y, width: graph.width, height: graph.height };
  
  window.addEventListener('mousemove', onResize);
  window.addEventListener('mouseup', stopResize);
};

const onResize = (e: MouseEvent) => {
  if (!resizeTarget.value) return;
  const dx = (e.clientX - dragStart.value.x) / workspaceScale.value;
  const dy = (e.clientY - dragStart.value.y) / workspaceScale.value;
  
  const newWidth = Math.max(400, initialLayout.value.width + dx);
  const newHeight = Math.max(300, initialLayout.value.height + dy);
  
  if (currentProject.value) {
    projectStore.updateGraphLayout(currentProject.value.id, resizeTarget.value, {
      width: newWidth,
      height: newHeight
    });
  }
};

const stopResize = () => {
  resizeTarget.value = null;
  window.removeEventListener('mousemove', onResize);
  window.removeEventListener('mouseup', stopResize);
};

const activateGraph = (graphId: string) => {
  if (currentGraphId.value !== graphId) {
    graphStore.selectGraph(graphId);
  }
};

const handleNewGraph = () => {
    emit('new-graph');
}

const resetView = () => {
    workspaceX.value = 50;
    workspaceY.value = 50;
    workspaceScale.value = 1;
}

const fitAll = () => {
    if (graphs.value.length === 0) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    
    graphs.value.forEach(g => {
        if (g.x < minX) minX = g.x;
        if (g.y < minY) minY = g.y;
        if (g.x + g.width > maxX) maxX = g.x + g.width;
        if (g.y + g.height > maxY) maxY = g.y + g.height;
    });
    
    const padding = 50;
    const width = maxX - minX + padding * 2;
    const height = maxY - minY + padding * 2;
    
    if (containerRef.value) {
        const containerW = containerRef.value.clientWidth;
        const containerH = containerRef.value.clientHeight;
        
        const scaleX = containerW / width;
        const scaleY = containerH / height;
        
        workspaceScale.value = Math.min(scaleX, scaleY, 1); // Don't zoom in too much
        workspaceX.value = -minX * workspaceScale.value + padding;
        workspaceY.value = -minY * workspaceScale.value + padding;
    }
};

onMounted(() => {
    // Center view initially if graphs exist
    if (graphs.value.length > 0) {
        workspaceX.value = 50;
        workspaceY.value = 50;
    }
});

onUnmounted(() => {
    window.removeEventListener('mousemove', onPan);
    window.removeEventListener('mouseup', stopPan);
    window.removeEventListener('mousemove', onGraphDrag);
    window.removeEventListener('mouseup', stopGraphDrag);
    window.removeEventListener('mousemove', onResize);
    window.removeEventListener('mouseup', stopResize);
    window.removeEventListener('mousemove', onControlsDrag);
    window.removeEventListener('mouseup', stopControlsDrag);
});

// Dropdown state for Arrange menu
const showArrangeMenu = ref(false);
</script>

<template>
  <div class="infinite-canvas-container" ref="containerRef">
    <div 
      class="infinite-canvas" 
      @mousedown="startPan" 
      @wheel="handleWheel"
      :style="{
        backgroundPosition: `${workspaceX}px ${workspaceY}px`,
        backgroundSize: `${20 * workspaceScale}px ${20 * workspaceScale}px`
      }"
    >
      <div 
        class="workspace"
        :style="{
          transform: `translate(${workspaceX}px, ${workspaceY}px) scale(${workspaceScale})`
        }"
      >
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
          <div class="graph-header" @mousedown="startGraphDrag($event, graph)">
            <span class="graph-title">{{ graph.name }}</span>
            <div class="header-actions">
                <span class="node-count-badge" :title="getNodeBreakdown(graph.id)">
                    {{ getElementsForGraph(graph.id).filter(el => el.type === 'node').length }} nodes
                </span>
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
                <div class="preview-blocker"></div> <!-- Blocks interactions -->
                <GraphPreview 
                  :elements="getElementsForGraph(graph.id)"
                  :graph-id="graph.id" 
                />
            </div>
          </div>

          <div class="resize-handle" @mousedown="startResize($event, graph)">
            <i class="fas fa-chevron-right" style="transform: rotate(45deg);"></i>
          </div>
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
  background-color: #f5f5f5;
}

:global(.dark-mode) .infinite-canvas-container {
    background-color: #1a1a1a;
}

.infinite-canvas {
  width: 100%;
  height: 100%;
  cursor: grab;
  /* Dot grid pattern */
  background-image: radial-gradient(circle, #ccc 1px, transparent 1px);
}

:global(.dark-mode) .infinite-canvas {
    background-image: radial-gradient(circle, #444 1px, transparent 1px);
}

.infinite-canvas:active {
  cursor: grabbing;
}

.workspace {
  position: absolute;
  top: 0;
  left: 0;
  transform-origin: 0 0;
  /* Ensure workspace doesn't collapse */
  width: 0; 
  height: 0;
}

.graph-card {
  position: absolute;
  background-color: var(--color-background);
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  display: flex;
  flex-direction: column;
  border: 1px solid var(--color-border);
  overflow: hidden;
  transition: box-shadow 0.2s;
}

.graph-card.active {
  box-shadow: 0 5px 20px rgba(0,0,0,0.2);
  border-color: var(--color-primary);
  outline: 2px solid rgba(66, 153, 225, 0.3);
}

.graph-header {
  height: 40px;
  background-color: var(--color-background-soft);
  border-bottom: 1px solid var(--color-border);
  display: flex;
  align-items: center;
  padding: 0 12px;
  cursor: move; /* Indicates draggable */
  user-select: none;
  justify-content: space-between;
}

.graph-title {
  font-weight: 600;
  font-size: 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--color-text);
}

.node-count-badge {
    font-size: 11px;
    background: var(--color-background-mute);
    padding: 2px 6px;
    border-radius: 4px;
    color: var(--color-secondary);
    cursor: help;
}

.graph-content {
  flex: 1;
  position: relative;
  overflow: hidden;
  background-color: var(--color-background);
  display: flex;
  flex-direction: column;
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
    z-index: 2; /* Sits on top of preview to capture clicks if needed, but handled by parent mousedown */
    background: transparent; 
}

.resize-handle {
  position: absolute;
  bottom: 0;
  right: 0;
  width: 20px;
  height: 20px;
  cursor: nwse-resize;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-secondary);
  font-size: 10px;
  z-index: 20;
  background: var(--color-background-soft);
  border-top-left-radius: 4px;
}

.workspace-controls {
    position: fixed; /* Changed from absolute to fixed to float above viewport */
    background: var(--color-background);
    padding: 8px 16px;
    border-radius: 30px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    display: flex;
    align-items: center;
    gap: 10px;
    z-index: 100;
    border: 1px solid var(--color-border);
    cursor: grab; /* Indicates the whole bar is draggable */
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
    width: 32px;
    height: 32px;
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
    padding: 6px 12px;
    font-size: 13px;
    font-weight: 500;
    gap: 6px;
}

.workspace-controls .primary-action:hover {
    background: var(--color-primary-hover);
}

.zoom-indicator {
    font-variant-numeric: tabular-nums;
    font-size: 13px;
    color: var(--color-secondary);
    width: 40px;
    text-align: center;
    user-select: none;
}

.drag-indicator {
    color: var(--color-border-dark);
    cursor: grab;
    margin-right: 4px;
}

.divider {
    width: 1px;
    height: 20px;
    background: var(--color-border);
}

/* Arrange Menu */
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
}

.menu-item {
    padding: 8px 12px;
    font-size: 13px;
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
    width: 16px;
    text-align: center;
    color: var(--color-secondary);
}
</style>
