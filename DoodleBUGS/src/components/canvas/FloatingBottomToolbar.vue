<script setup lang="ts">
import { computed, ref, onUnmounted, watch } from 'vue'
import type { NodeType } from '../../types'
import { nodeDefinitions } from '../../config/nodeDefinitions'
import DropdownMenu from '../common/DropdownMenu.vue'
import Tooltip from 'primevue/tooltip'

const vTooltip = Tooltip

const props = defineProps<{
  currentMode: string
  currentNodeType: NodeType
  showCodePanel?: boolean
  showDataPanel?: boolean
  showZoomControls?: boolean
  isDetachModeActive?: boolean
  showDetachModeControl?: boolean
  isWidget?: boolean
}>()

const emit = defineEmits<{
  (e: 'update:currentMode', mode: string): void
  (e: 'update:currentNodeType', type: NodeType): void
  (e: 'undo'): void
  (e: 'redo'): void
  (e: 'zoom-in'): void
  (e: 'zoom-out'): void
  (e: 'fit'): void
  (e: 'layout-graph', layout: string): void
  (e: 'toggle-code-panel'): void
  (e: 'toggle-data-panel'): void
  (e: 'toggle-detach-mode'): void
  (e: 'open-style-modal'): void
  (e: 'share'): void
  (e: 'nav', view: string): void
  (e: 'drag-start'): void
  (e: 'drag-end', position: { x: number; y: number }): void
}>()

const availableNodeTypes = computed(() => {
  return nodeDefinitions.map((def) => ({
    label: def.label,
    value: def.nodeType,
    icon: def.icon,
  }))
})

const setMode = (mode: string) => {
  emit('update:currentMode', mode)
}

const nodeIcons: Record<string, string> = {
  stochastic: 'fas fa-random',
  deterministic: 'fas fa-calculator',
  constant: 'fas fa-square',
  observed: 'fas fa-eye',
  plate: 'fas fa-th-large',
}

const nodeColors: Record<string, string> = {
  stochastic: '#ef4444',
  deterministic: '#10b981',
  constant: '#6b7280',
  observed: '#3b82f6',
  plate: '#8b5cf6',
  edge: '#f59e0b',
}

const lastAddTool = ref<NodeType | 'edge'>(props.currentNodeType)

watch(
  () => props.currentMode,
  (newMode) => {
    if (newMode === 'add-edge') {
      lastAddTool.value = 'edge'
    } else if (newMode === 'add-node') {
      lastAddTool.value = props.currentNodeType
    }
  }
)

watch(
  () => props.currentNodeType,
  (newType) => {
    if (props.currentMode === 'add-node') {
      lastAddTool.value = newType
    }
  }
)

const currentAddToolIcon = computed(() => {
  if (lastAddTool.value === 'edge') return 'fas fa-bezier-curve'
  return nodeIcons[lastAddTool.value] || 'fas fa-circle'
})

const currentAddToolColor = computed(() => {
  if (lastAddTool.value === 'edge') return nodeColors.edge
  return nodeColors[lastAddTool.value] || 'var(--theme-primary)'
})

const currentAddToolLabel = computed(() => {
  if (lastAddTool.value === 'edge') return 'Edge'
  const node = availableNodeTypes.value.find((n) => n.value === lastAddTool.value)
  return node ? node.label : 'Node'
})

const isAddModeActive = computed(() => {
  if (lastAddTool.value === 'edge') return props.currentMode === 'add-edge'
  return props.currentMode === 'add-node' && props.currentNodeType === lastAddTool.value
})

const selectAddTool = (tool: NodeType | 'edge') => {
  lastAddTool.value = tool
  if (tool === 'edge') {
    emit('update:currentMode', 'add-edge')
  } else {
    emit('update:currentNodeType', tool)
    emit('update:currentMode', 'add-node')
  }
}

