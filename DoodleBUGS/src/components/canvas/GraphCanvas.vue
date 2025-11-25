<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import type { Core, EventObject, NodeSingular, ElementDefinition } from 'cytoscape';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGridSnapping } from '../../composables/useGridSnapping';
import type { GraphElement, GraphNode, GraphEdge, NodeType, PaletteItemType, ValidationError } from '../../types';
import type { GridStyle } from '../../stores/uiStore';

const props = defineProps<{
  graphId: string;
  elements: GraphElement[];
  isGridEnabled: boolean;
  gridSize: number;
  gridStyle?: GridStyle;
  currentMode: string;
  validationErrors: Map<string, ValidationError[]>;
  showZoomControls?: boolean;
}>();

const emit = defineEmits<{
  (e: 'canvas-tap', event: EventObject): void;
  (e: 'node-moved', payload: { nodeId: string, position: { x: number; y: number }, parentId: string | undefined }): void;
  (e: 'node-dropped', payload: { nodeType: NodeType; position: { x: number; y: number } }): void;
  (e: 'plate-emptied', plateId: string): void;
  (e: 'element-remove', elementId: string): void;
  (e: 'update:show-zoom-controls', value: boolean): void;
  (e: 'graph-updated', elements: GraphElement[]): void;
}>();

const cyContainer = ref<HTMLElement | null>(null);
let cy: Core | null = null;
const cyInstance = ref<Core | null>(null);
let resizeObserver: ResizeObserver | null = null;

// Start hidden to prevent flash of un-layouted content
const isGraphVisible = ref(false);

const { initCytoscape, destroyCytoscape, getCyInstance, getUndoRedoInstance } = useGraphInstance();
const getCy = () => getCyInstance(props.graphId);
const { enableGridSnapping, disableGridSnapping, setGridSize } = useGridSnapping(getCy);

const validNodeTypes: NodeType[] = ['stochastic', 'deterministic', 'constant', 'observed', 'plate'];

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
    cy = initCytoscape(cyContainer.value, [], props.graphId);
    cyInstance.value = cy;

    // Initial sync
    syncGraphWithProps(props.elements, props.validationErrors);

    setGridSize(props.gridSize);
    
    if (props.isGridEnabled) {
      enableGridSnapping();
    } else {
      disableGridSnapping();
    }

    const ur = getUndoRedoInstance(props.graphId);
    if (ur) {
      cy.on('afterUndo afterRedo afterDo', () => {
        if (!cy) return;
        const allElements: GraphElement[] = cy.elements().toArray().map((ele) => {
          const data = ele.data();
          if (ele.isNode()) {
            const parentCollection = ele.parent();
            const parentId = parentCollection.length > 0 ? parentCollection.first().id() : undefined;
            return {
              ...data,
              type: 'node',
              position: ele.position(),
              parent: parentId,
            } as GraphNode;
          } else {
            return {
              ...data,
              type: 'edge',
              source: ele.source().id(),
              target: ele.target().id(),
            } as GraphEdge;
          }
        });
        emit('graph-updated', allElements);
      });
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

    cy.on('free', 'node', (evt: EventObject) => {
        const node = evt.target as NodeSingular;
        const parentCollection = node.parent();
        const parentId = parentCollection.length > 0 ? parentCollection.first().id() : undefined;

        emit('node-moved', {
            nodeId: node.id(),
            position: node.position(),
            parentId: parentId,
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

    resizeObserver = new ResizeObserver(() => {
      if (cy) {
        cy.resize();
        // Initial fit logic
        if (!isGraphVisible.value) {
            // If we have elements, fit them then show
            if (props.elements.length > 0) {
                if (cy.width() > 0 && cy.height() > 0) {
                    cy.fit(undefined, 50);
                    if (cy.zoom() > 0.8) {
                        cy.zoom(0.8);
                        cy.center();
                    }
                    isGraphVisible.value = true;
                }
            } else {
                // If empty, just show immediately
                isGraphVisible.value = true;
            }
        }
      }
    });
    resizeObserver.observe(cyContainer.value);
  }
});

onUnmounted(() => {
  if (resizeObserver) {
    resizeObserver.disconnect();
    resizeObserver = null;
  }
  if (cy) {
    destroyCytoscape(props.graphId);
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

watch([() => props.elements, () => props.validationErrors], async ([newElements, newErrors], [oldElements]) => {
  // Detect bulk load (empty -> populated).
  // Also handles reload where oldElements might be empty initially.
  const isBulkLoad = oldElements.length === 0 && newElements.length > 0;

  if (isBulkLoad) {
      // Hide INSTANTLY to prevent flash of unpositioned nodes
      isGraphVisible.value = false;
      await nextTick(); 
  }

  syncGraphWithProps(newElements, newErrors);

  if (isBulkLoad && cy) {
      // Ensure Cytoscape has processed the batch
      // Then fit and show
      setTimeout(() => {
          cy!.fit(undefined, 50);
          if (cy!.zoom() > 0.8) {
              cy!.zoom(0.8);
              cy!.center();
          }
          // Fade back in
          isGraphVisible.value = true;
      }, 50);
  }
}, { deep: true });
</script>

<template>
  <div
    ref="cyContainer"
    class="cytoscape-container"
    :class="{
      'grid-background': isGridEnabled && gridSize > 0,
      'grid-lines': (gridStyle === 'lines' || !gridStyle) && isGridEnabled && gridSize > 0,
      'grid-dots': gridStyle === 'dots' && isGridEnabled && gridSize > 0,
      'mode-add-node': currentMode === 'add-node',
      'mode-add-edge': currentMode === 'add-edge',
      'mode-select': currentMode === 'select',
      'graph-ready': isGraphVisible
    }"
    :style="{ 
        '--grid-size': `${gridSize}px`,
        'transition': isGraphVisible ? 'opacity 0.3s ease-in-out' : 'none'
    }"
  ></div>
</template>

<style scoped>
.cytoscape-container {
  flex-grow: 1;
  background-color: var(--theme-bg-canvas);
  position: relative;
  overflow: hidden;
  cursor: grab;
  opacity: 0;
  /* Transition defined inline to support instant toggle */
}

.cytoscape-container.graph-ready {
    opacity: 1;
}

.cytoscape-container.mode-add-node {
  cursor: crosshair;
}

.cytoscape-container.mode-add-edge {
  cursor: alias;
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

/* Grid styles with !important to override global defaults and ensure visibility */
.cytoscape-container.grid-background.grid-dots {
  background-image: radial-gradient(circle, var(--theme-grid-line) 1px, transparent 1px) !important;
  background-size: var(--grid-size) var(--grid-size) !important;
}

.cytoscape-container.grid-background.grid-lines {
  background-image:
    linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px) !important;
  background-size: var(--grid-size) var(--grid-size) !important;
}
</style>
