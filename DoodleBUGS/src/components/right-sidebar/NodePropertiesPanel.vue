<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import type { GraphElement, GraphNode, GraphEdge, ValidationError } from '../../types';
import BaseInput from '../ui/BaseInput.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import BaseButton from '../ui/BaseButton.vue';
import BaseModal from '../common/BaseModal.vue';
import { getNodeDefinition, getDistributionByName, type NodeDefinition } from '../../config/nodeDefinitions';

const props = defineProps<{
  selectedElement: GraphElement | null;
  validationErrors: Map<string, ValidationError[]>;
}>();

const emit = defineEmits<{
  (e: 'update-element', element: GraphElement): void;
  (e: 'delete-element', elementId: string): void;
}>();

const localElement = ref<GraphElement | null>(null);
const showDeleteConfirmModal = ref(false);

const currentDefinition = computed<NodeDefinition | undefined>(() => {
  if (localElement.value?.type === 'node') {
    return getNodeDefinition((localElement.value as GraphNode).nodeType);
  }
  return undefined;
});

const currentDistribution = computed(() => {
    if (localElement.value?.type === 'node') {
        const node = localElement.value as GraphNode;
        return getDistributionByName(node.distribution || '');
    }
    return undefined;
});

const selectedDistributionOption = computed(() => {
  if (localElement.value?.type === 'node') {
    const node = localElement.value as GraphNode;
    if (node.distribution) {
      const definition = getNodeDefinition(node.nodeType);
      const distProp = definition?.properties.find(p => p.key === 'distribution');
      return distProp?.options?.find(opt => opt.value === node.distribution);
    }
  }
  return undefined;
});

const elementErrors = computed(() => {
    if (props.selectedElement) {
        return props.validationErrors.get(props.selectedElement.id) || [];
    }
    return [];
});

watch(() => props.selectedElement, (newVal) => {
  localElement.value = newVal ? JSON.parse(JSON.stringify(newVal)) : null;
}, { deep: true, immediate: true });

const isNode = computed(() => localElement.value?.type === 'node');
const isEdge = computed(() => localElement.value?.type === 'edge');

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

const getErrorForField = (fieldKey: string): string | undefined => {
    if (localElement.value) {
        const errors = props.validationErrors.get(localElement.value.id);
        const error = errors?.find(err => err.field === fieldKey);
        return error?.message;
    }
    return undefined;
};
</script>

<template>
  <div class="node-properties-panel">
    <h4>Properties</h4>
    <div v-if="!localElement" class="no-selection-message">
      <p>Select a node or edge on the canvas to view/edit its properties.</p>
    </div>
    <div v-else class="properties-form">
      <div v-if="elementErrors.length > 0" class="validation-errors-container">
        <h5 class="validation-title">
            <i class="fas fa-exclamation-triangle"></i> Validation Issues
        </h5>
        <ul>
          <li v-for="(error, index) in elementErrors" :key="index">
            {{ error.message }}
          </li>
        </ul>
      </div>

      <div class="form-group">
        <label for="element-id">ID:</label>
        <BaseInput id="element-id" :model-value="localElement.id" disabled />
      </div>

      <template v-if="isNode && currentDefinition">
        <div v-for="prop in currentDefinition.properties" :key="prop.key" class="form-group">
          <label :for="`prop-${prop.key}`">{{ prop.label }}:</label>
          <div class="input-wrapper">
            <BaseSelect
              v-if="prop.type === 'select'"
              :id="`prop-${prop.key}`"
              v-model="(localElement as any)[prop.key]"
              :options="prop.options!"
              @change="handleUpdate"
              :class="{ 'has-error': getErrorForField(prop.key) }"
            />
            <input
              v-else-if="prop.type === 'checkbox'"
              type="checkbox"
              :id="`prop-${prop.key}`"
              v-model="(localElement as any)[prop.key]"
              @change="handleUpdate"
              class="form-checkbox"
            />
            <BaseInput
              v-else
              :id="`prop-${prop.key}`"
              :type="prop.type"
              v-model="(localElement as any)[prop.key]"
              :placeholder="prop.placeholder"
              @input="handleUpdate"
              :class="{ 'has-error': getErrorForField(prop.key) }"
            />
          </div>
          <small v-if="prop.helpText" class="help-text">{{ prop.helpText }}</small>
          <small v-if="prop.key === 'distribution' && selectedDistributionOption?.helpText" class="help-text distribution-help">
            {{ selectedDistributionOption.helpText }}
          </small>
          <small v-if="getErrorForField(prop.key)" class="error-message">{{ getErrorForField(prop.key) }}</small>
        </div>

        <template v-if="currentDistribution && currentDefinition.parameters">
            <div 
                v-for="(paramName, index) in currentDistribution.paramNames" 
                :key="paramName" 
                class="form-group"
            >
                <label :for="`param-${index}`">{{ paramName }}:</label>
                <BaseInput
                    :id="`param-${index}`"
                    type="text"
                    v-model="(localElement as any)[`param${index + 1}`]"
                    placeholder="Enter value or parent name"
                    @input="handleUpdate"
                    :class="{ 'has-error': getErrorForField(`param${index + 1}`) }"
                />
            </div>
        </template>
      </template>

      <template v-else-if="isEdge">
        <div class="form-group">
          <label for="edge-name">Name (Label):</label>
          <BaseInput
            id="edge-name"
            type="text"
            v-model="(localElement as GraphEdge).name"
            placeholder="Enter optional edge label"
            @input="handleUpdate"
          />
        </div>
      </template>

      <div class="action-buttons">
        <BaseButton @click="confirmDelete" type="danger">Delete Element</BaseButton>
      </div>
    </div>
    <BaseModal :is-open="showDeleteConfirmModal" @close="cancelDelete">
      <template #header>
        <h3>Confirm Deletion</h3>
      </template>
      <template #body>
        <p v-if="localElement">
          Are you sure you want to delete this {{ localElement.type }}?
          <strong v-if="'name' in localElement && localElement.name">{{ localElement.name }}</strong>
          This action cannot be undone.
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
  padding-right: 5px;
}

.validation-errors-container {
    background-color: #fffbe6;
    border: 1px solid #ffe58f;
    border-radius: 4px;
    padding: 10px 15px;
    margin-bottom: 10px;
}

.validation-title {
    margin: 0 0 8px 0;
    font-size: 0.9em;
    font-weight: 600;
    color: #d46b08;
    display: flex;
    align-items: center;
    gap: 8px;
}

.validation-errors-container ul {
    margin: 0;
    padding-left: 20px;
    font-size: 0.85em;
    color: #d46b08;
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
  text-transform: capitalize;
}

.input-wrapper {
    position: relative;
    display: flex;
    align-items: center;
}

.input-wrapper .base-input,
.input-wrapper .base-select {
    flex-grow: 1;
}

.has-error {
    border-color: var(--color-danger) !important;
}

.has-error:focus {
    box-shadow: 0 0 0 2px rgba(220, 53, 69, 0.25) !important;
}

.form-group .form-checkbox {
  width: 16px;
  height: 16px;
  align-self: flex-start;
}

.help-text {
  font-size: 0.75em;
  color: #888;
  margin-top: 2px;
  line-height: 1.4;
}

.distribution-help {
  background-color: var(--color-background-mute);
  padding: 5px 8px;
  border-radius: 4px;
}

.error-message {
    font-size: 0.75em;
    color: var(--color-danger);
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