const addButtonStyle = computed(() => {
  if (isAddModeActive.value) {
    const color = currentAddToolColor.value
    return {
      backgroundColor: color,
      borderColor: color,
      color: '#ffffff',
    }
  }
  return {}
})

const toolbarRef = ref<HTMLElement | null>(null)
const isDragging = ref(false)
const styleState = ref({
  left: '50%',
  bottom: '24px',
  top: 'auto',
  transform: 'translateX(-50%)',
})
const dragOffset = ref({ x: 0, y: 0 })
let animationFrameId: number | null = null

// When dragging starts, calculate position relative to the offset parent (the widget container) or viewport
const startDrag = (event: MouseEvent) => {
  if (
    (event.target as HTMLElement).closest('button') ||
    (event.target as HTMLElement).closest('select') ||
    (event.target as HTMLElement).closest('.p-popover') ||
    (event.target as HTMLElement).closest('input')
  )
    return

  if (!toolbarRef.value) return

  isDragging.value = true
  emit('drag-start') // Signal start of drag
  
  const toolbar = toolbarRef.value
  const rect = toolbar.getBoundingClientRect()

  dragOffset.value = {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  }

  let relX = 0
  let relY = 0

  if (props.isWidget) {
    // Absolute positioning (Embedded): Calculate relative to offset parent
    const parent = toolbar.offsetParent as HTMLElement || document.body
    const parentRect = parent.getBoundingClientRect()
    relX = rect.left - parentRect.left
    relY = rect.top - parentRect.top
  } else {
    // Fixed positioning (Fullscreen): Calculate relative to viewport
    relX = rect.left
    relY = rect.top
  }

  styleState.value = {
    left: '0px',
    top: '0px',
    bottom: 'auto',
    transform: `translate3d(${relX}px, ${relY}px, 0)`,
  }

  window.addEventListener('mousemove', onDrag)
  window.addEventListener('mouseup', stopDrag)
}

const onDrag = (event: MouseEvent) => {
  if (!isDragging.value) return

  // Throttle updates using requestAnimationFrame
  if (animationFrameId) return

  animationFrameId = requestAnimationFrame(() => {
    const toolbar = toolbarRef.value
    if (!toolbar) return
    
    let x = 0
    let y = 0

    if (props.isWidget) {
      // Absolute positioning
      const parent = toolbar.offsetParent as HTMLElement || document.body
      const parentRect = parent.getBoundingClientRect()
      x = event.clientX - dragOffset.value.x - parentRect.left
      y = event.clientY - dragOffset.value.y - parentRect.top
    } else {
      // Fixed positioning
      x = event.clientX - dragOffset.value.x
      y = event.clientY - dragOffset.value.y
    }
    
    styleState.value.transform = `translate3d(${x}px, ${y}px, 0)`
    animationFrameId = null
  })
}

const stopDrag = () => {
  isDragging.value = false
  emit('drag-end', { x: 0, y: 0 })
  if (animationFrameId) cancelAnimationFrame(animationFrameId)
  animationFrameId = null
  window.removeEventListener('mousemove', onDrag)
  window.removeEventListener('mouseup', stopDrag)
}

// Touch Support
const startDragTouch = (event: TouchEvent) => {
  if (
    (event.target as HTMLElement).closest('button') ||
    (event.target as HTMLElement).closest('select') ||
    (event.target as HTMLElement).closest('.p-popover') ||
    (event.target as HTMLElement).closest('input')
  )
    return

  if (!toolbarRef.value) return

  isDragging.value = true
  emit('drag-start') // Signal start of drag
  
  const touch = event.touches[0]
  const toolbar = toolbarRef.value
  const rect = toolbar.getBoundingClientRect()

  dragOffset.value = {
    x: touch.clientX - rect.left,
    y: touch.clientY - rect.top,
  }

  let relX = 0
  let relY = 0

  if (props.isWidget) {
    const parent = toolbar.offsetParent as HTMLElement || document.body
    const parentRect = parent.getBoundingClientRect()
    relX = rect.left - parentRect.left
    relY = rect.top - parentRect.top
  } else {
    relX = rect.left
    relY = rect.top
  }

  styleState.value = {
    left: '0px',
    top: '0px',
    bottom: 'auto',
    transform: `translate3d(${relX}px, ${relY}px, 0)`,
  }

  window.addEventListener('touchmove', onDragTouch, { passive: false })
  window.addEventListener('touchend', stopDragTouch)
}

