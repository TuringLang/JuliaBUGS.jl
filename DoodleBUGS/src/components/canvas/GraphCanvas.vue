<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue';
import type { Core, EventObject, NodeSingular, ElementDefinition } from 'cytoscape';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGridSnapping } from '../../composables/useGridSnapping';
import type { GraphElement, GraphNode, GraphEdge, NodeType, PaletteItemType, ValidationError } from '../../types';

const props = defineProps<{
  elements: GraphElement[];
  isGridEnabled: boolean;
  gridSize: number;
  currentMode: string;
  validationErrors: Map<string, ValidationError[]>;
  zoomControlsPosition?: string;
}>();

const emit = defineEmits<{
  (e: 'canvas-tap', event: EventObject): void;
  (e: 'node-moved', payload: { nodeId: string, position: { x: number; y: number }, parentId: string | undefined }): void;
  (e: 'node-dropped', payload: { nodeType: NodeType; position: { x: number; y: number } }): void;
  (e: 'plate-emptied', plateId: string): void;
  (e: 'element-remove', elementId: string): void;
}>();

const cyContainer = ref<HTMLElement | null>(null);
let cy: Core | null = null;

const { initCytoscape, destroyCytoscape, getCyInstance } = useGraphInstance();
const { enableGridSnapping, disableGridSnapping, setGridSize } = useGridSnapping(getCyInstance);

const validNodeTypes: NodeType[] = ['stochastic', 'deterministic', 'constant', 'observed', 'plate'];

// Zoom state
const currentZoom = ref(1);
const minZoom = 0.1;
const maxZoom =2;

// Panzoom control functions
const zoomIn = () => {
  if (cy) {
    const newZoom = Math.min(cy.zoom() * 1.2, maxZoom);
    cy.zoom({
      level: newZoom,
      renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 }
    });
    currentZoom.value = newZoom;
  }
};

const zoomOut = () => {
  if (cy) {
    const newZoom = Math.max(cy.zoom() / 1.2, minZoom);
    cy.zoom({
      level: newZoom,
      renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 }
    });
    currentZoom.value = newZoom;
  }
};

const resetView = () => {
  if (cy) {
    cy.fit();
    currentZoom.value = 1;
  }
};

const setZoomLevel = (event: Event) => {
  if (cy) {
    const target = event.target as HTMLInputElement;
    const zoomLevel = Number(target.value);
    cy.zoom({
      level: zoomLevel,
      renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 }
    });
    currentZoom.value = zoomLevel;
  }
}; 

interface CompoundDropPayload {
  node: NodeSingular;
  newParent: NodeSingular | null;
  oldParent: NodeSingular | null;
}

const formatElementsForCytoscape = (elements: GraphElement[], errors: Map<string, ValidationError[]>): ElementDefinition[] => {
  return elements.map(el => {
    if (el.type === 'node') {
      const node = el as GraphNode;
      const hasError = errors.has(node.id);
      return { 
        group: 'nodes', 
        data: { ...node, hasError }, 
        position: node.position 
      };
    } else {
      const edge = el as GraphEdge;
      const targetNode = elements.find(n => n.id === edge.target && n.type === 'node') as GraphNode | undefined;
      const relType = (targetNode?.nodeType === 'stochastic' || targetNode?.nodeType === 'observed') ? 'stochastic' : 'deterministic';
      return {
        group: 'edges',
        data: {
          ...edge,
          relationshipType: relType
        }
      };
    }
  });
};

/**
 * Synchronizes the Cytoscape instance with the current graph elements from props.
 * @param elementsToSync The array of graph elements to display.
 * @param errorsToSync The map of validation errors.
 */
