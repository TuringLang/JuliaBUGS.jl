<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import type { Core, EventObject, NodeSingular, ElementDefinition } from 'cytoscape'
import { useToast } from 'primevue/usetoast'
import { useGraphInstance } from '../../composables/useGraphInstance'
import { useGridSnapping } from '../../composables/useGridSnapping'
import type {
  GraphElement,
  GraphNode,
  GraphEdge,
  NodeType,
  PaletteItemType,
  ValidationError,
} from '../../types'
import type { GridStyle } from '../../stores/uiStore'
import { useUiStore } from '../../stores/uiStore'

const props = defineProps<{
  graphId: string
  elements: GraphElement[]
  isGridEnabled: boolean
  gridSize: number
  gridStyle?: GridStyle
  currentMode: string
  validationErrors: Map<string, ValidationError[]>
  showZoomControls?: boolean
  initialViewport?: { zoom: number; pan: { x: number; y: number } }
}>()

const emit = defineEmits<{
  (e: 'canvas-tap', event: EventObject): void
  (
    e: 'node-moved',
    payload: { nodeId: string; position: { x: number; y: number }; parentId: string | undefined }
  ): void
  (e: 'node-dropped', payload: { nodeType: NodeType; position: { x: number; y: number } }): void
  (e: 'plate-emptied', plateId: string): void
  (e: 'element-remove', elementId: string): void
  (e: 'update:show-zoom-controls', value: boolean): void
  (e: 'graph-updated', elements: GraphElement[]): void
  (e: 'viewport-changed', viewport: { zoom: number; pan: { x: number; y: number } }): void
}>()

const cyContainer = ref<HTMLElement | null>(null)
let cy: Core | null = null
const cyInstance = ref<Core | null>(null)
let resizeObserver: ResizeObserver | null = null

const toast = useToast()
const { initCytoscape, destroyCytoscape, getCyInstance, getUndoRedoInstance } = useGraphInstance()
const getCy = () => getCyInstance(props.graphId)
const { enableGridSnapping, disableGridSnapping, setGridSize } = useGridSnapping(getCy)
const uiStore = useUiStore()

const isGraphVisible = ref(false)
const isGraphReady = ref(false)

const validNodeTypes: NodeType[] = ['stochastic', 'deterministic', 'constant', 'observed', 'plate']

const formatElementsForCytoscape = (
  elements: GraphElement[],
  errors: Map<string, ValidationError[]>
): ElementDefinition[] => {
  return elements.map((el) => {
    if (el.type === 'node') {
      const node = el as GraphNode
      const hasError = errors.has(node.id)
      return {
        group: 'nodes',
        data: { ...node, hasError },
        position: node.position,
      }
    } else {
      const edge = el as GraphEdge
      const targetNode = elements.find((n) => n.id === edge.target && n.type === 'node') as
        | GraphNode
        | undefined
      const relType =
        targetNode?.nodeType === 'stochastic' || targetNode?.nodeType === 'observed'
          ? 'stochastic'
          : 'deterministic'
      return {
        group: 'edges',
        data: {
          ...edge,
          relationshipType: relType,
        },
      }
    }
  })
}

