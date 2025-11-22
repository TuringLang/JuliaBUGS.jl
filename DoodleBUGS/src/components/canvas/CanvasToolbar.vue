<script setup lang="ts">
import BaseButton from '../ui/BaseButton.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import type { NodeType } from '../../types';
import { nodeDefinitions } from '../../config/nodeDefinitions';
import { computed } from 'vue';

defineProps<{
  currentMode: string;
  currentNodeType: NodeType;
  isConnecting: boolean;
  sourceNodeName: string | undefined;
  isGridEnabled: boolean;
  gridSize: number;
}>();

const emit = defineEmits<{
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'update:isGridEnabled', value: boolean): void;
  (e: 'update:gridSize', value: number): void;
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

const updateNodeType = (value: NodeType) => {
  emit('update:currentNodeType', value);
};
</script>

<template>
  <div class="canvas-toolbar">
    <BaseButton
      class="base-button"
      :class="{ active: currentMode === 'select' }"
      @click="setMode('select')"
      size="small"
    >
      Select
    </BaseButton>
    <BaseButton
      class="base-button"
      :class="{ active: currentMode === 'add-node' }"
      @click="setMode('add-node')"
      size="small"
    >
      Add Node
    </BaseButton>
    <BaseButton
      class="base-button"
      :class="{ active: currentMode === 'add-edge' }"
      @click="setMode('add-edge')"
      size="small"
    >
      Add Edge
    </BaseButton>
    
    <div v-if="currentMode === 'add-node'" class="node-type-selector">
      <label for="node-type">Type:</label>
      <BaseSelect 
        :model-value="currentNodeType" 
        :options="availableNodeTypes" 
        @update:model-value="(val: any) => updateNodeType(val as NodeType)"
        class="w-32"
      />
    </div>
    
    <div class="separator"></div>
    <BaseButton class="base-button icon-only" @click="$emit('undo')" title="Undo" size="small">
      <i class="fas fa-undo"></i>
    </BaseButton>
    <BaseButton class="base-button icon-only" @click="$emit('redo')" title="Redo" size="small">
      <i class="fas fa-redo"></i>
    </BaseButton>
    
    <span v-if="isConnecting" class="connecting-message">
      Connecting from: <strong>{{ sourceNodeName }}</strong> (Click target node)
    </span>
  </div>
</template>

<style scoped>
.canvas-toolbar {
  display: flex;
  gap: 6px;
  padding: 6px 10px;
  background-color: var(--color-background-soft);
  border-bottom: 1px solid var(--color-border-light);
  align-items: center;
  flex-wrap: wrap;
  flex-shrink: 0;
  color: var(--color-text);
  min-height: 40px;
  box-sizing: border-box;
}

@media (max-width: 768px) {
  .canvas-toolbar {
    gap: 4px;
    padding: 4px 6px;
  }
}

:global(html.dark-mode) .canvas-toolbar {
  background-color: var(--p-surface-800);
  border-bottom-color: var(--p-surface-700);
}

.separator {
  width: 1px;
  height: 20px;
  background-color: var(--color-border-dark);
  margin: 0 4px;
}

.canvas-toolbar .base-button {
  padding: 4px 10px !important;
  border: 1px solid var(--color-border-dark);
  background-color: var(--color-background-soft);
  color: var(--color-text);
  cursor: pointer;
  border-radius: 4px;
  transition: background-color 0.2s ease, border-color 0.2s ease;
  box-sizing: border-box;
  font-size: 0.85rem;
}

.canvas-toolbar .base-button.icon-only {
    padding: 4px 8px !important;
    min-width: 28px;
}

.canvas-toolbar .base-button.active {
  background-color: var(--color-primary);
  color: white;
  border-color: var(--color-primary);
}

:global(html.dark-mode) .canvas-toolbar .base-button.active {
  color: black;
}

.canvas-toolbar .base-button:hover:not(.active) {
  background-color: var(--color-border-light);
  border-color: var(--color-border-dark);
}

.node-type-selector {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-left: 6px;
}

.node-type-selector label {
  font-size: 0.85em;
  color: var(--color-text);
}

.node-type-selector select {
  padding: 4px 6px;
  border: 1px solid var(--color-border-dark);
  border-radius: 4px;
  background-color: var(--color-background-soft);
  color: var(--color-text);
  font-size: 0.85em;
  cursor: pointer;
}

.connecting-message {
  margin-left: auto;
  font-style: italic;
  color: var(--color-secondary);
  font-size: 0.85em;
  white-space: nowrap;
}

@media (max-width: 768px) {
  .connecting-message {
    font-size: 0.75em;
  }
  
  .connecting-message strong {
    display: inline-block;
    max-width: 80px;
    overflow: hidden;
    text-overflow: ellipsis;
    vertical-align: bottom;
  }
}
</style>