const onDragTouch = (event: TouchEvent) => {
  if (!isDragging.value) return
  event.preventDefault() // Prevent scrolling while dragging
  const touch = event.touches[0]

  if (animationFrameId) return

  animationFrameId = requestAnimationFrame(() => {
    const toolbar = toolbarRef.value
    if (!toolbar) return
    
    let x = 0
    let y = 0

    if (props.isWidget) {
      const parent = toolbar.offsetParent as HTMLElement || document.body
      const parentRect = parent.getBoundingClientRect()
      x = touch.clientX - dragOffset.value.x - parentRect.left
      y = touch.clientY - dragOffset.value.y - parentRect.top
    } else {
      x = touch.clientX - dragOffset.value.x
      y = touch.clientY - dragOffset.value.y
    }
    
    styleState.value.transform = `translate3d(${x}px, ${y}px, 0)`
    animationFrameId = null
  })
}

const stopDragTouch = () => {
  isDragging.value = false
  emit('drag-end', { x: 0, y: 0 })
  if (animationFrameId) cancelAnimationFrame(animationFrameId)
  animationFrameId = null
  window.removeEventListener('touchmove', onDragTouch)
  window.removeEventListener('touchend', stopDragTouch)
}

onUnmounted(() => {
  window.removeEventListener('mousemove', onDrag)
  window.removeEventListener('mouseup', stopDrag)
  window.removeEventListener('touchmove', onDragTouch)
  window.removeEventListener('touchend', stopDragTouch)
})
</script>