const syncGraphWithProps = (elementsToSync: GraphElement[], errorsToSync: Map<string, ValidationError[]>) => {
  if (!cy) return;

  const formattedElements = formatElementsForCytoscape(elementsToSync, errorsToSync);

  cy.batch(() => {
    const newElementIds = new Set(elementsToSync.map(el => el.id));

    cy!.elements().forEach(cyEl => {
      if (!newElementIds.has(cyEl.id())) {
        cyEl.remove();
      }
    });

    formattedElements.forEach(formattedEl => {
      if (!formattedEl.data.id) return;

      const existingCyEl = cy!.getElementById(formattedEl.data.id);

      if (existingCyEl.empty()) {
        cy!.add(formattedEl);
      } else {
        existingCyEl.data(formattedEl.data);
        if (formattedEl.group === 'nodes') {
          const newNode = formattedEl as ElementDefinition & { position: {x: number, y: number} };
          const currentCyPos = existingCyEl.position();
          if (newNode.position.x !== currentCyPos.x || newNode.position.y !== currentCyPos.y) {
            existingCyEl.position(newNode.position);
          }
          const parentCollection = existingCyEl.parent();
          const currentParentId = parentCollection.length > 0 ? parentCollection.first().id() : undefined;
          
          if (newNode.data.parent !== currentParentId) {
            existingCyEl.move({ parent: newNode.data.parent ?? null });
          }
        }
      }
    });
  });
};


onMounted(() => {
  if (cyContainer.value) {
    cy = initCytoscape(cyContainer.value, []);

    syncGraphWithProps(props.elements, props.validationErrors);

    setGridSize(props.gridSize);
    if (props.isGridEnabled) {
      enableGridSnapping();
    } else {
      disableGridSnapping();
    }

    cy.container()?.addEventListener('cxt-remove', (event: Event) => {
        const customEvent = event as CustomEvent;
        if (customEvent.detail.elementId) {
            emit('element-remove', customEvent.detail.elementId);
        }
    });

    cy.on('tap', (evt: EventObject) => {
      emit('canvas-tap', evt);
    });

    cy.on('compound-drop', (_evt: EventObject, data: CompoundDropPayload) => {
      const { node, newParent } = data;
      const newParentId = newParent ? newParent.id() : undefined;
      
      emit('node-moved', {
          nodeId: node.id(),
          position: node.position(),
          parentId: newParentId
      });
    });

    cy.on('tap', 'node, edge', (evt: EventObject) => {
      cy?.elements().removeClass('cy-selected');
      evt.target.addClass('cy-selected');
    });
    cy.on('tap', (evt: EventObject) => {
      if (evt.target === cy) {
        cy?.elements().removeClass('cy-selected');
      }
    });

    cyContainer.value.addEventListener('dragover', (event) => {
      event.preventDefault();
      if (event.dataTransfer) {
        event.dataTransfer.dropEffect = 'copy';
      }
    });

    cyContainer.value.addEventListener('drop', (event) => {
      event.preventDefault();

      if (event.dataTransfer) {
        const droppedItemType = event.dataTransfer.getData('text/plain') as PaletteItemType;
        if (validNodeTypes.includes(droppedItemType as NodeType)) {
          const bbox = cyContainer.value?.getBoundingClientRect();
          if (bbox && cy) {
            const clientX = event.clientX;
            const clientY = event.clientY;
            const renderedPos = { x: clientX - bbox.left, y: clientY - bbox.top };
            const pan = cy.pan();
            const zoom = cy.zoom();
            const modelPos = { 
              x: (renderedPos.x - pan.x) / zoom,
              y: (renderedPos.y - pan.y) / zoom
            };
            emit('node-dropped', { nodeType: droppedItemType as NodeType, position: modelPos });
          }
        }
      }
    });
  }
});

onUnmounted(() => {
  if (cy) {
    destroyCytoscape(cy);
  }
});

watch(() => props.isGridEnabled, (newValue: boolean) => {
  if (newValue) {
    enableGridSnapping();
  } else {
    disableGridSnapping();
  }
});

watch(() => props.gridSize, (newValue: number) => {
  setGridSize(newValue);
  if (props.isGridEnabled) {
    enableGridSnapping();
  }
});

watch([() => props.elements, () => props.validationErrors], ([newElements, newErrors]) => {
  syncGraphWithProps(newElements, newErrors);
}, { deep: true });

