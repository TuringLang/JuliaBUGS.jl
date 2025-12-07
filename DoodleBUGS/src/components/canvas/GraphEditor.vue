<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import type { NodeSingular, EventObject, Core } from 'cytoscape'
import GraphCanvas from './GraphCanvas.vue'
import { useGraphElements } from '../../composables/useGraphElements'
import { useGraphInstance } from '../../composables/useGraphInstance'
import { useGraphStore } from '../../stores/graphStore'
import type { GraphElement, GraphNode, GraphEdge, NodeType, ValidationError } from '../../types'
import type { GridStyle } from '../../stores/uiStore'
import { getDefaultNodeData } from '../../config/nodeDefinitions'

// Fallback UUID generator for iOS Safari
const generateUUID = (): string => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

const props = defineProps<{
  graphId: string
  isGridEnabled: boolean
  gridSize: number
  gridStyle?: GridStyle
  currentMode: string
  currentNodeType: NodeType
  elements: GraphElement[]
  validationErrors: Map<string, ValidationError[]>
  showZoomControls?: boolean
}>()

const emit = defineEmits<{
  (e: 'element-selected', element: GraphElement | null): void
  (e: 'update:currentMode', mode: string): void
  (e: 'update:currentNodeType', type: NodeType): void
  (e: 'layout-updated', layoutName: string): void
  (e: 'update:show-zoom-controls', value: boolean): void
  (e: 'update:isGridEnabled', value: boolean): void
  (e: 'update:gridSize', value: number): void
  (e: 'viewport-changed', value: { zoom: number; pan: { x: number; y: number } }): void
}>()

const graphStore = useGraphStore()
const {
  elements: graphElements,
  addElement,
  updateElement,
  deleteElement,
} = useGraphElements(props.graphId)
const { getCyInstance, getUndoRedoInstance } = useGraphInstance()

const initialViewport = computed(() => {
  if (props.graphId && graphStore.graphContents.has(props.graphId)) {
    const content = graphStore.graphContents.get(props.graphId)
    if (content && content.zoom !== undefined && content.pan) {
      return { zoom: content.zoom, pan: content.pan }
    }
  }
  return undefined
})

const handleGraphUpdated = (newElements: GraphElement[]) => {
  graphElements.value = newElements
}

const formatForCy = (el: GraphElement) => {
  if (el.type === 'node') {
    const node = el as GraphNode
    return { group: 'nodes', data: node, position: node.position }
  } else {
    const edge = el as GraphEdge
    return { group: 'edges', data: edge }
  }
}

const sourceNode = ref<NodeSingular | null>(null)
const isConnecting = ref(false)

const greekAlphabet = [
  'alpha',
  'beta',
  'gamma',
  'delta',
  'epsilon',
  'zeta',
  'eta',
  'theta',
  'iota',
  'kappa',
  'lambda',
  'mu',
  'nu',
  'xi',
  'omicron',
  'pi',
  'rho',
  'sigma',
  'tau',
  'upsilon',
  'phi',
  'chi',
  'psi',
  'omega',
]

const getNextNodeName = (): string => {
  const existingNames = new Set(
    graphElements.value
      .filter((el: GraphElement) => el.type === 'node')
      .map((el: GraphElement) => (el as GraphNode).name)
  )

  for (const letter of greekAlphabet) {
    if (!existingNames.has(letter)) {
      return letter
    }
  }

  for (let i = 1; i < 1000; i++) {
    const fallbackName = `var${i}`
    if (!existingNames.has(fallbackName)) {
      return fallbackName
    }
  }

  return `node_${Date.now()}`
}

