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

onMounted(() => {
  if (cyContainer.value) {
    cy = initCytoscape(cyContainer.value, []);

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

    cy.on('cdnddrop', 'node', (evt: EventObject, dropTarget: NodeSingular | undefined) => {
        const node = evt.target as NodeSingular;
        const newParentId = dropTarget ? dropTarget.id() : undefined;

        const originalNode = props.elements.find(el => el.id === node.id() && el.type === 'node') as GraphNode | undefined;

        if (originalNode && originalNode.parent && originalNode.parent !== newParentId) {
            const oldParentId = originalNode.parent;
            const oldParent = props.elements.find(el => el.id === oldParentId && el.type === 'node' && (el as GraphNode).nodeType === 'plate');
            
            if (oldParent) {
                const siblings = props.elements.filter(el => el.type === 'node' && (el as GraphNode).parent === oldParentId);
                if (siblings.length === 1) { 
                    emit('plate-emptied', oldParentId);
                }
            }
        }

        emit('node-moved', {
            nodeId: node.id(),
            position: node.position(),
            parentId: newParentId,
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

watch([() => props.elements, () => props.validationErrors], ([newElements, newErrors]) => {
  if (!cy) return;

  const formattedElements = formatElementsForCytoscape(newElements, newErrors);

  cy.batch(() => {
    const newElementIds = new Set(newElements.map(el => el.id));

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
}, { deep: true, immediate: true });
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
</style>
