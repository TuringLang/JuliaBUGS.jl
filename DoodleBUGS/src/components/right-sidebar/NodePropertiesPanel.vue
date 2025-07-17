<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import type { GraphElement, GraphNode, GraphEdge } from '../../types';
import BaseInput from '../ui/BaseInput.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import BaseButton from '../ui/BaseButton.vue';
import BaseModal from '../common/BaseModal.vue';
import { getNodeDefinition, type NodeDefinition } from '../../config/nodeDefinitions';

const props = defineProps<{
  selectedElement: GraphElement | null;
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

      <template v-if="isNode && currentDefinition">
        <div v-for="prop in currentDefinition.properties" :key="prop.key" class="form-group">
          <label :for="`prop-${prop.key}`">{{ prop.label }}:</label>
          
          <BaseSelect
            v-if="prop.type === 'select'"
            :id="`prop-${prop.key}`"
            v-model="(localElement as any)[prop.key]"
            :options="prop.options!"
            @change="handleUpdate"
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
          />

          <small v-if="prop.helpText" class="help-text">{{ prop.helpText }}</small>
        </div>
      </template>

      <template v-else-if="isEdge">
        <div class="form-group">
            <label for="element-name">Name:</label>
            <BaseInput id="element-name" v-model="(localElement as GraphEdge).name!" @input="handleUpdate" />
        </div>
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

.form-group .form-checkbox {
  width: 16px;
  height: 16px;
  align-self: flex-start;
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