const createNode = (
  nodeType: NodeType,
  position: { x: number; y: number },
  parentId?: string
): GraphNode => {
  const defaultData = getDefaultNodeData(nodeType)
  const newId = `node_${generateUUID().substring(0, 8)}`
  const newName = nodeType === 'plate' ? 'Plate' : getNextNodeName()

  const newNode: GraphNode = {
    ...defaultData,
    id: newId,
    type: 'node',
    nodeType: nodeType,
    position: position,
    parent: parentId,
    name: newName,
  }

  if (newNode.nodeType === 'stochastic' || newNode.nodeType === 'observed') {
    if (newNode.distribution === 'dnorm') {
      newNode.param1 = '0.0'
      newNode.param2 = '1.0'
    }
    if (newNode.distribution === 'dgamma') {
      newNode.param1 = '0.001'
      newNode.param2 = '0.001'
    }
  }

  return newNode
}

const createPlateWithNode = (position: { x: number; y: number }, parentId?: string): GraphNode => {
  const newPlate = createNode('plate', position, parentId)
  const innerNode = createNode('stochastic', { x: position.x, y: position.y }, newPlate.id)

  const ur = getUndoRedoInstance(props.graphId)
  if (ur) {
    ur.do('batch', [
      { name: 'add', param: formatForCy(newPlate) },
      { name: 'add', param: formatForCy(innerNode) },
    ])
  } else {
    graphElements.value = [...graphElements.value, newPlate, innerNode]
  }
  return newPlate
}

const handleCanvasTap = (event: EventObject) => {
  const { position, target } = event
  const cy = getCyInstance(props.graphId) as Core

  if (!cy) return

  const isBackgroundClick = target === cy
  const isPlateClick = !isBackgroundClick && target.isNode() && target.data('nodeType') === 'plate'
  const isNodeClick = !isBackgroundClick && target.isNode()
  const isEdgeClick = !isBackgroundClick && target.isEdge()

  switch (props.currentMode) {
    case 'add-node':
      if (isBackgroundClick || isPlateClick) {
        if (props.currentNodeType === 'plate') {
          const newPlate = createPlateWithNode(
            position,
            isPlateClick ? (target as NodeSingular).id() : undefined
          )
          emit('element-selected', newPlate)
          // Don't switch back to select mode automatically
        } else {
          const newNode = createNode(
            props.currentNodeType,
            position,
            isPlateClick ? (target as NodeSingular).id() : undefined
          )
          const ur = getUndoRedoInstance(props.graphId)
          if (ur) {
            ur.do('add', formatForCy(newNode))
          } else {
            addElement(newNode)
          }
          emit('element-selected', newNode)
          // Don't switch back to select mode automatically
        }
      }
      break

    case 'add-edge':
      if (isNodeClick) {
        const tappedNode = target as NodeSingular

        if (sourceNode.value && sourceNode.value.id() !== tappedNode.id()) {
          const newEdge: GraphEdge = {
            id: `edge_${generateUUID().substring(0, 8)}`,
            type: 'edge',
            source: sourceNode.value.id(),
            target: tappedNode.id(),
            name: ``,
          }
          const ur = getUndoRedoInstance(props.graphId)
          if (ur) {
            ur.do('add', formatForCy(newEdge))
          } else {
            addElement(newEdge)
          }
          sourceNode.value?.removeClass('cy-connecting')
          sourceNode.value = null
          isConnecting.value = false
          // Keep in add-edge mode to allow adding multiple edges
          // But clear selection so next click can start new edge?
          // Usually edge tool resets or waits for new source.
          // Let's keep it waiting for new source.
          emit('element-selected', newEdge)
        } else if (!sourceNode.value) {
          sourceNode.value = tappedNode
          sourceNode.value.addClass('cy-connecting')
          isConnecting.value = true
          emit('element-selected', sourceNode.value.data())
        } else if (sourceNode.value.id() === tappedNode.id()) {
          // Clicked same node again, maybe deselect?
          sourceNode.value.removeClass('cy-connecting')
          sourceNode.value = null
          isConnecting.value = false
        }
      } else if (isBackgroundClick) {
        sourceNode.value?.removeClass('cy-connecting')
        sourceNode.value = null
        isConnecting.value = false
        emit('element-selected', null)
      }
      break

    default:
      if (isNodeClick || isEdgeClick) {
        emit('element-selected', target.data())
      } else if (isBackgroundClick) {
        emit('element-selected', null)
      }
      break
  }
}