// Sync zoom level with graph
watch(() => cy, (newCy) => {
  if (newCy) {
    // Set initial zoom level
    currentZoom.value = newCy.zoom();
    
    // Listen for zoom events from other sources (mouse wheel, etc.)
    newCy.on('zoom', () => {
      currentZoom.value = newCy.zoom();
    });
  }
}, { immediate: true });
</script>

<template>
  <div class="canvas-wrapper">
    <div
      ref="cyContainer"
      class="cytoscape-container"
      :class="{
        'grid-background': isGridEnabled && gridSize > 0,
        'mode-add-node': currentMode === 'add-node',
        'mode-add-edge': currentMode === 'add-edge',
        'mode-select': currentMode === 'select'
      }"
      :style="{ '--grid-size': `${gridSize}px` }"
    ></div>
    
    <!-- Custom Panzoom Controls Container -->
    <div 
      v-if="zoomControlsPosition !== 'hidden'"
      class="panzoom-controls"
      :class="`panzoom-position-${zoomControlsPosition || 'default'}`"
    >
      <div class="panzoom-button" @click="zoomIn" title="Zoom In">
        <i class="fas fa-plus"></i>
      </div>
      <div class="panzoom-slider-container">
        <input 
          type="range" 
          :min="minZoom" 
          :max="maxZoom" 
          :value="currentZoom" 
          step="0.1" 
          class="panzoom-slider" 
          @input="setZoomLevel"
        />
      </div>
      <div class="panzoom-button" @click="zoomOut" title="Zoom Out">
        <i class="fas fa-minus"></i>
      </div>
      <div class="panzoom-button" @click="resetView" title="Reset View">
        <i class="fas fa-expand"></i>
      </div>
    </div>
  </div>
</template>

<style scoped>
.canvas-wrapper {
  position: relative;
  flex-grow: 1;
  display: flex;
}

.cytoscape-container {
  flex-grow: 1;
  background-color: var(--color-background-soft);
  position: relative;
  overflow: hidden;
  cursor: grab;
}

.cytoscape-container.mode-add-node {
  cursor: crosshair;
}

.cytoscape-container.mode-add-edge {
  cursor: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%23333" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="feather feather-arrow-right"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>') 12 12, crosshair;
}

/* Custom drag and drop styling */
.cdnd-grabbed-node {
  background-color: #FFD700 !important;
  opacity: 0.7;
  border: 2px dashed #FFA500;
}

.cdnd-drop-target {
  border: 3px solid #32CD32 !important;
  background-color: rgba(50, 205, 50, 0.1) !important;
}

/* Visual indicator for nodes being dragged out of plates */
.cdnd-drag-out {
  border: 2px dashed #FF0000 !important;
  background-color: rgba(255, 0, 0, 0.1) !important;
}

/* Custom Panzoom Controls Container */
.panzoom-controls {
  position: absolute;
  z-index: 10;
  display: flex;
  flex-direction: column;
  gap: 4px;
  background: rgba(255, 255, 255, 0.9);
  border-radius: 8px;
  padding: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  backdrop-filter: blur(4px);
}

/* Position classes */
.panzoom-position-default,
.panzoom-position-bottom-left {
  left: 12px;
  bottom: 12px;
}

.panzoom-position-top-left {
  left: 12px;
  top: 12px;
}

.panzoom-position-top-right {
  right: 12px;
  top: 12px;
}

.panzoom-position-bottom-right {
  right: 12px;
  bottom: 12px;
}

.panzoom-button {
  width: 32px;
  height: 32px;
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s ease;
  color: #222;
  font-size: 12px;
}

.panzoom-button:hover {
  background: #f6f8fa;
  border-color: #c2c8d0;
  transform: scale(1.05);
}

.panzoom-button:active {
  transform: scale(0.95);
}

.panzoom-slider-container {
  
  align-items: center;
}
/* Custom Panzoom Slider vertically */
.panzoom-slider {
  margin-left: 8px;
  writing-mode: vertical-lr;
  direction: rtl;
}
</style>