<template>
  <div
    class="db-toolbar-container"
    ref="toolbarRef"
    :class="{ 'db-position-fixed': !isWidget }"
    :style="styleState"
    @mousedown="startDrag"
    @touchstart="startDragTouch"
  >
    <!-- Main Toolbar -->
    <div class="db-floating-dock db-glass-panel">
      <div
        class="db-drag-handle"
        v-tooltip.top="{ value: 'Drag Toolbar', showDelay: 0, hideDelay: 0 }"
      >
        <i class="fas fa-grip-vertical"></i>
      </div>

      <!-- Tools Group -->
      <button
        class="db-dock-btn"
        :class="{ 'db-active': currentMode === 'select' }"
        @click="setMode('select')"
        v-tooltip.top="{ value: 'Select Tool', showDelay: 0, hideDelay: 0 }"
        type="button"
      >
        <i class="fas fa-mouse-pointer"></i>
      </button>

      <DropdownMenu class="db-dock-dropdown add-tool-dropdown">
        <template #trigger>
          <button
            class="db-add-tool-btn"
            :class="{ 'db-active': isAddModeActive }"
            :style="addButtonStyle"
            v-tooltip.top="{ value: 'Add Node or Edge', showDelay: 0, hideDelay: 0 }"
            type="button"
          >
            <i
              :class="currentAddToolIcon"
              class="db-tool-icon"
              :style="{ color: isAddModeActive ? 'white' : currentAddToolColor }"
            ></i>
            <span
              class="db-tool-label"
              :style="{ color: isAddModeActive ? 'white' : 'var(--theme-text-primary)' }"
            >
              {{ currentAddToolLabel }}
            </span>
            <i
              class="fas fa-chevron-down db-arrow-icon"
              :style="{ color: isAddModeActive ? 'white' : 'var(--theme-text-muted)' }"
            ></i>
          </button>
        </template>
        <template #content>
          <div class="db-dropdown-section-title">Nodes</div>
          <a
            href="#"
            v-for="type in availableNodeTypes"
            :key="type.value"
            @click.prevent="selectAddTool(type.value)"
          >
            <i
              :class="nodeIcons[type.value]"
              :style="{ color: nodeColors[type.value] }"
              class="menu-icon"
            ></i>
            {{ type.label }}
          </a>
          <div class="db-dropdown-divider"></div>
          <div class="db-dropdown-section-title">Connections</div>
          <a href="#" @click.prevent="selectAddTool('edge')">
            <i class="fas fa-bezier-curve menu-icon" :style="{ color: nodeColors.edge }"></i> Edge
          </a>
        </template>
      </DropdownMenu>

      <div class="db-divider"></div>

      <!-- History -->
      <button
        class="db-dock-btn"
        @click="$emit('undo')"
        v-tooltip.top="{ value: 'Undo', showDelay: 0, hideDelay: 0 }"
        type="button"
      >
        <i class="fas fa-undo"></i>
      </button>
      <button
        class="db-dock-btn"
        @click="$emit('redo')"
        v-tooltip.top="{ value: 'Redo', showDelay: 0, hideDelay: 0 }"
        type="button"
      >
        <i class="fas fa-redo"></i>
      </button>

      <div class="db-divider"></div>

      <!-- Layout Dropdown -->
      <DropdownMenu class="db-dock-dropdown">
        <template #trigger>
          <button
            class="db-dock-btn"
            v-tooltip.top="{ value: 'Graph Layout', showDelay: 0, hideDelay: 0 }"
            type="button"
          >
            <i class="fas fa-sitemap"></i>
          </button>
        </template>
        <template #content>
          <div class="db-dropdown-section-title">Auto Layout</div>
          <a href="#" @click.prevent="$emit('layout-graph', 'dagre')">Dagre (Hierarchical)</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'fcose')">fCoSE (Force)</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'cola')">Cola (Physics)</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'klay')">KLay (Layered)</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'preset')">Reset Positions</a>
        </template>
      </DropdownMenu>

      <div class="db-divider"></div>

      <!-- Panel Toggles (Moved from Secondary Menu) -->
      <button
        class="db-dock-btn"
        @click="$emit('open-style-modal')"
        v-tooltip.top="{ value: 'Graph Style', showDelay: 0, hideDelay: 0 }"
      >
        <i class="fas fa-palette"></i>
      </button>
      <button
        class="db-dock-btn"
        :class="{ 'db-active': showDataPanel }"
        @click="$emit('toggle-data-panel')"
        v-tooltip.top="{ value: 'Data & Inits', showDelay: 0, hideDelay: 0 }"
      >
        <i class="fas fa-database"></i>
      </button>
      <button
        class="db-dock-btn"
        :class="{ 'db-active': showCodePanel }"
        @click="$emit('toggle-code-panel')"
        v-tooltip.top="{ value: 'BUGS Code', showDelay: 0, hideDelay: 0 }"
      >
        <i class="fas fa-code"></i>
      </button>

      <!-- Zoom (Conditional) -->
      <template v-if="showZoomControls">
        <div class="db-divider"></div>
        <button
          class="db-dock-btn"
          @click="$emit('zoom-in')"
          v-tooltip.top="{ value: 'Zoom In', showDelay: 0, hideDelay: 0 }"
          type="button"
        >
          <i class="fas fa-plus"></i>
        </button>
        <button
          class="db-dock-btn"
          @click="$emit('zoom-out')"
          v-tooltip.top="{ value: 'Zoom Out', showDelay: 0, hideDelay: 0 }"
          type="button"
        >
          <i class="fas fa-minus"></i>
        </button>
        <button
          class="db-dock-btn"
          @click="$emit('fit')"
          v-tooltip.top="{ value: 'Fit to View', showDelay: 0, hideDelay: 0 }"
          type="button"
        >
          <i class="fas fa-compress-arrows-alt"></i>
        </button>
      </template>

      <!-- Detach Toggle (Conditional) -->
      <template v-if="showDetachModeControl">
        <div class="db-divider"></div>
        <button
          class="db-dock-btn"
          :class="{ 'db-active': isDetachModeActive }"
          @click="$emit('toggle-detach-mode')"
          v-tooltip.top="{ value: 'Detach Mode', showDelay: 0, hideDelay: 0 }"
          type="button"
        >
          <i class="fas fa-unlink"></i>
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.db-toolbar-container {
  /* Default to absolute for widget containment */
  position: absolute; 
  z-index: 400; /* Layer 5: Toolbar - above panels, below dropdowns */
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0;
  cursor: grab;
  touch-action: none;
  will-change: transform;
}