const handleNodeMoved = (payload: {
  nodeId: string
  position: { x: number; y: number }
  parentId: string | undefined
}) => {
  const elementToUpdate = graphElements.value.find(
    (el: GraphElement) => el.id === payload.nodeId
  ) as GraphNode | undefined

  if (elementToUpdate) {
    const updatedNode: GraphNode = {
      ...elementToUpdate,
      position: payload.position,
      parent: payload.parentId,
    }
    updateElement(updatedNode)
    emit('layout-updated', 'preset')
  }
}

const handleNodeDropped = (payload: { nodeType: NodeType; position: { x: number; y: number } }) => {
  const { nodeType, position } = payload
  const cy = getCyInstance(props.graphId)
  let parentPlateId: string | undefined = undefined

  if (nodeType === 'plate') {
    if (cy) {
      const plates = cy.nodes('[nodeType="plate"]')
      for (const plate of plates) {
        const bb = plate.boundingBox()
        if (position.x > bb.x1 && position.x < bb.x2 && position.y > bb.y1 && position.y < bb.y2) {
          parentPlateId = plate.id()
          break
        }
      }
    }
    const newPlate = createPlateWithNode(position, parentPlateId)
    emit('element-selected', newPlate)
    // emit('update:currentMode', 'select'); // DND usually implies a one-off, but let's be consistent if drag from outside
    return
  }

  if (cy) {
    const plates = cy.nodes('[nodeType="plate"]')
    for (const plate of plates) {
      const bb = plate.boundingBox()
      if (position.x > bb.x1 && position.x < bb.x2 && position.y > bb.y1 && position.y < bb.y2) {
        parentPlateId = plate.id()
        break
      }
    }
  }

  const newNode = createNode(nodeType, position, parentPlateId)
  const ur = getUndoRedoInstance(props.graphId)
  if (ur) {
    ur.do('add', formatForCy(newNode))
  } else {
    addElement(newNode)
  }
  emit('element-selected', newNode)
}

const handleDeleteElement = (elementId: string) => {
  const ur = getUndoRedoInstance(props.graphId)
  const cy = getCyInstance(props.graphId)
  if (ur && cy) {
    const el = cy.getElementById(elementId)
    if (el.length > 0) {
      ur.do('remove', el)
    }
  } else {
    deleteElement(elementId)
  }
}

watch(
  () => props.currentMode,
  (newMode) => {
    if (newMode !== 'add-edge') {
      sourceNode.value?.removeClass('cy-connecting')
      sourceNode.value = null
      isConnecting.value = false
    }
  }
)
</script>

<template>
  <div class="graph-editor-container" style="display: flex; flex-direction: column; position: relative; width: 100%; height: 100%; overflow: hidden;">
    <GraphCanvas
      :graph-id="props.graphId"
      :elements="props.elements"
      :is-grid-enabled="isGridEnabled"
      :grid-size="gridSize"
      :grid-style="gridStyle"
      :current-mode="props.currentMode"
      :validation-errors="props.validationErrors"
      :show-zoom-controls="props.showZoomControls"
      :initial-viewport="initialViewport"
      @canvas-tap="handleCanvasTap"
      @node-moved="handleNodeMoved"
      @node-dropped="handleNodeDropped"
      @element-remove="handleDeleteElement"
      @graph-updated="handleGraphUpdated"
      @viewport-changed="(v) => emit('viewport-changed', v)"
      @update:show-zoom-controls="(value: boolean) => emit('update:show-zoom-controls', value)"
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
  height: 100%;
  width: 100%;
}
</style>
