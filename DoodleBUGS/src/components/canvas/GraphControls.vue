<script setup lang="ts">
import { ref, watch, onMounted } from 'vue';
import type { Core } from 'cytoscape';
import type { GraphElement } from '../../types';

const props = defineProps<{
  cy: Core | null;
  elements: GraphElement[];
}>();

const emit = defineEmits<{
  (e: 'hide-controls'): void;
}>();

// --- Panzoom Logic ---
const currentZoom = ref(1);
const minZoom = 0.1;
const maxZoom = 2.0; // Match common Cytoscape zoom limits
const showContextMenu = ref(false);
const contextMenuPos = ref({ x: 0, y: 0 });

// --- Drag Logic ---
const controlsRef = ref<HTMLElement | null>(null);
const isDragging = ref(false);
const dragOffset = ref({ x: 0, y: 0 });
const position = ref({ right: '400px', bottom: '20px', top: 'auto', left: 'auto' });
const isHorizontal = ref(false);
const STORAGE_KEY = 'doodlebugs-zoom-controls-config';

const saveConfig = () => {
  const config = {
    position: position.value,
    isHorizontal: isHorizontal.value
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
};

const toggleOrientation = () => {
  isHorizontal.value = !isHorizontal.value;
  saveConfig();
};

const startDrag = (event: MouseEvent) => {
  if (!controlsRef.value) return;
  // Only allow dragging from the handle or background, not buttons
  if ((event.target as HTMLElement).closest('button') || (event.target as HTMLElement).closest('input')) return;

  isDragging.value = true;
  const rect = controlsRef.value.getBoundingClientRect();
  dragOffset.value = {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top
  };
  
  // Switch to fixed positioning based on current location to allow free movement
  position.value = {
    left: `${rect.left}px`,
    top: `${rect.top}px`,
    right: 'auto',
    bottom: 'auto'
  };

  window.addEventListener('mousemove', onDrag);
  window.addEventListener('mouseup', stopDrag);
};

const onDrag = (event: MouseEvent) => {
  if (!isDragging.value) return;
  
  const x = event.clientX - dragOffset.value.x;
  const y = event.clientY - dragOffset.value.y;
  
  // Boundary checks could be added here if needed
  
  position.value = {
    left: `${x}px`,
    top: `${y}px`,
    right: 'auto',
    bottom: 'auto'
  };
};

const stopDrag = () => {
  isDragging.value = false;
  window.removeEventListener('mousemove', onDrag);
  window.removeEventListener('mouseup', stopDrag);
  saveConfig();
};

const updateZoom = () => {
  if (props.cy) {
    const cyZoom = props.cy.zoom();
    currentZoom.value = Math.max(minZoom, Math.min(maxZoom, cyZoom));
  }
};

const zoomIn = () => {
  if (!props.cy) return;
  const currentLevel = Math.max(minZoom, Math.min(maxZoom, props.cy.zoom()));
  const newZoom = Math.min(currentLevel * 1.2, maxZoom);
  animateZoom(newZoom);
};

const zoomOut = () => {
  if (!props.cy) return;
  const currentLevel = Math.max(minZoom, Math.min(maxZoom, props.cy.zoom()));
  const newZoom = Math.max(currentLevel / 1.2, minZoom);
  animateZoom(newZoom);
};

const resetView = () => {
  if (!props.cy) return;
  props.cy.animate({
    fit: { 
      eles: props.cy.elements(),
      padding: 50 
    },
    duration: 300,
    easing: 'ease-in-out-cubic'
  });
};

const animateZoom = (level: number) => {
  if (!props.cy) return;
  props.cy.animate({
    zoom: {
      level: level,
      position: { x: props.cy.width() / 2, y: props.cy.height() / 2 }
    },
    duration: 200,
    easing: 'ease-out'
  });
};

const handleSliderChange = (event: Event) => {
  const target = event.target as HTMLInputElement;
  const val = parseFloat(target.value);
  const clampedVal = Math.max(minZoom, Math.min(maxZoom, val));
  if (props.cy) {
    props.cy.zoom({
      level: clampedVal,
      renderedPosition: { x: props.cy.width() / 2, y: props.cy.height() / 2 }
    });
    currentZoom.value = clampedVal;
  }
};

const handleContextMenu = (event: MouseEvent) => {
  event.preventDefault();
  event.stopPropagation();
  contextMenuPos.value = { x: event.clientX, y: event.clientY };
  showContextMenu.value = true;
  
  const closeMenu = () => {
    showContextMenu.value = false;
    window.removeEventListener('click', closeMenu);
  };
  
  setTimeout(() => {
    window.addEventListener('click', closeMenu, { once: true });
  }, 0);
};

const hideControls = () => {
  showContextMenu.value = false;
  emit('hide-controls');
};

// --- Watchers & Lifecycle ---

onMounted(() => {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved) {
    try {
      const config = JSON.parse(saved);
      if (config.position) position.value = config.position;
      if (typeof config.isHorizontal === 'boolean') isHorizontal.value = config.isHorizontal;
    } catch (e) {
      console.error('Failed to load zoom controls config', e);
    }
  }
});

watch(() => props.cy, (newCy) => {
  if (newCy) {
    newCy.on('zoom pan', () => {
      updateZoom();
    });
    // Clamp initial zoom to valid range
    const initialZoom = newCy.zoom();
    currentZoom.value = Math.max(minZoom, Math.min(maxZoom, initialZoom));
  }
}, { immediate: true });

