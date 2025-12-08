<script setup lang="ts">
import { ref, onMounted } from 'vue'
import type { NodeType } from '../../types'
import { nodeDefinitions, defaultEdgeStyles } from '../../config/nodeDefinitions'
import BaseModal from '../common/BaseModal.vue'
import BaseInput from '../ui/BaseInput.vue'
import BaseSelect from '../ui/BaseSelect.vue'
import BaseButton from '../ui/BaseButton.vue'
import { useUiStore } from '../../stores/uiStore'

defineProps<{
  isOpen: boolean
}>()

const emit = defineEmits(['close'])

const uiStore = useUiStore()

const editingCategory = ref<'node' | 'edge'>('node')
const editingNodeType = ref<NodeType>('stochastic')
const editingEdgeType = ref<'stochastic' | 'deterministic'>('stochastic')
const applyFontToAllNodes = ref(false)

const tempNodeStyle = ref({
  backgroundColor: '',
  borderColor: '',
  borderWidth: 2,
  borderStyle: 'solid',
  backgroundOpacity: 1,
  shape: '',
  width: 60,
  height: 60,
  labelFontSize: 10,
  labelColor: '#000000',
})

const tempEdgeStyle = ref({
  color: '',
  width: 3,
  lineStyle: 'solid',
  labelFontSize: 10,
  labelColor: '#000000',
  labelBackgroundColor: '#ffffff',
  labelBackgroundOpacity: 1,
  labelBorderColor: '#cccccc',
  labelBorderWidth: 1,
  labelBackgroundShape: 'rectangle' as 'rectangle' | 'roundrectangle',
})

const nodeTypeOptions = nodeDefinitions.map((def) => ({ label: def.label, value: def.nodeType }))

const shapeOptions = [
  { label: 'Ellipse', value: 'ellipse' },
  { label: 'Rectangle', value: 'rectangle' },
  { label: 'Round Rectangle', value: 'round-rectangle' },
  { label: 'Triangle', value: 'triangle' },
  { label: 'Diamond', value: 'diamond' },
  { label: 'Pentagon', value: 'pentagon' },
  { label: 'Hexagon', value: 'hexagon' },
  { label: 'Star', value: 'star' },
]

const borderStyleOptions = [
  { label: 'Solid', value: 'solid' },
  { label: 'Dotted', value: 'dotted' },
  { label: 'Dashed', value: 'dashed' },
  { label: 'Double', value: 'double' },
]

const edgeStyleOptions = [
  { label: 'Solid', value: 'solid' },
  { label: 'Dashed', value: 'dashed' },
  { label: 'Dotted', value: 'dotted' },
]

const labelShapeOptions = [
  { label: 'Rectangle', value: 'rectangle' },
  { label: 'Rounded', value: 'roundrectangle' },
]

const loadNodeStyle = () => {
  const currentStyle = uiStore.nodeStyles[editingNodeType.value]
  tempNodeStyle.value = { ...currentStyle }
}

const loadEdgeStyle = () => {
  const currentStyle = uiStore.edgeStyles[editingEdgeType.value]
  tempEdgeStyle.value = { ...currentStyle }
}

onMounted(() => {
  loadNodeStyle()
  loadEdgeStyle()
})

const switchNodeType = (type: NodeType) => {
  editingNodeType.value = type
  loadNodeStyle()
}

const switchEdgeType = (type: 'stochastic' | 'deterministic') => {
  editingEdgeType.value = type
  loadEdgeStyle()
}

const saveStyleSettings = () => {
  if (editingCategory.value === 'node') {
    uiStore.nodeStyles[editingNodeType.value] = { ...tempNodeStyle.value }

    if (applyFontToAllNodes.value) {
      Object.keys(uiStore.nodeStyles).forEach((key) => {
        if (key !== editingNodeType.value) {
          uiStore.nodeStyles[key].labelFontSize = tempNodeStyle.value.labelFontSize
          uiStore.nodeStyles[key].labelColor = tempNodeStyle.value.labelColor
        }
      })
    }
  } else {
    uiStore.edgeStyles[editingEdgeType.value] = { ...tempEdgeStyle.value }
  }
  emit('close')
}

