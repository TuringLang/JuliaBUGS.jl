<script setup lang="ts">
import { computed, ref, onUnmounted, watch } from 'vue'
import type { NodeType } from '../../types'
import { nodeDefinitions } from '../../config/nodeDefinitions'
import DropdownMenu from '../common/DropdownMenu.vue'

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

// --- Smooth Dragging Logic (Transform-based) ---
const toolbarRef = ref<HTMLElement | null>(null)
const isDragging = ref(false)
// Initial CSS state: Centered at bottom
const styleState = ref({
  left: '50%',
  bottom: '24px',
  top: 'auto',
  transform: 'translateX(-50%)',
})
const dragOffset = ref({ x: 0, y: 0 })
let animationFrameId: number | null = null

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
  const rect = toolbarRef.value.getBoundingClientRect()

  dragOffset.value = {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  }

  // Switch to absolute positioning with transform for performance
  // We lock left/top to 0 and use translate3d for the actual position
  styleState.value = {
    left: '0px',
    top: '0px',
    bottom: 'auto',
    transform: `translate3d(${rect.left}px, ${rect.top}px, 0)`,
  }

  window.addEventListener('mousemove', onDrag)
  window.addEventListener('mouseup', stopDrag)
}

const onDrag = (event: MouseEvent) => {
  if (!isDragging.value) return

  // Throttle updates using requestAnimationFrame
  if (animationFrameId) return

  animationFrameId = requestAnimationFrame(() => {
    const x = event.clientX - dragOffset.value.x
    const y = event.clientY - dragOffset.value.y
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
  const rect = toolbarRef.value.getBoundingClientRect()
  const touch = event.touches[0]

  dragOffset.value = {
    x: touch.clientX - rect.left,
    y: touch.clientY - rect.top,
  }

  styleState.value = {
    left: '0px',
    top: '0px',
    bottom: 'auto',
    transform: `translate3d(${rect.left}px, ${rect.top}px, 0)`,
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
    const x = touch.clientX - dragOffset.value.x
    const y = touch.clientY - dragOffset.value.y
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
    :style="styleState"
    @mousedown="startDrag"
    @touchstart="startDragTouch"
  >
    <div class="db-floating-dock db-glass-panel">
      <div class="db-drag-handle" title="Drag Toolbar">
        <i class="fas fa-grip-vertical"></i>
      </div>

      <!-- Widget-Only Navigation Group -->
      <template v-if="isWidget">
        <button class="db-dock-btn" @click="$emit('nav', 'project')" title="Projects">
          <i class="fas fa-folder"></i>
        </button>
        <button class="db-dock-btn" @click="$emit('nav', 'view')" title="View Options">
          <i class="fas fa-eye"></i>
        </button>
        <div class="db-divider"></div>
      </template>

      <!-- Tools Group -->
      <button
        class="db-dock-btn"
        :class="{ 'db-active': currentMode === 'select' }"
        @click="setMode('select')"
        title="Select Tool (V)"
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
            title="Add Node or Edge"
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

      <!-- Detach Mode (Touch) -->
      <template v-if="showDetachModeControl">
        <button
          class="db-dock-btn"
          :class="{ 'db-active': isDetachModeActive }"
          @click="$emit('toggle-detach-mode')"
          title="Detach Mode (Simulates Alt/Option key)"
          type="button"
        >
          <i class="fas fa-unlink"></i>
        </button>
        <div class="db-divider"></div>
      </template>

      <!-- History & Panels -->
      <button class="db-dock-btn" @click="$emit('undo')" title="Undo (Ctrl+Z)" type="button">
        <i class="fas fa-undo"></i>
      </button>
      <button class="db-dock-btn" @click="$emit('redo')" title="Redo (Ctrl+Y)" type="button">
        <i class="fas fa-redo"></i>
      </button>

      <button
        class="db-dock-btn"
        :class="{ 'db-active': showCodePanel }"
        @click="$emit('toggle-code-panel')"
        title="BUGS Code"
        type="button"
      >
        <i class="fas fa-code"></i>
      </button>

      <button
        class="db-dock-btn"
        :class="{ 'db-active': showDataPanel }"
        @click="$emit('toggle-data-panel')"
        title="Data Panel"
        type="button"
      >
        <i class="fas fa-database"></i>
      </button>

      <button
        class="db-dock-btn"
        @click="$emit('open-style-modal')"
        title="Graph Style"
        type="button"
      >
        <i class="fas fa-palette"></i>
      </button>

      <template v-if="showZoomControls">
        <div class="db-divider"></div>
        <button class="db-dock-btn" @click="$emit('zoom-in')" title="Zoom In" type="button">
          <i class="fas fa-plus"></i>
        </button>
        <button class="db-dock-btn" @click="$emit('zoom-out')" title="Zoom Out" type="button">
          <i class="fas fa-minus"></i>
        </button>
        <button class="db-dock-btn" @click="$emit('fit')" title="Fit to View" type="button">
          <i class="fas fa-compress-arrows-alt"></i>
        </button>
      </template>

      <div class="db-divider"></div>

      <!-- Widget-Only Export & Help Group -->
      <template v-if="isWidget">
        <button class="db-dock-btn" @click="$emit('nav', 'export')" title="Export">
          <i class="fas fa-file-export"></i>
        </button>
        <button class="db-dock-btn" @click="$emit('nav', 'help')" title="Help & Dev Tools">
          <i class="fas fa-question-circle"></i>
        </button>
        <div class="db-divider"></div>
      </template>

      <!-- Layout Dropdown -->
      <DropdownMenu class="db-dock-dropdown">
        <template #trigger>
          <button class="db-dock-btn" title="Graph Layout" type="button">
            <i class="fas fa-sitemap"></i>
          </button>
        </template>
        <template #content>
          <div class="db-dropdown-section-title">Layout</div>
          <a href="#" @click.prevent="$emit('layout-graph', 'dagre')">Dagre</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'fcose')">fCoSE</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'cola')">Cola</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'klay')">KLay</a>
          <a href="#" @click.prevent="$emit('layout-graph', 'preset')">Reset</a>
        </template>
      </DropdownMenu>
    </div>
  </div>
</template>

<style scoped>
.db-toolbar-container {
  position: fixed;
  z-index: 400; /* Layer 5: Toolbar - above panels, below dropdowns */
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  cursor: grab;
  touch-action: none;
  /* Hardware acceleration for smooth movement */
  will-change: transform;
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
  /* Prevent text selection during drag */
  user-select: none;
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
    /* Maintain transform for centering on mobile initially, JS will override if dragged */
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
