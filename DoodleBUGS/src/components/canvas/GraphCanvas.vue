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

    // Capture the final position of a node after any drag operation (including grid snapping).
    // This is the definitive event for updating node positions and saving the 'preset' layout.
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
</style>

