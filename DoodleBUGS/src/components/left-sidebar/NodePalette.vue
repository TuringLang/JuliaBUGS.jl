<script setup lang="ts">
import type { PaletteItemType } from '../../types';
import { nodeDefinitions, connectionPaletteItems } from '../../config/nodeDefinitions';

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
          <div class="card-icon connection-icon"></div>
          <span class="card-label">{{ connection.label }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.node-palette {
  padding: 12px;
  background-color: var(--color-background-soft);
  height: 100%;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.palette-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.section-title {
  font-size: 0.9em;
  font-weight: 600;
  color: var(--color-heading);
  padding-bottom: 8px;
  border-bottom: 1px solid var(--color-border-light);
  margin: 0;
}

.palette-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

.palette-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 15px 10px;
  border-radius: 8px;
  border: 1px solid var(--color-border);
  background-color: var(--color-background-soft);
  cursor: grab;
  text-align: center;
  transition: all 0.2s ease-in-out;
  user-select: none;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
}

.palette-card:hover {
  transform: translateY(-3px);
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
  border-color: var(--color-primary);
}

.palette-card:active {
  cursor: grabbing;
  transform: translateY(-1px);
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
}

/* Dark Mode Overrides */
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
  font-size: 0.8em;
  font-weight: 500;
  color: var(--color-text);
  margin-top: 8px;
}

.card-icon {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5em;
  font-weight: bold;
  border-radius: 50%;
  color: #fff;
}

.icon-stochastic { background-color: #dc3545; }
.icon-deterministic { background-color: #28a745; border-radius: 8px; font-size: 1.2em; }
.icon-constant { background-color: #6c757d; border-radius: 4px; }
.icon-observed {
  background-color: var(--color-background-soft);
  border: 2px dashed #007bff;
  color: #007bff;
}
.icon-plate {
  background-color: var(--color-background-soft);
  border: 2px dashed var(--color-text);
  color: var(--color-text);
  border-radius: 8px;
  font-size: 1.2em;
}

.connection-icon {
  width: 100%;
  height: 20px;
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
  border-width: 6px 0 6px 10px;
  border-color: transparent transparent transparent #6c757d;
}
</style>
