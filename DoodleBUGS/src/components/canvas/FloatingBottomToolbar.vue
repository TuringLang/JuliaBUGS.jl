<script setup lang="ts">
import { computed, ref, onUnmounted, watch } from 'vue';
import type { NodeType } from '../../types';
import { nodeDefinitions } from '../../config/nodeDefinitions';
import DropdownMenu from '../common/DropdownMenu.vue';

const props = defineProps<{
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

// --- Unified Add Tool Logic ---
const nodeIcons: Record<string, string> = {
    stochastic: 'fas fa-random',
    deterministic: 'fas fa-calculator',
    constant: 'fas fa-square',
    observed: 'fas fa-eye',
    plate: 'fas fa-th-large'
};

// Colors used for Active State Background and Inactive State Icon/Text
const nodeColors: Record<string, string> = {
    stochastic: '#ef4444', // Red
    deterministic: '#10b981', // Green
    constant: '#6b7280', // Gray
    observed: '#3b82f6', // Blue
    plate: '#8b5cf6', // Purple
    edge: '#f59e0b'   // Amber
};

const lastAddTool = ref<NodeType | 'edge'>(props.currentNodeType);

// Sync local state with props when mode changes externally
watch(() => props.currentMode, (newMode) => {
    if (newMode === 'add-edge') {
        lastAddTool.value = 'edge';
    } else if (newMode === 'add-node') {
        lastAddTool.value = props.currentNodeType;
    }
});

watch(() => props.currentNodeType, (newType) => {
    if (props.currentMode === 'add-node') {
        lastAddTool.value = newType;
    }
});

const currentAddToolIcon = computed(() => {
    if (lastAddTool.value === 'edge') return 'fas fa-bezier-curve';
    return nodeIcons[lastAddTool.value] || 'fas fa-circle';
});

const currentAddToolColor = computed(() => {
    if (lastAddTool.value === 'edge') return nodeColors.edge;
    return nodeColors[lastAddTool.value] || 'var(--theme-primary)';
});

const currentAddToolLabel = computed(() => {
    if (lastAddTool.value === 'edge') return 'Edge';
    const node = availableNodeTypes.value.find(n => n.value === lastAddTool.value);
    return node ? node.label : 'Node';
});

const isAddModeActive = computed(() => {
    if (lastAddTool.value === 'edge') return props.currentMode === 'add-edge';
    return props.currentMode === 'add-node' && props.currentNodeType === lastAddTool.value;
});

const activateAddTool = () => {
    if (lastAddTool.value === 'edge') {
        emit('update:currentMode', 'add-edge');
    } else {
        emit('update:currentNodeType', lastAddTool.value);
        emit('update:currentMode', 'add-node');
    }
};

const selectAddTool = (tool: NodeType | 'edge') => {
    lastAddTool.value = tool;
    activateAddTool();
};

// Style for the main add button
const addButtonStyle = computed(() => {
    if (isAddModeActive.value) {
        const color = currentAddToolColor.value;
        return {
            backgroundColor: color,
            borderColor: color,
            color: '#ffffff' // Always white text on colored background
        };
    }
    return {}; // Default styles (transparent bg, theme text)
});

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
        type="button"
      >
        <i class="fas fa-mouse-pointer"></i>
      </button>

      <div class="divider"></div>

      <!-- Unified Add Tool (Single Button with Dropdown) -->
      <DropdownMenu class="dock-dropdown add-tool-dropdown">
          <template #trigger>
              <button 
                class="add-tool-btn"
                :class="{ active: isAddModeActive }"
                :style="addButtonStyle"
                title="Add Node or Edge"
                type="button"
              >
                  <i 
                    :class="currentAddToolIcon" 
                    class="tool-icon"
                    :style="{ color: isAddModeActive ? 'white' : currentAddToolColor }"
                  ></i>
                  <span 
                    class="tool-label"
                    :style="{ color: isAddModeActive ? 'white' : 'var(--theme-text-primary)' }"
                  >
                    {{ currentAddToolLabel }}
                  </span>
                  <i 
                    class="fas fa-chevron-down arrow-icon"
                    :style="{ color: isAddModeActive ? 'white' : 'var(--theme-text-muted)' }"
                  ></i>
              </button>
          </template>
          <template #content>
               <div class="dropdown-section-title">Nodes</div>
               <a href="#" v-for="type in availableNodeTypes" :key="type.value" @click.prevent="selectAddTool(type.value)">
                   <i :class="nodeIcons[type.value]" :style="{ color: nodeColors[type.value] }" class="menu-icon"></i> {{ type.label }}
               </a>
               <div class="dropdown-divider"></div>
               <div class="dropdown-section-title">Connections</div>
               <a href="#" @click.prevent="selectAddTool('edge')">
                   <i class="fas fa-bezier-curve menu-icon" :style="{ color: nodeColors.edge }"></i> Edge
               </a>
          </template>
      </DropdownMenu>

      <div class="divider"></div>

      <!-- Undo/Redo -->
      <button class="dock-btn" @click="$emit('undo')" title="Undo (Ctrl+Z)" type="button">
        <i class="fas fa-undo"></i>
      </button>
      <button class="dock-btn" @click="$emit('redo')" title="Redo (Ctrl+Y)" type="button">
        <i class="fas fa-redo"></i>
      </button>

      <template v-if="showWorkspaceControls">
        <div class="divider"></div>
        
        <!-- Navigation -->
        <button class="dock-btn" @click="$emit('zoom-in')" title="Zoom In" type="button">
          <i class="fas fa-plus"></i>
        </button>
        <button class="dock-btn" @click="$emit('zoom-out')" title="Zoom Out" type="button">
          <i class="fas fa-minus"></i>
        </button>
        <button class="dock-btn" @click="$emit('fit')" title="Fit to View" type="button">
          <i class="fas fa-compress-arrows-alt"></i>
        </button>
        
        <!-- Auto Arrange Cards Menu -->
        <DropdownMenu class="dock-dropdown">
            <template #trigger>
                <button class="dock-btn" title="Arrange Canvas Cards" type="button">
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

/* Unified Add Tool Button */
.add-tool-btn {
    display: flex;
    align-items: center;
    height: 32px;
    border: none;
    background: transparent;
    border-radius: 16px; /* Pill shape */
    padding: 0 10px;
    cursor: pointer;
    transition: all 0.2s;
    border: 1px solid transparent;
}

.add-tool-btn:hover {
    background: var(--theme-bg-hover);
    border-color: var(--theme-border);
}

/* When active, styles are applied via :style binding (colored background) */
.add-tool-btn.active {
    border-color: transparent;
}

.tool-icon {
    font-size: 14px;
    margin-right: 6px;
    pointer-events: none;
}

.tool-label {
    font-size: 12px;
    font-weight: 600;
    margin-right: 6px;
    white-space: nowrap;
    pointer-events: none;
}

.arrow-icon {
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
.dock-dropdown {
    display: flex;
    align-items: center;
}

.dock-dropdown :deep(.p-popover) {
    margin-bottom: 8px;
}
</style>
