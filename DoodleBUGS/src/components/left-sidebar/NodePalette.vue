<script setup lang="ts">
import { ref } from 'vue';
import type { PaletteItemType, NodeType } from '../../types';
import { nodeDefinitions, connectionPaletteItems, defaultEdgeStyles } from '../../config/nodeDefinitions';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import BaseButton from '../ui/BaseButton.vue';
import { useUiStore } from '../../stores/uiStore';

const uiStore = useUiStore();

const emit = defineEmits<{
  (e: 'select-palette-item', itemType: PaletteItemType): void;
}>();

const onDragStart = (event: DragEvent, itemType: PaletteItemType) => {
  if (event.dataTransfer) {
    event.dataTransfer.setData('text/plain', itemType);
    event.dataTransfer.effectAllowed = 'copy';
  }
};

const onClickPaletteItem = (itemType: PaletteItemType) => {
  emit('select-palette-item', itemType);
};

// Styling Logic
const showStyleModal = ref(false);
const editingCategory = ref<'node' | 'edge' | null>(null);
const editingNodeType = ref<NodeType | null>(null);
const editingEdgeType = ref<'stochastic' | 'deterministic'>('stochastic');

const tempNodeStyle = ref({
    backgroundColor: '',
    borderColor: '',
    borderWidth: 2,
    borderStyle: 'solid',
    backgroundOpacity: 1,
    shape: '',
    width: 60,
    height: 60
});

const tempEdgeStyle = ref({
    color: '',
    width: 3,
    lineStyle: 'solid'
});

const shapeOptions = [
    { label: 'Ellipse', value: 'ellipse' },
    { label: 'Rectangle', value: 'rectangle' },
    { label: 'Round Rectangle', value: 'round-rectangle' },
    { label: 'Triangle', value: 'triangle' },
    { label: 'Diamond', value: 'diamond' },
    { label: 'Pentagon', value: 'pentagon' },
    { label: 'Hexagon', value: 'hexagon' },
    { label: 'Star', value: 'star' }
];

const borderStyleOptions = [
    { label: 'Solid', value: 'solid' },
    { label: 'Dotted', value: 'dotted' },
    { label: 'Dashed', value: 'dashed' },
    { label: 'Double', value: 'double' }
];

const edgeStyleOptions = [
    { label: 'Solid', value: 'solid' },
    { label: 'Dashed', value: 'dashed' },
    { label: 'Dotted', value: 'dotted' }
];

const openNodeStyleSettings = (event: MouseEvent, nodeType: NodeType) => {
    event.stopPropagation();
    editingCategory.value = 'node';
    editingNodeType.value = nodeType;
    const currentStyle = uiStore.nodeStyles[nodeType];
    tempNodeStyle.value = { ...currentStyle };
    showStyleModal.value = true;
};

const openEdgeStyleSettings = (event: MouseEvent) => {
    event.stopPropagation();
    editingCategory.value = 'edge';
    editingEdgeType.value = 'stochastic'; // Default
    loadEdgeStyle();
    showStyleModal.value = true;
};

const loadEdgeStyle = () => {
    const currentStyle = uiStore.edgeStyles[editingEdgeType.value];
    tempEdgeStyle.value = { ...currentStyle };
};

const switchEdgeType = (type: 'stochastic' | 'deterministic') => {
    // Save current temp to store before switching (optional, or just switch view)
    // Let's save to store immediately to allow switching back and forth without losing unsaved changes?
    // Actually, standard behavior is "Save" commits everything. But complex with tabs.
    // Simple approach: Commit current temp to a local buffer or just save to store?
    // Let's just load the other type. If user didn't save, changes lost?
    // Better: Auto-save to store is aggressive. Let's keeping it simple:
    // Switching tabs loads from store. If you want to save "Stochastic", click Save first.
    // Or, we can just update the store on "Save" button only for the CURRENTLY visible tab.
    // Let's accept that limitation for now or implementing local buffer for both.
    // For simplicity, I will just load from store.
    editingEdgeType.value = type;
    loadEdgeStyle();
};

const saveStyleSettings = () => {
    if (editingCategory.value === 'node' && editingNodeType.value) {
        uiStore.nodeStyles[editingNodeType.value] = { ...tempNodeStyle.value };
    } else if (editingCategory.value === 'edge') {
        uiStore.edgeStyles[editingEdgeType.value] = { ...tempEdgeStyle.value };
    }
    showStyleModal.value = false;
};

const resetStyleSettings = () => {
    if (editingCategory.value === 'node' && editingNodeType.value) {
        const def = nodeDefinitions.find(d => d.nodeType === editingNodeType.value);
        if (def) {
            tempNodeStyle.value = { ...def.defaultStyle };
        }
    } else if (editingCategory.value === 'edge') {
        tempEdgeStyle.value = { ...defaultEdgeStyles[editingEdgeType.value] };
    }
};