</script>

<template>
  <div 
    ref="controlsRef"
    class="graph-controls" 
    :style="position"
    @mousedown="startDrag"
    @contextmenu="handleContextMenu"
  >
    <!-- Context Menu -->
    <div v-if="showContextMenu" class="context-menu" :style="{ left: `${contextMenuPos.x}px`, top: `${contextMenuPos.y}px` }">
      <div class="context-menu-item" @click="hideControls">
        <i class="fas fa-eye-slash"></i> Hide Zoom Controls
      </div>
    </div>

    <!-- Panzoom -->
    <div class="panzoom-controls" :class="{ 'is-horizontal': isHorizontal }">
      <div class="drag-handle" title="Drag to move">
        <i class="fas fa-grip-lines" :class="{ 'fa-rotate-90': isHorizontal }"></i>
        <div class="orientation-toggle" @click.stop="toggleOrientation" title="Toggle Orientation">
          <i class="fas fa-redo"></i>
        </div>
      </div>
      
      <button class="control-btn" @click="zoomIn" title="Zoom In">
        <i class="fas fa-plus"></i>
      </button>
      
      <div class="slider-container">
        <input 
          type="range" 
          :min="minZoom" 
          :max="maxZoom" 
          step="0.01" 
          :value="currentZoom"
          @input="handleSliderChange"
          class="zoom-slider"
        />
      </div>

      <button class="control-btn" @click="zoomOut" title="Zoom Out">
        <i class="fas fa-minus"></i>
      </button>
      
      <button class="control-btn" @click="resetView" title="Fit View">
        <i class="fas fa-compress-arrows-alt"></i>
      </button>
    </div>
  </div>
</template>

<style scoped>
.graph-controls {
  position: fixed; /* Changed to fixed to allow dragging relative to viewport */
  z-index: 1000;
  user-select: none;
}

/* Panzoom */
.panzoom-controls {
  background: rgba(255, 255, 255, 0.95);
  border-radius: 20px; /* More rounded for a modern look */
  box-shadow: 0 4px 15px rgba(0,0,0,0.15);
  padding: 8px 6px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  align-items: center;
  backdrop-filter: blur(5px);
  border: 1px solid rgba(0,0,0,0.05);
  transition: opacity 0.2s;
}

.panzoom-controls.is-horizontal {
  flex-direction: row;
  padding: 6px 8px;
}

.drag-handle {
  cursor: grab;
  color: #aaa;
  font-size: 10px;
  padding: 2px;
  width: 100%;
  text-align: center;
  border-bottom: 1px solid #eee;
  margin-bottom: 2px;
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
}

.panzoom-controls.is-horizontal .drag-handle {
  width: auto;
  height: 100%;
  border-bottom: none;
  border-right: 1px solid #eee;
  margin-bottom: 0;
  margin-right: 2px;
  padding: 0 4px;
  flex-direction: row;
}

.orientation-toggle {
  cursor: pointer;
  font-size: 8px;
  color: #888;
  opacity: 0;
  transition: opacity 0.2s;
  position: absolute;
  top: -12px;
  background: white;
  border-radius: 50%;
  width: 14px;
  height: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}

.panzoom-controls.is-horizontal .orientation-toggle {
  top: auto;
  left: -12px;
}

.panzoom-controls:hover .orientation-toggle {
  opacity: 1;
}

.orientation-toggle:hover {
  color: #333;
  transform: scale(1.1);
}

.drag-handle:active {
  cursor: grabbing;
}

.control-btn {
  width: 28px;
  height: 28px;
  border: none;
  background: transparent;
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #555;
  transition: all 0.2s;
  font-size: 12px;
}

.control-btn:hover {
  background: #f0f0f0;
  color: #222;
  transform: scale(1.1);
}

.control-btn:active {
  transform: scale(0.95);
}

.slider-container {
  height: 60px; /* Smaller slider */
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 5px 0;
}

.panzoom-controls.is-horizontal .slider-container {
  height: auto;
  width: 60px;
  padding: 0 5px;
}

.zoom-slider {
  writing-mode: vertical-lr;
  direction: rtl;
  width: 4px; /* Thinner slider */
  height: 100%;
  cursor: pointer;
  appearance: none;
  background: #eee;
  border-radius: 2px;
}

.panzoom-controls.is-horizontal .zoom-slider {
  writing-mode: horizontal-tb;
  direction: ltr;
  width: 100%;
  height: 4px;
}

.zoom-slider::-webkit-slider-thumb {
  appearance: none;
  width: 12px;
  height: 12px;
  background: #666;
  border-radius: 50%;
  cursor: pointer;
}

.zoom-slider::-moz-range-thumb {
  width: 12px;
  height: 12px;
  background: #666;
  border-radius: 50%;
  cursor: pointer;
  border: none;
}

/* Context Menu */
.context-menu {
  position: fixed;
  background: white;
  border: 1px solid #ddd;
  border-radius: 4px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
  z-index: 10000;
  min-width: 180px;
}

.context-menu-item {
  padding: 10px 15px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 8px;
  transition: background 0.2s;
}

.context-menu-item:hover {
  background: #f0f0f0;
}

.context-menu-item i {
  width: 16px;
  text-align: center;
}
</style>
