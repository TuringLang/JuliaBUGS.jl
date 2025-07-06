<script setup lang="ts">
import { ref, watch } from 'vue';
import type { NodeSingular, EventObject, Core } from 'cytoscape';
import GraphCanvas from './GraphCanvas.vue';
import CanvasToolbar from './CanvasToolbar.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useGraphInstance } from '../../composables/useGraphInstance';
import type { GraphElement, GraphNode, GraphEdge, NodeType } from '../../types';

const props = defineProps<{
  isGridEnabled: boolean;
  gridSize: number;
  currentMode: string;
  currentNodeType: NodeType;
}>();

const emit = defineEmits<{
  (e: 'element-selected', element: GraphElement | null): void;
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
}>();

const { elements, addElement, updateElement, deleteElement } = useGraphElements();
const { getCyInstance } = useGraphInstance();

const sourceNode = ref<NodeSingular | null>(null);
const isConnecting = ref(false);

/**
 * Creates a new plate with a default stochastic node inside it and adds them to the graph.
 * @param position - The position to create the plate at.
 * @param parentId - The ID of a parent element, if any.
 * @returns The newly created plate node.
 */
const createPlateWithNode = (position: { x: number; y: number }, parentId?: string): GraphNode => {
    const plateId = `node_${crypto.randomUUID().substring(0, 8)}`;
    const newPlate: GraphNode = {
      id: plateId,
      name: `Plate ${elements.value.filter(e => e.type === 'node' && e.nodeType === 'plate').length + 1}`,
      type: 'node',
      nodeType: 'plate',
      position: position,
      parent: parentId, // For potential future nested plates
      loopVariable: 'i',
      loopRange: '1:N',
    };

    const innerNodeId = `node_${crypto.randomUUID().substring(0, 8)}`;
    const innerNode: GraphNode = {
        id: innerNodeId,
        name: `Node ${elements.value.filter(e => e.type === 'node').length + 2}`,
        type: 'node',
        nodeType: 'stochastic',
        position: { x: position.x, y: position.y }, // Position is relative to parent in cytoscape
        parent: plateId,
        distribution: 'dnorm',
    };

    // Use the setter from the computed property to update the store with both new elements
    elements.value = [...elements.value, newPlate, innerNode];
    return newPlate;
}


const handleCanvasTap = (event: EventObject) => {
  const { position, target } = event;
  const cy = getCyInstance() as Core;

  if (!cy) return;

  const isBackgroundClick = target === cy;
  const isPlateClick = !isBackgroundClick && target.isNode() && target.data('nodeType') === 'plate';
  const isNodeClick = !isBackgroundClick && target.isNode();
  const isEdgeClick = !isBackgroundClick && target.isEdge();

  switch (props.currentMode) {
    case 'add-node':
      if (isBackgroundClick || isPlateClick) {
        if (props.currentNodeType === 'plate') {
            if (isPlateClick) {
                alert("Nesting plates is not currently supported.");
                return;
            }
            const newPlate = createPlateWithNode(position, isPlateClick ? (target as NodeSingular).id() : undefined);
            emit('element-selected', newPlate);
            emit('update:currentMode', 'select');
        } else {
            const newId = `node_${crypto.randomUUID().substring(0, 8)}`;
            const newNode: GraphNode = {
              id: newId,
              name: `${props.currentNodeType} ${elements.value.filter(e => e.type === 'node').length + 1}`,
              type: 'node',
              nodeType: props.currentNodeType,
              position: { x: position.x, y: position.y },
              parent: isPlateClick ? (target as NodeSingular).id() : undefined,
              distribution: props.currentNodeType === 'stochastic' ? 'dnorm' : undefined,
              equation: props.currentNodeType === 'deterministic' ? '' : undefined,
              observed: props.currentNodeType === 'observed' ? true : undefined,
            };
            addElement(newNode);
            emit('element-selected', newNode);
            emit('update:currentMode', 'select');
        }
      }
      break;

    case 'add-edge':
      if (isNodeClick) {
        const tappedNode = target as NodeSingular;
        if (sourceNode.value && sourceNode.value.id() !== tappedNode.id()) {
          const newEdge: GraphEdge = {
            id: `edge_${crypto.randomUUID().substring(0, 8)}`,
            type: 'edge',
            source: sourceNode.value.id(),
            target: tappedNode.id(),
            name: `Edge ${sourceNode.value.data('name')} -> ${tappedNode.data('name')}`,
          };
          addElement(newEdge);
          sourceNode.value?.removeClass('cy-connecting');
          sourceNode.value = null;
          isConnecting.value = false;
          emit('update:currentMode', 'select');
          emit('element-selected', newEdge);
        } else if (!sourceNode.value) {
          sourceNode.value = tappedNode;
          sourceNode.value.addClass('cy-connecting');
          isConnecting.value = true;
          emit('element-selected', sourceNode.value.data());
        }
      } else if (isBackgroundClick) {
        sourceNode.value?.removeClass('cy-connecting');
        sourceNode.value = null;
        isConnecting.value = false;
        emit('element-selected', null);
      }
      break;

    default: // 'select' mode
      if (isNodeClick || isEdgeClick) {
        emit('element-selected', target.data());
      } else if (isBackgroundClick) {
        emit('element-selected', null);
      }
      break;
  }
};

