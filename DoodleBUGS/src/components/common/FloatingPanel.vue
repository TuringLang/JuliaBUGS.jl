<script setup lang="ts">
import { ref, computed, onUnmounted, watch } from 'vue'

const props = defineProps<{
  title: string
  icon?: string
  badge?: string
  isOpen: boolean
  defaultWidth?: number
  defaultHeight?: number
  defaultX?: number
  defaultY?: number
  minWidth?: number
  minHeight?: number
  showDownload?: boolean
  showImport?: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'download'): void
  (e: 'import'): void
  (e: 'drag-start'): void
  (e: 'drag-end', position: { x: number; y: number }): void
  (e: 'resize-start'): void
  (e: 'resize-end', size: { width: number; height: number }): void
}>()

const panelRef = ref<HTMLElement | null>(null)

// Position and size state
const width = ref(props.defaultWidth || 400)
const height = ref(props.defaultHeight || 300)
const x = ref(
  props.defaultX ||
    (typeof window !== 'undefined' ? window.innerWidth / 2 - (props.defaultWidth || 400) / 2 : 0)
)
const y = ref(
  props.defaultY ||
    (typeof window !== 'undefined' ? window.innerHeight - (props.defaultHeight || 300) - 100 : 0)
)

// Watch for prop changes to sync with internal state
watch(
  () => props.defaultWidth,
  (newWidth) => {
    if (newWidth !== undefined && newWidth !== width.value) {
      width.value = newWidth
    }
  }
)

watch(
  () => props.defaultHeight,
  (newHeight) => {
    if (newHeight !== undefined && newHeight !== height.value) {
      height.value = newHeight
    }
  }
)

watch(
  () => props.defaultX,
  (newX) => {
    if (newX !== undefined && newX !== x.value) {
      x.value = newX
    }
  }
)

watch(
  () => props.defaultY,
  (newY) => {
    if (newY !== undefined && newY !== y.value) {
      y.value = newY
    }
  }
)

// Dragging state
const isDragging = ref(false)
const dragOffsetX = ref(0)
const dragOffsetY = ref(0)
let dragAnimationFrame: number | null = null
let lastDragX = 0
let lastDragY = 0

// Resizing state
const isResizing = ref(false)
const resizeStartX = ref(0)
const resizeStartY = ref(0)
const resizeStartWidth = ref(0)
const resizeStartHeight = ref(0)
let resizeAnimationFrame: number | null = null
let lastResizeX = 0
let lastResizeY = 0

const panelStyle = computed(() => ({
  // Use translate3d for smooth GPU-accelerated movement
  transform: `translate3d(${x.value}px, ${y.value}px, 0)`,
  // Force top/left to 0 so translate3d works from the origin
  left: '0px',
  top: '0px',
  width: `${width.value}px`,
  height: `${height.value}px`,
}))

// Drag handlers
const startDrag = (e: MouseEvent | TouchEvent) => {
  if (!panelRef.value) return

  isDragging.value = true
  emit('drag-start')

  const rect = panelRef.value.getBoundingClientRect()
  const clientX = e instanceof MouseEvent ? e.clientX : e.touches[0].clientX
  const clientY = e instanceof MouseEvent ? e.clientY : e.touches[0].clientY

  dragOffsetX.value = clientX - rect.left
  dragOffsetY.value = clientY - rect.top

  if (e instanceof MouseEvent) {
    document.addEventListener('mousemove', onDragMove)
    document.addEventListener('mouseup', onDragEnd)
  } else {
    document.addEventListener('touchmove', onDragMoveTouch, { passive: false })
    document.addEventListener('touchend', onDragEnd)
  }
}

const onDragMove = (e: MouseEvent) => {
  if (!isDragging.value) return

  lastDragX = e.clientX - dragOffsetX.value
  lastDragY = e.clientY - dragOffsetY.value

  if (dragAnimationFrame) return

  dragAnimationFrame = requestAnimationFrame(() => {
    x.value = lastDragX
    y.value = lastDragY
    dragAnimationFrame = null
  })
}

