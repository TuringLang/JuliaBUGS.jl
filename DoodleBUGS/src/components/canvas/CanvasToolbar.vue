<script setup lang="ts">
import BaseButton from '../ui/BaseButton.vue';
import type { NodeType } from '../../types';
import { nodeDefinitions } from '../../config/nodeDefinitions';
import { computed } from 'vue';

defineProps<{
  currentMode: string;
  currentNodeType: NodeType;
  isConnecting: boolean;
  sourceNodeName: string | undefined;
}>();

const emit = defineEmits<{
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'undo'): void;
  (e: 'redo'): void;
}>();

// Get node types for the dropdown from the central config file
const availableNodeTypes = computed(() => {
  return nodeDefinitions.map(def => ({
    label: def.label,
    value: def.nodeType
  }));
});

const setMode = (mode: string) => {
  emit('update:currentMode', mode);
};

const updateNodeType = (event: Event) => {
  const target = event.target as HTMLSelectElement;
  emit('update:currentNodeType', target.value as NodeType);
};
</script>

<template>
  <div class="canvas-toolbar">
    <BaseButton
      :class="{ active: currentMode === 'select' }"
      @click="setMode('select')"
    >
      Select
    </BaseButton>
    <BaseButton
      :class="{ active: currentMode === 'add-node' }"
      @click="setMode('add-node')"
    >
      Add Node
    </BaseButton>
    <BaseButton
      :class="{ active: currentMode === 'add-edge' }"
      @click="setMode('add-edge')"
    >
      Add Edge
    </BaseButton>

    
    <div v-if="currentMode === 'add-node'" class="node-type-selector">
      <label for="node-type">Node Type:</label>
      <select id="node-type" :value="currentNodeType" @change="updateNodeType">
        <option v-for="type in availableNodeTypes" :key="type.value" :value="type.value">
          {{ type.label }}
        </option>
      </select>
    </div>
    
    <div class="separator"></div>
    <BaseButton @click="$emit('undo')" title="Undo">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 7v6h6"></path>
        <path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"></path>
      </svg>
    </BaseButton>
    <BaseButton @click="$emit('redo')" title="Redo">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 7v6h-6"></path>
        <path d="M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13"></path>
      </svg>
    </BaseButton>
    
    <span v-if="isConnecting" class="connecting-message">
      Connecting from: <strong>{{ sourceNodeName }}</strong> (Click target node)
    </span>
  </div>
</template>

<style scoped>
.canvas-toolbar {
  display: flex;
  gap: 10px;
  padding: 10px;
  background-color: var(--color-background-soft);
  border-bottom: 1px solid var(--color-border-light);
  align-items: center;
  flex-wrap: wrap;
  flex-shrink: 0;
}

.separator {
  width: 1px;
  height: 24px;
  background-color: var(--color-border-dark);
  margin: 0 5px;
}

.canvas-toolbar .base-button {
  padding: 8px 15px;
  border: 1px solid var(--color-border-dark);
  background-color: #fff;
  cursor: pointer;
  border-radius: 4px;
  transition: background-color 0.2s ease, border-color 0.2s ease;
}

.canvas-toolbar .base-button.active {
  background-color: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}

.canvas-toolbar .base-button:hover:not(.active) {
  background-color: var(--color-border-light);
}

.node-type-selector {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-left: 10px;
}

.node-type-selector label {
  font-size: 0.9em;
  color: #555;
}

.node-type-selector select {
  padding: 6px 8px;
  border: 1px solid var(--color-border-dark);
  border-radius: 4px;
  background-color: white;
  font-size: 0.9em;
  cursor: pointer;
}

.connecting-message {
  margin-left: auto;
  font-style: italic;
  color: #666;
  font-size: 0.9em;
  white-space: nowrap;
}
</style>