/* When in fullscreen/body teleport, switch to fixed positioning */
.db-toolbar-container.db-position-fixed {
  position: fixed;
}

.db-toolbar-container:active {
  cursor: grabbing;
}

.db-floating-dock {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 8px;
  border-radius: var(--radius-pill);
  transition: box-shadow 0.2s ease;
  user-select: none;
  position: relative;
  z-index: 2;
  background: var(--theme-bg-panel);
}

.db-drag-handle {
  color: var(--theme-text-muted);
  cursor: grab;
  padding: 0 6px;
  display: flex;
  align-items: center;
  font-size: 12px;
}

.db-drag-handle:active {
  cursor: grabbing;
}

.db-dock-btn {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  border: none;
  background: transparent;
  color: var(--theme-text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  transition: all 0.2s;
}

.db-dock-btn:hover {
  background: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.db-dock-btn.db-active {
  background: var(--theme-primary);
  color: white;
}

.db-divider {
  width: 1px;
  height: 16px;
  background: var(--theme-border);
  margin: 0 4px;
  align-self: center;
}

.db-add-tool-btn {
  display: flex;
  align-items: center;
  height: 32px;
  border: none;
  background: transparent;
  border-radius: 16px;
  padding: 0 10px;
  cursor: pointer;
  transition: all 0.2s;
  border: 1px solid transparent;
}

.db-add-tool-btn:hover {
  background: var(--theme-bg-hover);
  border-color: var(--theme-border);
}

/* When active, styles are applied via :style binding (colored background) */
.db-add-tool-btn.db-active {
  border-color: transparent;
}

.db-tool-icon {
  font-size: 14px;
  margin-right: 6px;
  pointer-events: none;
}

.db-tool-label {
  font-size: 12px;
  font-weight: 600;
  margin-right: 6px;
  white-space: nowrap;
  pointer-events: none;
}

.db-arrow-icon {
  font-size: 10px;
  opacity: 0.7;
  pointer-events: none;
}

/* Menu Icons */
.menu-icon {
  width: 20px;
  text-align: center;
  margin-right: 4px;
}

/* Dropdown adjustments */
.db-dock-dropdown {
  display: flex;
  align-items: center;
}

.db-dock-dropdown :deep(.p-popover) {
  margin-bottom: 8px;
}

@media (max-width: 768px) {
  .db-toolbar-container {
    bottom: 16px !important;
    left: 50% !important;
    top: auto !important;
    width: 100%;
    max-width: 100vw;
  }
  .db-floating-dock {
    max-width: calc(100vw - 32px);
    overflow-x: auto;
    justify-content: flex-start;
  }
  .db-floating-dock::-webkit-scrollbar {
    display: none;
  }
  .db-floating-dock {
    -ms-overflow-style: none;
    scrollbar-width: none;
  }
  .db-drag-handle {
    display: none;
  }
}

/* Glass Panel Polyfill */
.db-glass-panel {
  background: var(--theme-bg-panel-transparent, rgba(255, 255, 255, 0.95));
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--theme-border);
  box-shadow: var(--shadow-floating);
}
</style>
