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
 * This function handles adding, updating, and removing nodes and edges.
 * @param elementsToSync The array of graph elements to display.
 * @param errorsToSync The map of validation errors.
 */
const syncGraphWithProps = (elementsToSync: GraphElement[], errorsToSync: Map<string, ValidationError[]>) => {
  if (!cy) return;

  const formattedElements = formatElementsForCytoscape(elementsToSync, errorsToSync);

  cy.batch(() => {
    const newElementIds = new Set(elementsToSync.map(el => el.id));

    // Remove elements that are no longer in the props
    cy!.elements().forEach(cyEl => {
      if (!newElementIds.has(cyEl.id())) {
        cyEl.remove();
      }
    });

    // Add or update elements
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

    // Perform the initial synchronization to draw the graph on load
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

    cy.on('compound-drop', (evt: EventObject, data: { node: NodeSingular; newParent: NodeSingular | null; oldParent: NodeSingular | null }) => {
        const { node, newParent, oldParent } = data;
        const newParentId = newParent ? newParent.id() : undefined;
        
        // Handle plate emptied logic
        // Note: We no longer automatically delete empty plates
        // Users can manually delete empty plates if desired
        if (oldParent) {
            const oldParentId = oldParent.id();
            const oldParentElement = props.elements.find(el => el.id === oldParentId && el.type === 'node' && (el as GraphNode).nodeType === 'plate');
            
            if (oldParentElement) {
                // Count siblings after the move (excluding the moved node)
                const siblings = props.elements.filter(el => 
                    el.id !== node.id() && 
                    el.type === 'node' && 
                    (el as GraphNode).parent === oldParentId
                );
                // We no longer automatically delete empty plates
                // if (siblings.length === 0) { 
                //     emit('plate-emptied', oldParentId);
                // }
            }
        }

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
            const modelPos = cy.panzoom().renderedPositionToModelPosition(renderedPos);
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

watch(() => props.isGridEnabled, (newValue) => {
  if (newValue) {
    enableGridSnapping();
  } else {
    disableGridSnapping();
  }
});

watch(() => props.gridSize, (newValue) => {
  setGridSize(newValue);
  if (props.isGridEnabled) {
    enableGridSnapping();
  }
});

// Watch for subsequent changes to props and re-sync the graph
watch([() => props.elements, () => props.validationErrors], ([newElements, newErrors]) => {
  syncGraphWithProps(newElements, newErrors);
}, { deep: true });
</script>

<template>
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
</template>

<style scoped>
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
</style>