</script>

<template>
  <div class="node-palette">
    <div class="palette-section">
      <h5 class="section-title">Nodes</h5>
      <div class="palette-grid">
        <div
          v-for="node in nodeDefinitions"
          :key="node.nodeType"
          class="palette-card"
          :class="node.styleClass"
          draggable="true"
          @dragstart="onDragStart($event, node.nodeType)"
          @click="onClickPaletteItem(node.nodeType)"
          :title="node.description"
        >
          <button class="settings-btn" @click="openNodeStyleSettings($event, node.nodeType)" title="Customize Appearance">
              <i class="fas fa-cog"></i>
          </button>
          <div class="card-icon" :class="`icon-${node.nodeType}`">{{ node.icon }}</div>
          <span class="card-label">{{ node.label }}</span>
        </div>
      </div>
    </div>

    <div class="palette-section">
      <h5 class="section-title">Connections</h5>
      <div class="palette-grid">
        <div
          v-for="connection in connectionPaletteItems"
          :key="connection.type"
          class="palette-card"
          :class="connection.styleClass"
          draggable="false"
          @click="onClickPaletteItem(connection.type)"
          :title="connection.description"
        >
          <button class="settings-btn" @click="openEdgeStyleSettings($event)" title="Customize Appearance">
              <i class="fas fa-cog"></i>
          </button>
          <div class="card-icon connection-icon"></div>
          <span class="card-label">{{ connection.label }}</span>
        </div>
      </div>
    </div>

    <BaseModal :is-open="showStyleModal" @close="showStyleModal = false">
        <template #header>
            <h3 v-if="editingCategory === 'node'">Customize {{ editingNodeType ? nodeDefinitions.find(n => n.nodeType === editingNodeType)?.label : '' }} Style</h3>
            <h3 v-else>Customize Edge Style</h3>
        </template>
        <template #body>
            <!-- Node Styling Form -->
            <div class="style-form" v-if="editingCategory === 'node' && editingNodeType">
                <div class="form-group">
                    <label>Shape</label>
                    <BaseSelect :model-value="tempNodeStyle.shape" :options="shapeOptions" @update:model-value="tempNodeStyle.shape = $event" />
                </div>
                <div class="grid-2">
                    <div class="form-group">
                        <label>Fill Color</label>
                        <div class="color-wrapper">
                            <input type="color" v-model="tempNodeStyle.backgroundColor">
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Border Color</label>
                        <div class="color-wrapper">
                            <input type="color" v-model="tempNodeStyle.borderColor">
                        </div>
                    </div>
                </div>
                <div class="grid-2">
                    <div class="form-group">
                        <label>Border Width (px)</label>
                        <BaseInput type="number" v-model.number="tempNodeStyle.borderWidth" min="0" />
                    </div>
                    <div class="form-group">
                        <label>Border Style</label>
                        <BaseSelect :model-value="tempNodeStyle.borderStyle" :options="borderStyleOptions" @update:model-value="tempNodeStyle.borderStyle = $event" />
                    </div>
                </div>
                <div class="form-group">
                    <label>Opacity ({{ tempNodeStyle.backgroundOpacity }})</label>
                    <input type="range" min="0" max="1" step="0.1" v-model.number="tempNodeStyle.backgroundOpacity" class="w-full" />
                </div>
                <div class="grid-2" v-if="editingNodeType !== 'plate'">
                    <div class="form-group">
                        <label>Width (px)</label>
                        <BaseInput type="number" v-model.number="tempNodeStyle.width" />
                    </div>
                    <div class="form-group">
                        <label>Height (px)</label>
                        <BaseInput type="number" v-model.number="tempNodeStyle.height" />
                    </div>
                </div>
            </div>

            <!-- Edge Styling Form -->
            <div class="style-form" v-else-if="editingCategory === 'edge'">
                <div class="edge-type-switcher">
                    <BaseButton size="small" :type="editingEdgeType === 'stochastic' ? 'primary' : 'secondary'" @click="switchEdgeType('stochastic')">Stochastic</BaseButton>
                    <BaseButton size="small" :type="editingEdgeType === 'deterministic' ? 'primary' : 'secondary'" @click="switchEdgeType('deterministic')">Deterministic</BaseButton>
                </div>
                <div class="grid-2">
                    <div class="form-group">
                        <label>Line Color</label>
                        <div class="color-wrapper">
                            <input type="color" v-model="tempEdgeStyle.color">
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Width (px)</label>
                        <BaseInput type="number" v-model.number="tempEdgeStyle.width" min="1" />
                    </div>
                </div>
                <div class="form-group">
                    <label>Line Style</label>
                    <BaseSelect :model-value="tempEdgeStyle.lineStyle" :options="edgeStyleOptions" @update:model-value="tempEdgeStyle.lineStyle = $event" />
                </div>
                <div class="info-box">
                    <i class="fas fa-info-circle"></i>
                    <small>Note: Stochastic edges connect to stochastic/observed nodes. Deterministic edges connect to deterministic nodes.</small>
                </div>
            </div>
        </template>
        <template #footer>
            <div class="modal-footer">
                <BaseButton type="secondary" @click="resetStyleSettings">Reset to Default</BaseButton>
                <div class="flex gap-2">
                    <BaseButton type="secondary" @click="showStyleModal = false">Cancel</BaseButton>
                    <BaseButton type="primary" @click="saveStyleSettings">Save</BaseButton>
                </div>
            </div>
        </template>
    </BaseModal>
  </div>