const syncGraphWithProps = (
  elementsToSync: GraphElement[],
  errorsToSync: Map<string, ValidationError[]>
) => {
  if (!cy) return

  const formattedElements = formatElementsForCytoscape(elementsToSync, errorsToSync)

  cy.batch(() => {
    const newElementIds = new Set(elementsToSync.map((el) => el.id))

    // Remove deleted elements, preserving ghost nodes used for drag operations
    cy!.elements().forEach((cyEl) => {
      if (!newElementIds.has(cyEl.id()) && !cyEl.id().startsWith('ghost_')) {
        cyEl.remove()
      }
    })

    const nodes = formattedElements.filter((el) => el.group === 'nodes')
    const edges = formattedElements.filter((el) => el.group === 'edges')

    // Sort nodes by depth (parents before children) to ensure correct parentage assignment
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const nodeDefMap = new Map<string, any>(nodes.map((n) => [n.data.id as string, n]))
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const getDepth = (n: any, visited = new Set<string>()): number => {
      const id = n.data.id
      if (visited.has(id)) return 0
      visited.add(id)
      const parentId = n.data.parent
      if (!parentId) return 0
      const parentDef = nodeDefMap.get(parentId)
      if (parentDef) {
        return 1 + getDepth(parentDef, visited)
      }
      return 0
    }
    nodes.sort((a, b) => getDepth(a) - getDepth(b))

    nodes.forEach((formattedEl) => {
      if (!formattedEl.data.id) return

      const existingCyEl = cy!.getElementById(formattedEl.data.id)

      if (existingCyEl.empty()) {
        cy!.add(formattedEl)
      } else {
        // Optimization: Only update data if changed
        const currentData = existingCyEl.data()
        const newData = formattedEl.data
        if (JSON.stringify(currentData) !== JSON.stringify(newData)) {
          existingCyEl.data(newData)
        }

        const newNode = formattedEl as ElementDefinition & { position: { x: number; y: number } }
        const currentCyPos = existingCyEl.position()
        if (
          Math.abs(newNode.position.x - currentCyPos.x) > 0.01 ||
          Math.abs(newNode.position.y - currentCyPos.y) > 0.01
        ) {
          existingCyEl.position(newNode.position)
        }

        const parentCollection = existingCyEl.parent()
        const currentParentId =
          parentCollection.length > 0 ? parentCollection.first().id() : undefined

        if (newNode.data.parent !== currentParentId) {
          existingCyEl.move({ parent: newNode.data.parent ?? null })
        }
      }
    })

    edges.forEach((formattedEl) => {
      if (!formattedEl.data.id) return

      const existingCyEl = cy!.getElementById(formattedEl.data.id)

      if (existingCyEl.empty()) {
        const srcId = formattedEl.data.source
        const tgtId = formattedEl.data.target
        // Safety check: ensure source and target exist before adding edge
        if (cy!.getElementById(srcId).nonempty() && cy!.getElementById(tgtId).nonempty()) {
          cy!.add(formattedEl)
        } else {
          console.warn(
            `Skipping edge ${formattedEl.data.id}: source ${srcId} or target ${tgtId} missing`
          )
        }
      } else {
        if (JSON.stringify(existingCyEl.data()) !== JSON.stringify(formattedEl.data)) {
          existingCyEl.data(formattedEl.data)
        }
      }
    })
  })
}

const getSerializedElements = (): GraphElement[] => {
  if (!cy) return []
  return (
    cy
      .elements()
      .toArray()
      // Exclude temporary "ghost" nodes from serialization
      .filter((ele) => !ele.id().startsWith('ghost_'))
      .map((ele) => {
        const data = ele.data()
        // Remove temporary UI state flags
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const { hasError, ...cleanData } = data

        if (ele.isNode()) {
          const parentCollection = ele.parent()
          const parentId = parentCollection.length > 0 ? parentCollection.first().id() : undefined
          return {
            ...cleanData,
            type: 'node',
            position: ele.position(),
            parent: parentId,
          } as GraphNode
        } else {
          return {
            ...cleanData,
            type: 'edge',
            source: ele.source().id(),
            target: ele.target().id(),
          } as GraphEdge
        }
      })
  )
}

const updateGridStyle = () => {
  if (!cyContainer.value || !cy) return

  if (props.isGridEnabled && props.gridSize > 0) {
    const pan = cy.pan()
    const zoom = cy.zoom()
    const scaledSize = props.gridSize * zoom

    cyContainer.value.style.backgroundPosition = `${pan.x}px ${pan.y}px`
    cyContainer.value.style.backgroundSize = `${scaledSize}px ${scaledSize}px`
  } else {
    cyContainer.value.style.backgroundPosition = ''
    cyContainer.value.style.backgroundSize = ''
  }
}