const handleNodeMoved = (payload: { nodeId: string, position: { x: number; y: number }, parentId: string | undefined }) => {
  const elementToUpdate = elements.value.find(el => el.id === payload.nodeId) as GraphNode | undefined;

  if (elementToUpdate) {
    const updatedNode: GraphNode = {
      ...elementToUpdate,
      position: payload.position,
      parent: payload.parentId
    };
    updateElement(updatedNode);
  }
};

const handleNodeDropped = (payload: { nodeType: NodeType; position: { x: number; y: number } }) => {
  const { nodeType, position } = payload;
  const cy = getCyInstance();
  let parentPlateId: string | undefined = undefined;

  // Handle plate creation separately to satisfy the type checker and simplify logic.
  if (nodeType === 'plate') {
      if (cy) {
          // Check if dropping inside another plate, which is not allowed.
          const plates = cy.nodes('[nodeType="plate"]');
          for (const plate of plates) {
              const bb = plate.boundingBox();
              if (position.x > bb.x1 && position.x < bb.x2 && position.y > bb.y1 && position.y < bb.y2) {
                  alert("Nesting plates is not currently supported.");
                  return;
              }
          }
      }
      const newPlate = createPlateWithNode(position);
      emit('element-selected', newPlate);
      emit('update:currentMode', 'select');
      return; // Exit after creating the plate.
  }
  
  // Handle all other node types.
  if (cy) {
    const plates = cy.nodes('[nodeType="plate"]');
    for (const plate of plates) {
      const bb = plate.boundingBox();
      if (position.x > bb.x1 && position.x < bb.x2 && position.y > bb.y1 && position.y < bb.y2) {
        parentPlateId = plate.id();
        break;
      }
    }
  }

  const newId = `node_${crypto.randomUUID().substring(0, 8)}`;
  const newNode: GraphNode = {
    id: newId,
    name: `${nodeType} ${elements.value.filter(e => e.type === 'node').length + 1}`,
    type: 'node',
    nodeType: nodeType,
    position: position,
    parent: parentPlateId,
    distribution: nodeType === 'stochastic' ? 'dnorm' : undefined,
    equation: nodeType === 'deterministic' ? '' : undefined,
    observed: nodeType === 'observed' ? true : undefined,
  };
  addElement(newNode);
  emit('element-selected', newNode);
  emit('update:currentMode', 'select');
};

const handlePlateEmptied = (plateId: string) => {
    deleteElement(plateId);
};

watch(() => props.currentMode, (newMode) => {
  if (newMode !== 'add-edge') {
    sourceNode.value?.removeClass('cy-connecting');
    sourceNode.value = null;
    isConnecting.value = false;
  }
});
</script>

<template>
  <div class="graph-editor-container">
    <CanvasToolbar
      :current-mode="props.currentMode"
      :current-node-type="props.currentNodeType"
      @update:current-mode="(mode: string) => emit('update:currentMode', mode)"
      @update:current-node-type="(type: NodeType) => emit('update:currentNodeType', type)"
      :is-connecting="isConnecting"
      :source-node-name="sourceNode?.data('name')"
    />

    <GraphCanvas
      :elements="elements"
      :is-grid-enabled="isGridEnabled"
      :grid-size="gridSize"
      :current-mode="props.currentMode"
      @canvas-tap="handleCanvasTap"
      @node-moved="handleNodeMoved"
      @node-dropped="handleNodeDropped"
      @plate-emptied="handlePlateEmptied"
    />
  </div>
</template>

<style scoped>
.graph-editor-container {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  position: relative;
  overflow: hidden;
}
</style>
