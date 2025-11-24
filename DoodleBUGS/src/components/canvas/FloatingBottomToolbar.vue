<script setup lang="ts">
import { computed, ref, onUnmounted } from 'vue';
import type { NodeType } from '../../types';
import { nodeDefinitions } from '../../config/nodeDefinitions';
import DropdownMenu from '../common/DropdownMenu.vue';

defineProps<{
  currentMode: string;
  currentNodeType: NodeType;
  showWorkspaceControls?: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'undo'): void;
  (e: 'redo'): void;
  // Workspace controls
  (e: 'zoom-in'): void;
  (e: 'zoom-out'): void;
  (e: 'fit'): void;
  (e: 'arrange', type: 'grid' | 'horizontal' | 'vertical'): void;
  // Graph Layout
  (e: 'layout-graph', layout: string): void;
}>();

const availableNodeTypes = computed(() => {
  return nodeDefinitions.map(def => ({
    label: def.label,
    value: def.nodeType,
    icon: def.icon
  }));
});

const setMode = (mode: string) => {
  emit('update:currentMode', mode);
};

const handleNodeChange = (event: Event) => {
    const target = event.target as HTMLSelectElement;
    emit('update:currentNodeType', target.value as NodeType);
    emit('update:currentMode', 'add-node');
};

// --- Dragging Logic ---
const toolbarRef = ref<HTMLElement | null>(null);
const isDragging = ref(false);
const position = ref({ bottom: '24px', left: '50%', transform: 'translateX(-50%)' });
const dragOffset = ref({ x: 0, y: 0 });

const startDrag = (event: MouseEvent) => {
    // Only allow drag if clicking on the container, not buttons
    if ((event.target as HTMLElement).closest('button') || (event.target as HTMLElement).closest('select') || (event.target as HTMLElement).closest('.p-popover') || (event.target as HTMLElement).closest('input')) return;
    
    if (!toolbarRef.value) return;
    
    isDragging.value = true;
    const rect = toolbarRef.value.getBoundingClientRect();
    
    // Switch to fixed pixel positioning to allow free drag
    position.value = {
        left: `${rect.left}px`,
        bottom: 'auto', // Unset bottom to allow top positioning
        transform: 'none'
    };
    
    // Set top based on current rect to prevent jumping
    (toolbarRef.value.style as CSSStyleDeclaration).top = `${rect.top}px`;

    dragOffset.value = {
        x: event.clientX - rect.left,
        y: event.clientY - rect.top
    };

    window.addEventListener('mousemove', onDrag);
    window.addEventListener('mouseup', stopDrag);
};

const onDrag = (event: MouseEvent) => {
    if (!isDragging.value || !toolbarRef.value) return;
    
    const x = event.clientX - dragOffset.value.x;
    const y = event.clientY - dragOffset.value.y;
    
    position.value.left = `${x}px`;
    (toolbarRef.value.style as CSSStyleDeclaration).top = `${y}px`;
};

const stopDrag = () => {
    isDragging.value = false;
    window.removeEventListener('mousemove', onDrag);
    window.removeEventListener('mouseup', stopDrag);
};

const startDragTouch = (event: TouchEvent) => {
    // prevent dragging if touching buttons
    if ((event.target as HTMLElement).closest('button') || (event.target as HTMLElement).closest('select') || (event.target as HTMLElement).closest('.p-popover') || (event.target as HTMLElement).closest('input')) return;
    
    if (!toolbarRef.value) return;
    
    isDragging.value = true;
    const rect = toolbarRef.value.getBoundingClientRect();
    const touch = event.touches[0];
    
    // Switch to fixed pixel positioning to allow free drag
    position.value = {
        left: `${rect.left}px`,
        bottom: 'auto', // Unset bottom to allow top positioning
        transform: 'none'
    };
    
    // Set top based on current rect to prevent jumping
    (toolbarRef.value.style as CSSStyleDeclaration).top = `${rect.top}px`;

    dragOffset.value = {
        x: touch.clientX - rect.left,
        y: touch.clientY - rect.top
    };

    window.addEventListener('touchmove', onDragTouch, { passive: false });
    window.addEventListener('touchend', stopDragTouch);
};