const resetStyleSettings = () => {
  if (editingCategory.value === 'node') {
    const def = nodeDefinitions.find((d) => d.nodeType === editingNodeType.value)
    if (def) {
      tempNodeStyle.value = { ...def.defaultStyle }
    }
  } else {
    tempEdgeStyle.value = { ...defaultEdgeStyles[editingEdgeType.value] }
  }
}
</script>

<template>
  <BaseModal :is-open="isOpen" @close="emit('close')">
    <template #header>
      <h3>Graph Styles</h3>
    </template>
    <template #body>
      <div class="db-style-container">
        <div class="db-category-tabs">
          <button :class="{ 'db-active': editingCategory === 'node' }" @click="editingCategory = 'node'">
            Nodes
          </button>
          <button :class="{ 'db-active': editingCategory === 'edge' }" @click="editingCategory = 'edge'">
            Edges
          </button>
        </div>

        <!-- Node Styling Form -->
        <div class="db-style-form" v-if="editingCategory === 'node'">
          <div class="db-form-group">
            <label>Node Type</label>
            <BaseSelect
              :model-value="editingNodeType"
              :options="nodeTypeOptions"
              @update:model-value="switchNodeType($event as NodeType)"
            />
          </div>

          <div class="db-scrollable-form">
            <div class="db-form-group">
              <label>Shape</label>
              <BaseSelect
                :model-value="tempNodeStyle.shape"
                :options="shapeOptions"
                @update:model-value="tempNodeStyle.shape = $event"
              />
            </div>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Fill Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempNodeStyle.backgroundColor" />
                </div>
              </div>
              <div class="db-form-group">
                <label>Border Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempNodeStyle.borderColor" />
                </div>
              </div>
            </div>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Border Width (px)</label>
                <BaseInput type="number" v-model.number="tempNodeStyle.borderWidth" min="0" />
              </div>
              <div class="db-form-group">
                <label>Border Style</label>
                <BaseSelect
                  :model-value="tempNodeStyle.borderStyle"
                  :options="borderStyleOptions"
                  @update:model-value="tempNodeStyle.borderStyle = $event"
                />
              </div>
            </div>
            <div class="db-form-group">
              <label>Opacity ({{ tempNodeStyle.backgroundOpacity }})</label>
              <input
                type="range"
                min="0"
                max="1"
                step="0.1"
                v-model.number="tempNodeStyle.backgroundOpacity"
                class="w-full"
              />
            </div>
            <div class="db-grid-2" v-if="editingNodeType !== 'plate'">
              <div class="db-form-group">
                <label>Width (px)</label>
                <BaseInput type="number" v-model.number="tempNodeStyle.width" />
              </div>
              <div class="db-form-group">
                <label>Height (px)</label>
                <BaseInput type="number" v-model.number="tempNodeStyle.height" />
              </div>
            </div>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Label Size (px)</label>
                <BaseInput type="number" v-model.number="tempNodeStyle.labelFontSize" min="1" />
              </div>
              <div class="db-form-group">
                <label>Label Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempNodeStyle.labelColor" />
                </div>
              </div>
            </div>
            <div class="db-form-group db-checkbox-row">
              <input type="checkbox" id="apply-font-all" v-model="applyFontToAllNodes" />
              <label for="apply-font-all">Apply font settings to all node types</label>
            </div>
          </div>
        </div>

        <!-- Edge Styling Form -->
        <div class="db-style-form" v-else>
          <div class="db-edge-type-switcher">
            <BaseButton
              size="small"
              :type="editingEdgeType === 'stochastic' ? 'primary' : 'secondary'"
              @click="switchEdgeType('stochastic')"
              >Stochastic</BaseButton
            >
            <BaseButton
              size="small"
              :type="editingEdgeType === 'deterministic' ? 'primary' : 'secondary'"
              @click="switchEdgeType('deterministic')"
              >Deterministic</BaseButton
            >
          </div>
          <div class="db-scrollable-form">
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Line Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempEdgeStyle.color" />
                </div>
              </div>
              <div class="db-form-group">
                <label>Width (px)</label>
                <BaseInput type="number" v-model.number="tempEdgeStyle.width" min="1" />
              </div>
            </div>
            <div class="db-form-group">
              <label>Line Style</label>
              <BaseSelect
                :model-value="tempEdgeStyle.lineStyle"
                :options="edgeStyleOptions"
                @update:model-value="tempEdgeStyle.lineStyle = $event"
              />
            </div>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Label Size (px)</label>
                <BaseInput type="number" v-model.number="tempEdgeStyle.labelFontSize" min="1" />
              </div>
              <div class="db-form-group">
                <label>Label Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempEdgeStyle.labelColor" />
                </div>
              </div>
            </div>

            <div class="db-dropdown-divider"></div>
            <h5 class="db-sub-title">Label Background</h5>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Background Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempEdgeStyle.labelBackgroundColor" />
                </div>
              </div>
              <div class="db-form-group">
                <label>Opacity ({{ tempEdgeStyle.labelBackgroundOpacity }})</label>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.1"
                  v-model.number="tempEdgeStyle.labelBackgroundOpacity"
                  class="w-full h-8"
                />
              </div>
            </div>
            <div class="db-grid-2">
              <div class="db-form-group">
                <label>Border Color</label>
                <div class="db-color-wrapper">
                  <input type="color" v-model="tempEdgeStyle.labelBorderColor" />
                </div>
              </div>
              <div class="db-form-group">
                <label>Border Width</label>
                <BaseInput type="number" v-model.number="tempEdgeStyle.labelBorderWidth" min="0" />
              </div>
            </div>
            <div class="db-form-group">
              <label>Background Shape</label>
              <BaseSelect
                :model-value="tempEdgeStyle.labelBackgroundShape"
                :options="labelShapeOptions"
                @update:model-value="tempEdgeStyle.labelBackgroundShape = $event"
              />
            </div>

            <div class="db-info-box">
              <i class="fas fa-info-circle"></i>
              <small
                >Note: Stochastic edges connect to stochastic/observed nodes. Deterministic edges
                connect to deterministic nodes.</small
              >
            </div>
          </div>
        </div>
      </div>
    </template>
    <template #footer>
      <div class="db-modal-footer">
        <BaseButton type="secondary" @click="resetStyleSettings">Reset to Default</BaseButton>
        <div class="db-footer-actions">
          <BaseButton type="primary" @click="saveStyleSettings">Save</BaseButton>
        </div>
      </div>
    </template>
  </BaseModal>
