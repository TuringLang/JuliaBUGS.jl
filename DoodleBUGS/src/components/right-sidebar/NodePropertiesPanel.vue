<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import type { GraphElement, GraphNode, GraphEdge, NodeType } from '../../types';
import BaseInput from '../ui/BaseInput.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import BaseButton from '../ui/BaseButton.vue';
import BaseModal from '../common/BaseModal.vue';

const props = defineProps<{
  selectedElement: GraphElement | null;
}>();

const emit = defineEmits<{
  (e: 'update-element', element: GraphElement): void;
  (e: 'delete-element', elementId: string): void;
}>();

const localElement = ref<GraphElement | null>(null);
const showDeleteConfirmModal = ref(false);

watch(() => props.selectedElement, (newVal) => {
  if (newVal) {
    const newElement = JSON.parse(JSON.stringify(newVal));
    if (newElement.type === 'node') {
      newElement.distribution = newElement.distribution ?? '';
      newElement.equation = newElement.equation ?? '';
      if (typeof newElement.initialValue === 'object' && newElement.initialValue !== null) {
        newElement.initialValue = JSON.stringify(newElement.initialValue);
      } else {
        newElement.initialValue = newElement.initialValue ?? '';
      }
      newElement.indices = newElement.indices ?? '';
      newElement.loopVariable = newElement.loopVariable ?? '';
      newElement.loopRange = newElement.loopRange ?? '';
    } else if (newElement.type === 'edge') {
      newElement.name = newElement.name ?? '';
    }
    localElement.value = newElement;
  } else {
    localElement.value = null;
  }
}, { deep: true, immediate: true });

const isNode = computed(() => localElement.value?.type === 'node');
const isEdge = computed(() => localElement.value?.type === 'edge');
const isPlate = computed(() => isNode.value && (localElement.value as GraphNode).nodeType === 'plate');

const nodeTypes: { value: NodeType; label: string }[] = [
  { value: 'stochastic', label: 'Stochastic' },
  { value: 'deterministic', label: 'Deterministic' },
  { value: 'constant', label: 'Constant' },
  { value: 'observed', label: 'Observed' },
  { value: 'plate', label: 'Plate' },
];

const distributionOptions = [
  { value: 'dnorm', label: 'Normal (dnorm)' },
  { value: 'dbeta', label: 'Beta (dbeta)' },
  { value: 'dgamma', label: 'Gamma (dgamma)' },
  { value: 'dbin', label: 'Binomial (dbin)' },
  { value: 'dpois', label: 'Poisson (dpois)' },
  { value: 'dt', label: 'Student-t (dt)' },
  { value: 'dchisqr', label: 'Chi-squared (dchisqr)' },
  { value: 'dweib', label: 'Weibull (dweib)' },
  { value: 'dexp', label: 'Exponential (dexp)' },
  { value: 'dloglik', label: 'Log-Likelihood (dloglik)' },
];

const handleUpdate = () => {
  if (localElement.value) {
    emit('update-element', localElement.value);
  }
};

const confirmDelete = () => {
  if (localElement.value) {
    showDeleteConfirmModal.value = true;
  }
};

const executeDelete = () => {
  if (localElement.value) {
    emit('delete-element', localElement.value.id);
    localElement.value = null;
  }
  showDeleteConfirmModal.value = false;
};