const onDragTouch = (event: TouchEvent) => {
    if (!isDragging.value || !toolbarRef.value) return;
    event.preventDefault(); // Prevent scroll
    const touch = event.touches[0];
    
    const x = touch.clientX - dragOffset.value.x;
    const y = touch.clientY - dragOffset.value.y;
    
    position.value.left = `${x}px`;
    (toolbarRef.value.style as CSSStyleDeclaration).top = `${y}px`;
};

const stopDragTouch = () => {
    isDragging.value = false;
    window.removeEventListener('touchmove', onDragTouch);
    window.removeEventListener('touchend', stopDragTouch);
};

onUnmounted(() => {
    window.removeEventListener('mousemove', onDrag);
    window.removeEventListener('mouseup', stopDrag);
    window.removeEventListener('touchmove', onDragTouch);
    window.removeEventListener('touchend', stopDragTouch);
});
</script>

<template>
  <div class="toolbar-container" ref="toolbarRef" :style="position" @mousedown="startDrag" @touchstart="startDragTouch">
    <div class="floating-dock glass-panel">
      <!-- Drag Handle Indicator -->
      <div class="drag-handle" title="Drag Toolbar">
          <i class="fas fa-grip-vertical"></i>
      </div>

      <!-- Selection Tool -->
      <button 
        class="dock-btn" 
        :class="{ active: currentMode === 'select' }"
        @click="setMode('select')"
        title="Select Tool (V)"
      >
        <i class="fas fa-mouse-pointer"></i>
      </button>

      <div class="divider"></div>

      <!-- Add Node Inline Selector -->
      <div class="inline-node-selector" :class="{ active: currentMode === 'add-node' }">
          <button class="icon-only-btn" @click="setMode('add-node')">
              <i class="fas fa-plus-circle"></i>
          </button>
          <select class="native-select" :value="currentNodeType" @change="handleNodeChange">
              <option v-for="opt in availableNodeTypes" :key="opt.value" :value="opt.value">
                  {{ opt.label }}
              </option>
          </select>
          <i class="fas fa-chevron-down select-arrow"></i>
      </div>

      <!-- Add Edge -->
      <button 
        class="dock-btn"
        :class="{ active: currentMode === 'add-edge' }"
        @click="setMode('add-edge')"
        title="Add Connection (C)"
      >
        <i class="fas fa-bezier-curve"></i>
      </button>

      <div class="divider"></div>

      <!-- Undo/Redo -->
      <button class="dock-btn" @click="$emit('undo')" title="Undo (Ctrl+Z)">
        <i class="fas fa-undo"></i>
      </button>
      <button class="dock-btn" @click="$emit('redo')" title="Redo (Ctrl+Y)">
        <i class="fas fa-redo"></i>
      </button>

      <template v-if="showWorkspaceControls">
        <div class="divider"></div>
        
        <!-- Navigation -->
        <button class="dock-btn" @click="$emit('zoom-in')" title="Zoom In">
          <i class="fas fa-plus"></i>
        </button>
        <button class="dock-btn" @click="$emit('zoom-out')" title="Zoom Out">
          <i class="fas fa-minus"></i>
        </button>
        <button class="dock-btn" @click="$emit('fit')" title="Fit to View">
          <i class="fas fa-compress-arrows-alt"></i>
        </button>
        
        <!-- Auto Arrange Cards Menu -->
        <DropdownMenu class="dock-dropdown">
            <template #trigger>
                <button class="dock-btn" title="Arrange Canvas Cards">
                    <i class="fas fa-th"></i>
                </button>
            </template>
            <template #content>
                <div class="dropdown-section-title">Arrange Cards</div>
                <a href="#" @click.prevent="$emit('arrange', 'grid')"><i class="fas fa-th-large"></i> Grid</a>
                <a href="#" @click.prevent="$emit('arrange', 'horizontal')"><i class="fas fa-ellipsis-h"></i> Horizontal</a>
                <a href="#" @click.prevent="$emit('arrange', 'vertical')"><i class="fas fa-ellipsis-v"></i> Vertical</a>
            </template>
        </DropdownMenu>
      </template>

      <div class="divider"></div>

      <!-- Graph Layout Menu -->
      <DropdownMenu class="dock-dropdown">
          <template #trigger>
              <button class="dock-btn" title="Graph Layout">
                  <i class="fas fa-sitemap"></i>
              </button>
          </template>
          <template #content>
              <div class="dropdown-section-title">Graph Layout</div>
              <a href="#" @click.prevent="$emit('layout-graph', 'dagre')">Dagre (Hierarchical)</a>
              <a href="#" @click.prevent="$emit('layout-graph', 'fcose')">fCoSE (Force)</a>
              <a href="#" @click.prevent="$emit('layout-graph', 'cola')">Cola (Physics)</a>
              <a href="#" @click.prevent="$emit('layout-graph', 'klay')">KLay (Layered)</a>
              <div class="dropdown-divider"></div>
              <a href="#" @click.prevent="$emit('layout-graph', 'preset')">Reset to Preset</a>
          </template>
      </DropdownMenu>
    </div>
  </div>