</template>

<style scoped>
.node-palette {
  padding: 10px;
  background-color: var(--color-background-soft);
  height: 100%;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.palette-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.section-title {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--color-heading);
  padding-bottom: 6px;
  border-bottom: 1px solid var(--color-border-light);
  margin: 0;
}

.palette-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
}

.palette-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 10px 6px;
  border-radius: 6px;
  border: 1px solid var(--color-border);
  background-color: var(--color-background-soft);
  cursor: grab;
  text-align: center;
  transition: all 0.2s ease-in-out;
  user-select: none;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
  position: relative;
}

.palette-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
  border-color: var(--color-primary);
}

.palette-card:active {
  cursor: grabbing;
  transform: translateY(-1px);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

:global(html.dark-mode) .palette-card {
  background-color: var(--p-surface-800);
  border-color: var(--p-surface-700);
  color: var(--p-text-color);
}

:global(html.dark-mode) .palette-card:hover {
  border-color: var(--color-primary);
  background-color: var(--p-surface-700);
}

.card-label {
  font-size: 0.75em;
  font-weight: 500;
  color: var(--color-text);
  margin-top: 6px;
}

.card-icon {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.2em;
  font-weight: bold;
  border-radius: 50%;
  color: #fff;
}

.icon-stochastic { background-color: #dc3545; }
.icon-deterministic { background-color: #28a745; border-radius: 6px; font-size: 1em; }
.icon-constant { background-color: #6c757d; border-radius: 3px; }
.icon-observed {
  background-color: var(--color-background-soft);
  border: 2px dashed #007bff;
  color: #007bff;
}
.icon-plate {
  background-color: var(--color-background-soft);
  border: 2px dashed var(--color-text);
  color: var(--color-text);
  border-radius: 6px;
  font-size: 1em;
}

.connection-icon {
  width: 80%;
  height: 16px;
  margin: 0 auto;
  background-color: transparent !important;
  position: relative;
  border-radius: 0;
}

.connection-icon::before {
  content: '';
  position: absolute;
  left: 10%;
  right: 10%;
  top: 50%;
  height: 2px;
  transform: translateY(-50%);
  background-color: #6c757d;
}

.connection-icon::after {
  content: '';
  position: absolute;
  right: 10%;
  top: 50%;
  transform: translateY(-50%);
  width: 0;
  height: 0;
  border-style: solid;
  border-width: 5px 0 5px 8px;
  border-color: transparent transparent transparent #6c757d;
}

.settings-btn {
    position: absolute;
    top: 4px;
    right: 4px;
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    opacity: 0;
    cursor: pointer;
    padding: 4px;
    border-radius: 4px;
    transition: opacity 0.2s, background-color 0.2s;
    z-index: 10;
}

.palette-card:hover .settings-btn {
    opacity: 1;
}

.settings-btn:hover {
    background-color: rgba(0,0,0,0.1);
    color: var(--color-text);
}

.style-form {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.form-group {
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.form-group label {
    font-size: 0.85em;
    font-weight: 600;
}

.grid-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
}

.color-wrapper {
    height: 32px;
    border: 1px solid var(--color-border);
    border-radius: 4px;
    padding: 2px;
}

.color-wrapper input {
    width: 100%;
    height: 100%;
    border: none;
    padding: 0;
    cursor: pointer;
    background: none;
}

.edge-type-switcher {
    display: flex;
    gap: 8px;
    margin-bottom: 8px;
}

.info-box {
    background-color: var(--color-background-mute);
    padding: 8px;
    border-radius: 4px;
    font-size: 0.8em;
    color: var(--color-text-secondary);
    display: flex;
    gap: 6px;
    align-items: flex-start;
}

.modal-footer {
    display: flex;
    justify-content: space-between;
    width: 100%;
}
</style>