// Updated mapping for dynamic summary based on severity
const summaryMap: Record<'info' | 'warn' | 'error' | 'success', string> = {
  info: 'Info',
  warn: 'Warning',
  error: 'Error',
  success: 'Success',
}

const handleToast = (message: string, severity: 'info' | 'warn' | 'error' | 'success' = 'info') => {
  toast.add({ severity: severity, summary: summaryMap[severity], detail: message, life: 3000 })
}

onMounted(() => {
  if (cyContainer.value) {
    // Initialize Cytoscape (elements synced later on resize)
    cy = initCytoscape(cyContainer.value, [], props.graphId, handleToast)
    cyInstance.value = cy

    setGridSize(props.gridSize)

    if (props.isGridEnabled) {
      enableGridSnapping()
    } else {
      disableGridSnapping()
    }

    const ur = getUndoRedoInstance(props.graphId)
    if (ur) {
      cy.on('afterUndo afterRedo afterDo', () => {
        if (!cy) return
        emit('graph-updated', getSerializedElements())
      })
    }

    cy.on('layoutstop', () => {
      if (cy && cy.elements().length > 0) {
        emit('graph-updated', getSerializedElements())
      }
      updateGridStyle()
    })

    let rafId: number | null = null
    const emitViewport = () => {
      if (!cy) return
      updateGridStyle()
      emit('viewport-changed', { zoom: cy.zoom(), pan: cy.pan() })
      rafId = null
    }
    cy.on('pan zoom', () => {
      if (rafId === null) {
        rafId = requestAnimationFrame(emitViewport)
      }
    })

    cy.container()?.addEventListener('cxt-remove', (event: Event) => {
      const customEvent = event as CustomEvent
      if (customEvent.detail.elementId) {
        emit('element-remove', customEvent.detail.elementId)
      }
    })

    cy.on('tap', (evt: EventObject) => {
      emit('canvas-tap', evt)
    })

    cy.on('free', 'node', (evt: EventObject) => {
      const node = evt.target as NodeSingular

      if (node.id().startsWith('ghost_')) return

      const parentCollection = node.parent()
      const parentId = parentCollection.length > 0 ? parentCollection.first().id() : undefined

      emit('node-moved', {
        nodeId: node.id(),
        position: node.position(),
        parentId: parentId,
      })
    })

    cy.on('tap', 'node, edge', (evt: EventObject) => {
      cy?.elements().removeClass('cy-selected')
      evt.target.addClass('cy-selected')
    })
    cy.on('tap', (evt: EventObject) => {
      if (evt.target === cy) {
        cy?.elements().removeClass('cy-selected')
      }
    })

    cyContainer.value.addEventListener('dragover', (event) => {
      event.preventDefault()
      if (event.dataTransfer) {
        event.dataTransfer.dropEffect = 'copy'
      }
    })

    cyContainer.value.addEventListener('drop', (event) => {
      event.preventDefault()

      if (event.dataTransfer) {
        const droppedItemType = event.dataTransfer.getData('text/plain') as PaletteItemType
        if (validNodeTypes.includes(droppedItemType as NodeType)) {
          const bbox = cyContainer.value?.getBoundingClientRect()
          if (bbox && cy) {
            const clientX = event.clientX
            const clientY = event.clientY
            const renderedPos = { x: clientX - bbox.left, y: clientY - bbox.top }
            const pan = cy.pan()
            const zoom = cy.zoom()
            const modelPos = {
              x: (renderedPos.x - pan.x) / zoom,
              y: (renderedPos.y - pan.y) / zoom,
            }
            emit('node-dropped', { nodeType: droppedItemType as NodeType, position: modelPos })
          }
        }
      }
    })

    resizeObserver = new ResizeObserver(() => {
      if (cy) {
        cy.resize()
        if (cy.width() > 0 && cy.height() > 0) {
          if (!isGraphReady.value) {
            isGraphReady.value = true

            // Populate graph and set initial viewport
            syncGraphWithProps(props.elements, props.validationErrors)

            if (props.initialViewport) {
              cy.viewport({
                zoom: props.initialViewport.zoom,
                pan: props.initialViewport.pan,
              })
            } else if (props.elements.length > 0) {
              cy.fit(undefined, 50)
              if (cy.zoom() > 0.8) {
                cy.zoom(0.8)
                cy.center()
              }
            }

            updateGridStyle()

            // Delay visibility slightly to ensure the canvas has painted the new state
            requestAnimationFrame(() => {
              isGraphVisible.value = true
            })
          } else {
            updateGridStyle()
          }
        }
      }
    })
    resizeObserver.observe(cyContainer.value)
  }
})