</template>

<style scoped>
.db-style-container {
  display: flex;
  flex-direction: column;
  gap: 15px;
  max-height: 60vh;
}

.db-category-tabs {
  display: flex;
  border-bottom: 1px solid var(--theme-border);
  gap: 10px;
}

.db-category-tabs button {
  background: transparent;
  border: none;
  border-bottom: 2px solid transparent;
  padding: 8px 16px;
  font-weight: 600;
  color: var(--theme-text-secondary);
  cursor: pointer;
  transition: all 0.2s;
}

.db-category-tabs button.db-active {
  color: var(--theme-primary);
  border-bottom-color: var(--theme-primary);
}

.db-style-form {
  display: flex;
  flex-direction: column;
  gap: 12px;
  flex: 1;
  overflow: hidden;
}

.db-scrollable-form {
  overflow-y: auto;
  padding-right: 5px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.db-form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.db-form-group label {
  font-size: 0.85em;
  font-weight: 600;
}

.db-checkbox-row {
  flex-direction: row;
  align-items: center;
  gap: 8px;
}

.db-sub-title {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--color-heading);
  margin: 4px 0 0 0;
}

.db-grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.db-color-wrapper {
  height: 32px;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  padding: 2px;
}

.db-color-wrapper input {
  width: 100%;
  height: 100%;
  border: none;
  padding: 0;
  cursor: pointer;
  background: none;
}

.db-edge-type-switcher {
  display: flex;
  gap: 8px;
  margin-bottom: 8px;
}

.db-info-box {
  background-color: var(--color-background-mute);
  padding: 8px;
  border-radius: 4px;
  font-size: 0.8em;
  color: var(--color-text-secondary);
  display: flex;
  gap: 6px;
  align-items: flex-start;
}

.db-modal-footer {
  display: flex;
  justify-content: space-between;
  width: 100%;
  flex-wrap: wrap;
  gap: 10px;
}

.db-footer-actions {
  display: flex;
  gap: 8px;
}

.h-8 {
  height: 32px;
}
</style>
