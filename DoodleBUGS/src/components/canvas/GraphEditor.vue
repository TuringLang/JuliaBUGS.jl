<script setup lang="ts">
import { ref, watch } from 'vue';
import type { NodeSingular, EventObject, Core } from 'cytoscape';
import GraphCanvas from './GraphCanvas.vue';
import CanvasToolbar from './CanvasToolbar.vue';
import { useGraphElements } from '../../composables/useGraphElements';
import { useGraphInstance } from '../../composables/useGraphInstance';
import type { GraphElement, GraphNode, GraphEdge, NodeType, ValidationError } from '../../types';
import { getDefaultNodeData } from '../../config/nodeDefinitions';

const props = defineProps<{
  isGridEnabled: boolean;
  gridSize: number;
  currentMode: string;
  currentNodeType: NodeType;
  elements: GraphElement[];
  validationErrors: Map<string, ValidationError[]>;
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

const greekAlphabet = [
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 
  'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'omicron', 'pi', 'rho', 
  'sigma', 'tau', 'upsilon', 'phi', 'chi', 'psi', 'omega'
];

const MAX_NODE_NAME_ITERATIONS = 1000;

const getNextNodeName = (): string => {
    const existingNames = new Set(
        elements.value
            .filter(el => el.type === 'node')
            .map(el => (el as GraphNode).name)
    );

    for (const letter of greekAlphabet) {
        if (!existingNames.has(letter)) {
            return letter;
        }
    }

    // Fallback if all Greek letters are used
    let i = 1;
    while (i < MAX_NODE_NAME_ITERATIONS) { // reasonable limit to prevent infinite loops
        const fallbackName = `var${i}`;
        if (!existingNames.has(fallbackName)) {
            return fallbackName;
        }
        i++;
    }

    // Ultimate fallback for extreme cases
    return `node_${Date.now()}`;
};


const createNode = (nodeType: NodeType, position: { x: number; y: number }, parentId?: string): GraphNode => {
    const defaultData = getDefaultNodeData(nodeType);
    const newId = `node_${crypto.randomUUID().substring(0, 8)}`;
    const newName = nodeType === 'plate' ? 'Plate' : getNextNodeName();

    const newNode: GraphNode = {
        ...defaultData,
        id: newId,
        type: 'node',
        nodeType: nodeType,
        position: position,
        parent: parentId,
        name: newName,
    };

    if (newNode.nodeType === 'stochastic' || newNode.nodeType === 'observed') {
        if (newNode.distribution === 'dnorm') {
            newNode.param1 = "0.0";
            newNode.param2 = "1.0";
        }
        if (newNode.distribution === 'dgamma') {
            newNode.param1 = "0.001";
            newNode.param2 = "0.001";
        }
    }

    return newNode;
};

const createPlateWithNode = (position: { x: number; y: number }, parentId?: string): GraphNode => {
    const newPlate = createNode('plate', position, parentId);
    const innerNode = createNode('stochastic', { x: position.x, y: position.y }, newPlate.id);
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
            const newPlate = createPlateWithNode(position, isPlateClick ? (target as NodeSingular).id() : undefined);
            emit('element-selected', newPlate);
            emit('update:currentMode', 'select');
        } else {
            const newNode = createNode(props.currentNodeType, position, isPlateClick ? (target as NodeSingular).id() : undefined);
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
            name: ``,
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

    default:
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

  if (nodeType === 'plate') {
      // Find parent plate for nested plate creation
      let parentPlateId: string | undefined = undefined;
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
      const newPlate = createPlateWithNode(position, parentPlateId);
      emit('element-selected', newPlate);
      emit('update:currentMode', 'select');
      return;
  }
  
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

  const newNode = createNode(nodeType, position, parentPlateId);
  addElement(newNode);
  emit('element-selected', newNode);
  emit('update:currentMode', 'select');
};

const handleDeleteElement = (elementId: string) => {
    deleteElement(elementId);
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
      :elements="props.elements"
      :is-grid-enabled="isGridEnabled"
      :grid-size="gridSize"
      :current-mode="props.currentMode"
      :validation-errors="props.validationErrors"
      @canvas-tap="handleCanvasTap"
      @node-moved="handleNodeMoved"
      @node-dropped="handleNodeDropped"
      @delete-element="handleDeleteElement"
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