const onDragMoveTouch = (e: TouchEvent) => {
  if (!isDragging.value) return
  e.preventDefault()

  lastDragX = e.touches[0].clientX - dragOffsetX.value
  lastDragY = e.touches[0].clientY - dragOffsetY.value

  if (dragAnimationFrame) return

  dragAnimationFrame = requestAnimationFrame(() => {
    x.value = lastDragX
    y.value = lastDragY
    dragAnimationFrame = null
  })
}

const onDragEnd = () => {
  isDragging.value = false
  emit('drag-end', { x: x.value, y: y.value })
  if (dragAnimationFrame) {
    cancelAnimationFrame(dragAnimationFrame)
    dragAnimationFrame = null
  }
  document.removeEventListener('mousemove', onDragMove)
  document.removeEventListener('mouseup', onDragEnd)
  document.removeEventListener('touchmove', onDragMoveTouch)
  document.removeEventListener('touchend', onDragEnd)
}

// Resize handlers
const startResize = (e: MouseEvent | TouchEvent) => {
  e.stopPropagation()
  isResizing.value = true
  emit('resize-start')

  const clientX = e instanceof MouseEvent ? e.clientX : e.touches[0].clientX
  const clientY = e instanceof MouseEvent ? e.clientY : e.touches[0].clientY

  resizeStartX.value = clientX
  resizeStartY.value = clientY
  resizeStartWidth.value = width.value
  resizeStartHeight.value = height.value

  if (e instanceof MouseEvent) {
    document.addEventListener('mousemove', onResizeMove)
    document.addEventListener('mouseup', onResizeEnd)
  } else {
    document.addEventListener('touchmove', onResizeMoveTouch, { passive: false })
    document.addEventListener('touchend', onResizeEnd)
  }
}

const onResizeMove = (e: MouseEvent) => {
  if (!isResizing.value) return

  lastResizeX = e.clientX
  lastResizeY = e.clientY

  if (resizeAnimationFrame) return

  resizeAnimationFrame = requestAnimationFrame(() => {
    const deltaX = lastResizeX - resizeStartX.value
    const deltaY = lastResizeY - resizeStartY.value

    width.value = Math.max(props.minWidth || 300, resizeStartWidth.value + deltaX)
    height.value = Math.max(props.minHeight || 200, resizeStartHeight.value + deltaY)
    resizeAnimationFrame = null
  })
}

const onResizeMoveTouch = (e: TouchEvent) => {
  if (!isResizing.value) return
  e.preventDefault()

  lastResizeX = e.touches[0].clientX
  lastResizeY = e.touches[0].clientY

  if (resizeAnimationFrame) return

  resizeAnimationFrame = requestAnimationFrame(() => {
    const deltaX = lastResizeX - resizeStartX.value
    const deltaY = lastResizeY - resizeStartY.value

    width.value = Math.max(props.minWidth || 300, resizeStartWidth.value + deltaX)
    height.value = Math.max(props.minHeight || 200, resizeStartHeight.value + deltaY)
    resizeAnimationFrame = null
  })
}

const onResizeEnd = () => {
  isResizing.value = false
  emit('resize-end', { width: width.value, height: height.value })
  if (resizeAnimationFrame) {
    cancelAnimationFrame(resizeAnimationFrame)
    resizeAnimationFrame = null
  }
  document.removeEventListener('mousemove', onResizeMove)
  document.removeEventListener('mouseup', onResizeEnd)
  document.removeEventListener('touchmove', onResizeMoveTouch)
  document.removeEventListener('touchend', onResizeEnd)
}

onUnmounted(() => {
  if (dragAnimationFrame) {
    cancelAnimationFrame(dragAnimationFrame)
  }
  if (resizeAnimationFrame) {
    cancelAnimationFrame(resizeAnimationFrame)
  }
  onDragEnd()
  onResizeEnd()
})
</script>