const cancelDelete = () => {
  showDeleteConfirmModal.value = false;
};
</script>
<template>
  <div class="node-properties-panel">
    <h4>Properties</h4>
    <div v-if="!localElement" class="no-selection-message">
      <p>Select a node or edge on the canvas to view/edit its properties.</p>
    </div>
    <div v-else class="properties-form">
      <div class="form-group">
        <label for="element-id">ID:</label>
        <BaseInput id="element-id" :model-value="localElement.id" disabled />
      </div>
      <div class="form-group">
        <label for="element-name">Name:</label>
        <BaseInput id="element-name" v-model="localElement.name!" @input="handleUpdate" />
      </div>

      <template v-if="isNode">
        <div class="form-group">
          <label for="node-type">Node Type:</label>
          <BaseSelect id="node-type" v-model="(localElement as GraphNode).nodeType" :options="nodeTypes"
            @change="handleUpdate" />
        </div>
        <template v-if="!isPlate">
          <div class="form-group">
            <label for="node-position-x">Position X:</label>
            <BaseInput id="node-position-x" type="number" v-model.number="(localElement as GraphNode).position.x"
              @input="handleUpdate" />
          </div>
          <div class="form-group">
            <label for="node-position-y">Position Y:</label>
            <BaseInput id="node-position-y" type="number" v-model.number="(localElement as GraphNode).position.y"
              @input="handleUpdate" />
          </div>
          <div class="form-section-header">BUGS Specific Properties</div>
          <div class="form-group">
            <label for="distribution">Distribution (~):</label>
            <BaseSelect id="distribution" v-model="(localElement as GraphNode).distribution!"
              :options="distributionOptions" @change="handleUpdate" />
          </div>
          <div class="form-group">
            <label for="equation">Equation (&lt;--):</label>
            <BaseInput id="equation" v-model="(localElement as GraphNode).equation!" placeholder="e.g., a + b * x"
              @input="handleUpdate" />
          </div>
          <div class="form-group checkbox-group">
            <label for="observed">Observed:</label>
            <input type="checkbox" id="observed" v-model="(localElement as GraphNode).observed"
              @change="handleUpdate" />
          </div>
          <div class="form-group">
            <label for="initial-value">Initial Value:</label>
            <BaseInput id="initial-value" v-model="(localElement as GraphNode).initialValue"
              placeholder="e.g., 0.5 or list(value=0.5)" @input="handleUpdate" />
          </div>
          <div class="form-group">
            <label for="variable-indices">Indices (e.g., i,j):</label>
            <BaseInput id="variable-indices" v-model="(localElement as GraphNode).indices!"
              placeholder="e.g., i,j or 1:N" @input="handleUpdate" />
            <small class="help-text">Use comma-separated for multiple indices, e.g., 'i,j' or '1:N, 1:M'</small>
          </div>
        </template>
        <template v-else>
          <div class="form-section-header">Plate Properties</div>
          <div class="form-group">
            <label for="plate-loop-variable">Loop Variable:</label>
            <BaseInput id="plate-loop-variable" v-model="(localElement as GraphNode).loopVariable!"
              placeholder="e.g., i" @input="handleUpdate" />
          </div>
          <div class="form-group">
            <label for="plate-loop-range">Loop Range:</label>
            <BaseInput id="plate-loop-range" v-model="(localElement as GraphNode).loopRange!" placeholder="e.g., 1:N"
              @input="handleUpdate" />
          </div>
          <small class="help-text">Define the iteration for this plate, e.g., 'i' in '1:N'</small>
        </template>
      </template>

      <template v-else-if="isEdge">
        <div class="form-group">
          <label for="edge-source">Source Node ID:</label>
          <BaseInput id="edge-source" :model-value="(localElement as GraphEdge).source" disabled />
        </div>
        <div class="form-group">
          <label for="edge-target">Target Node ID:</label>
          <BaseInput id="edge-target" :model-value="(localElement as GraphEdge).target" disabled />
        </div>
      </template>

      <div class="action-buttons">
        <BaseButton @click="handleUpdate" type="primary">Apply Changes</BaseButton>
        <BaseButton @click="confirmDelete" type="danger">Delete Element</BaseButton>
      </div>
    </div>
    <BaseModal :is-open="showDeleteConfirmModal" @close="cancelDelete">
      <template #header>
        <h3>Confirm Deletion</h3>
      </template>
      <template #body>
        <p>Are you sure you want to delete "{{ localElement?.name || localElement?.id }}"? This action cannot be undone.
        </p>
      </template>
      <template #footer>
        <BaseButton @click="cancelDelete" type="secondary">Cancel</BaseButton>
        <BaseButton @click="executeDelete" type="danger">Delete</BaseButton>
      </template>
    </BaseModal>
  </div>
</template>
<style scoped>
.node-properties-panel {
  padding: 15px;
  height: 100%;
  display: flex;
  flex-direction: column;
}

h4 {
  margin: 0 0 10px 0;
  color: var(--color-heading);
  text-align: center;
  border-bottom: 1px solid var(--color-border-light);
  padding-bottom: 10px;
}

.no-selection-message {
  text-align: center;
  padding: 20px;
  color: var(--color-secondary);
  font-style: italic;
  background-color: var(--color-background-mute);
  border-radius: 8px;
  margin-top: 20px;
}

.properties-form {
  display: flex;
  flex-direction: column;
  gap: 15px;
  overflow-y: auto;
  padding-right: 5px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.form-group label {
  font-weight: 500;
  color: var(--color-text);
  font-size: 0.9em;
}

.form-group input[type="text"],
.form-group input[type="number"],
.form-group select {
  width: 100%;
  box-sizing: border-box;
}

.form-group.checkbox-group {
  flex-direction: row;
  align-items: center;
  gap: 10px;
}

.form-group input[type="checkbox"] {
  width: auto;
  margin-top: 0;
}

.form-section-header {
  margin-top: 15px;
  padding-bottom: 5px;
  border-bottom: 1px dashed var(--color-border-light);
  font-weight: 600;
  color: var(--color-primary);
  font-size: 0.95em;
}

.help-text {
  font-size: 0.75em;
  color: #888;
  margin-top: 2px;
}

.action-buttons {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 20px;
  padding-top: 15px;
  border-top: 1px solid var(--color-border-light);
  flex-shrink: 0;
}
</style>