</template>

<style scoped>
.toolbar-container {
  position: fixed;
  z-index: 100;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  cursor: grab;
  touch-action: none; /* Prevent default touch actions */
}

.toolbar-container:active {
    cursor: grabbing;
}

.floating-dock {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 8px;
  border-radius: var(--radius-pill);
  transition: box-shadow 0.2s ease;
}

.drag-handle {
    color: var(--theme-text-muted);
    cursor: grab;
    padding: 0 6px;
    display: flex;
    align-items: center;
    font-size: 12px;
}

.drag-handle:active {
    cursor: grabbing;
}

.dock-btn {
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

.dock-btn:hover {
  background: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.dock-btn.active {
  background: var(--theme-primary);
  color: white;
}

.divider {
  width: 1px;
  height: 16px;
  background: var(--theme-border);
  margin: 0 4px;
}

/* Inline Node Selector */
.inline-node-selector {
    display: flex;
    align-items: center;
    position: relative;
    background: transparent;
    border-radius: 16px;
    padding-right: 8px;
    transition: background 0.2s;
}

.inline-node-selector:hover {
    background: var(--theme-bg-hover);
}

.inline-node-selector.active {
    background: var(--theme-bg-active);
}

.inline-node-selector.active .icon-only-btn {
    color: var(--theme-primary);
}

.icon-only-btn {
    width: 32px;
    height: 32px;
    border: none;
    background: transparent;
    color: var(--theme-text-secondary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
}

.native-select {
    appearance: none;
    background: transparent;
    border: none;
    font-size: 12px;
    color: var(--theme-text-primary);
    padding: 4px 18px 4px 4px;
    cursor: pointer;
    font-family: inherit;
    font-weight: 500;
    outline: none;
    width: auto; /* Allow auto width */
    min-width: 60px;
    max-width: 120px;
    text-overflow: ellipsis;
}

.native-select option {
    background-color: var(--theme-bg-panel);
    color: var(--theme-text-primary);
}

.select-arrow {
    position: absolute;
    right: 8px;
    font-size: 10px;
    color: var(--theme-text-muted);
    pointer-events: none;
}

/* Dropdown adjustments */
.dock-dropdown {
    display: flex;
    align-items: center;
}

.dock-dropdown :deep(.p-popover) {
    margin-bottom: 8px;
}
</style>