<template>
  <div v-if="isOpen" ref="panelRef" class="db-floating-panel db-glass-panel" :style="panelStyle">
    <div class="db-panel-header" @mousedown="startDrag" @touchstart="startDrag">
      <span class="db-graph-title">
        <i v-if="icon" :class="icon"></i>
        {{ title }}
        <span v-if="badge" class="db-badge-json">{{ badge }}</span>
      </span>
      <div class="db-panel-actions">
        <button
          v-if="showDownload"
          class="db-action-btn"
          @click.stop="emit('download')"
          @mousedown.stop
          @touchstart.stop
          title="Download"
        >
          <i class="fas fa-download"></i>
        </button>
        <button
          v-if="showImport"
          class="db-action-btn"
          @click.stop="emit('import')"
          @mousedown.stop
          @touchstart.stop
          title="Import"
        >
          <i class="fas fa-file-upload"></i>
        </button>
        <button class="db-close-btn" @click.stop="emit('close')" @mousedown.stop @touchstart.stop>
          <i class="fas fa-times"></i>
        </button>
      </div>
    </div>
    <div class="db-panel-content">
      <slot></slot>
    </div>
    <div
      class="db-resize-handle"
      @mousedown.stop="startResize"
      @touchstart.stop.prevent="startResize"
    >
      <i class="fas fa-chevron-right" style="transform: rotate(45deg)"></i>
    </div>
  </div>
</template>

<style scoped>
.db-floating-panel {
  position: fixed;
  pointer-events: auto;
  z-index: 300; /* Layer 4: Floating panels (code/data) - above sidebars, below toolbar */
  background: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-floating);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  /* Hardware acceleration for smooth dragging */
  will-change: transform;
}

.db-panel-header {
  height: 36px;
  background-color: var(--theme-bg-hover);
  border-bottom: 1px solid var(--theme-border);
  display: flex;
  align-items: center;
  padding: 0 10px;
  justify-content: space-between;
  user-select: none;
  cursor: move;
}

.db-graph-title {
  font-weight: 600;
  font-size: 12px;
  color: var(--theme-text-primary);
  display: flex;
  align-items: center;
  gap: 6px;
}

.db-badge-json {
  font-size: 0.7em;
  background-color: var(--theme-primary);
  color: white;
  padding: 2px 4px;
  border-radius: 3px;
  margin-left: 6px;
  font-weight: normal;
  vertical-align: middle;
}

.db-panel-actions {
  display: flex;
  align-items: center;
  gap: 4px;
}

.db-action-btn {
  background: transparent;
  border: none;
  color: var(--theme-text-secondary);
  cursor: pointer;
  font-size: 13px;
  padding: 4px;
  display: flex;
  align-items: center;
  transition: color 0.2s;
}

.db-action-btn:hover {
  color: var(--theme-text-primary);
}

.db-close-btn {
  background: transparent;
  border: none;
  color: var(--theme-text-secondary);
  cursor: pointer;
  font-size: 13px;
  padding: 4px;
  display: flex;
  align-items: center;
  transition: all 0.2s;
}

.db-close-btn:hover {
  background: var(--theme-bg-active);
  color: var(--theme-danger);
}

.db-panel-content {
  flex: 1;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background-color: var(--theme-bg-panel);
}

.db-panel-content :deep(.code-preview-panel),
.db-panel-content :deep(.data-input-panel),
.db-panel-content :deep(.json-editor-panel) {
  height: 100%;
  padding: 0;
}

.db-panel-content :deep(.header-section) {
  display: none;
}

.db-panel-content :deep(.header-controls) {
  display: none;
}

.db-panel-content :deep(.panel-title),
.db-panel-content :deep(.description) {
  display: none;
}

.db-resize-handle {
  position: absolute;
  bottom: 0;
  right: 0;
  width: 20px;
  height: 20px;
  cursor: nwse-resize;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--theme-text-muted);
  font-size: 10px;
  user-select: none;
  opacity: 0.5;
  transition: opacity 0.2s;
}

.db-resize-handle:hover {
  opacity: 1;
  color: var(--theme-text-primary);
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