onUnmounted(() => {
  if (resizeObserver) {
    resizeObserver.disconnect()
    resizeObserver = null
  }
  if (cy) {
    destroyCytoscape(props.graphId)
  }
})

watch(
  () => props.isGridEnabled,
  (newValue: boolean) => {
    if (newValue) {
      enableGridSnapping()
      updateGridStyle()
    } else {
      disableGridSnapping()
      if (cyContainer.value) {
        cyContainer.value.style.backgroundPosition = ''
        cyContainer.value.style.backgroundSize = ''
      }
    }
  }
)

watch(
  () => props.gridSize,
  (newValue: number) => {
    setGridSize(newValue)
    if (props.isGridEnabled) {
      enableGridSnapping()
      updateGridStyle()
    }
  }
)

watch(
  [() => props.elements, () => props.validationErrors],
  ([newElements, newErrors]) => {
    // Only sync if graph is ready (container sized and initialized)
    if (isGraphReady.value) {
      syncGraphWithProps(newElements, newErrors)
    }
  },
  { deep: true }
)

// Watch for global style changes and force update (for both nodes and edges)
watch(
  [() => uiStore.nodeStyles, () => uiStore.edgeStyles],
  () => {
    if (cy) {
      cy.style().update()
    }
  },
  { deep: true }
)
</script>

<template>
  <div
    ref="cyContainer"
    class="cytoscape-container"
    :class="{
      'grid-background': isGridEnabled && gridSize > 0,
      'grid-lines': gridStyle === 'lines' && isGridEnabled && gridSize > 0,
      'grid-dots': gridStyle === 'dots' && isGridEnabled && gridSize > 0,
      'mode-add-node': currentMode === 'add-node',
      'mode-add-edge': currentMode === 'add-edge',
      'mode-select': currentMode === 'select',
      'graph-ready': isGraphVisible,
    }"
    :style="{
      transition: isGraphVisible ? 'opacity 0.3s ease-in-out' : 'none',
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
  background-position: 0 0;
  background-repeat: repeat;
  width: 100%;
  height: 100%;
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

.cdnd-grabbed-node {
  background-color: #ffd700 !important;
  opacity: 0.7;
  border: 2px dashed #ffa500;
}

.cdnd-drop-target {
  border: 3px solid #32cd32 !important;
  background-color: rgba(50, 205, 50, 0.1) !important;
}

.cdnd-drag-out {
  border: 2px dashed #ff0000 !important;
  background-color: rgba(255, 0, 0, 0.1) !important;
}

.cytoscape-container.grid-background.grid-dots {
  background-image: radial-gradient(
    circle,
    var(--theme-text-secondary) 1.2px,
    transparent 1px
  ) !important;
  opacity: 0.8;
}

html.dark-mode .cytoscape-container.grid-background.grid-dots {
  background-image: radial-gradient(
    circle,
    rgba(255, 255, 255, 0.2) 1.2px,
    transparent 1px
  ) !important;
}

.cytoscape-container.grid-background.grid-lines {
  background-image:
    linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px) !important;
}
</style>
