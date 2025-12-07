<script setup lang="ts">
import { type StyleValue } from 'vue'
import { storeToRefs } from 'pinia'
import NodePropertiesPanel from '../right-sidebar/NodePropertiesPanel.vue'
import LocalScriptPanel from '../right-sidebar/LocalScriptPanel.vue'
import BaseButton from '../ui/BaseButton.vue'
import { useUiStore } from '../../stores/uiStore'
import type { GraphElement, ValidationError } from '../../types'

const props = defineProps<{
  selectedElement: GraphElement | null
  validationErrors: Map<string, ValidationError[]>
  isModelValid: boolean
  enableDrag?: boolean
}>()

const emit = defineEmits<{
  (e: 'toggle-right-sidebar'): void
  (e: 'update-element', element: GraphElement): void
  (e: 'delete-element', elementId: string): void
  (e: 'show-validation-issues'): void
  (e: 'open-script-settings'): void
  (e: 'download-script'): void
  (e: 'generate-script'): void
  (e: 'share'): void
  (e: 'open-export-modal', format: 'png' | 'jpg' | 'svg'): void
  (e: 'export-json'): void
  (e: 'header-drag-start', event: MouseEvent | TouchEvent): void
}>()

const uiStore = useUiStore()
const { isRightSidebarOpen, activeRightTab } = storeToRefs(uiStore)

const sidebarStyle = (isOpen: boolean): StyleValue => {
  if (!isOpen) {
    return {
      transform: 'scale(0)',
      opacity: 0,
      pointerEvents: 'none',
    }
  }
  return {
    transform: 'scale(1)',
    opacity: 1,
    pointerEvents: 'auto',
  }
}

const handleHeaderMouseDown = (e: MouseEvent | TouchEvent) => {
  if (props.enableDrag) {
    emit('header-drag-start', e)
  }
}

const handleHeaderClick = () => {
  if (!props.enableDrag) {
    emit('toggle-right-sidebar')
  }
}
</script>

<template>
  <aside class="floating-sidebar right glass-panel" :style="sidebarStyle(isRightSidebarOpen)">
    <div
      class="sidebar-header"
      @mousedown="handleHeaderMouseDown"
      @touchstart="handleHeaderMouseDown"
      @click="handleHeaderClick"
      :style="{ cursor: enableDrag ? 'move' : 'pointer' }"
    >
      <span class="sidebar-title">Inspector</span>

      <div class="flex items-center ml-auto" @click.stop @mousedown.stop @touchstart.stop>
        <div
          class="status-indicator validation-status"
          @click="$emit('show-validation-issues')"
          :class="isModelValid ? 'valid' : 'invalid'"
        >
          <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
          <div class="instant-tooltip">
            {{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}
          </div>
        </div>

        <button class="header-icon-btn" @click="$emit('share')" title="Share via URL">
          <i class="fas fa-share-alt"></i>
        </button>
      </div>

      <div class="pointer-events-none flex items-center ml-2">
        <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon">
          <path
            fill="currentColor"
            fill-rule="evenodd"
            d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"
            clip-rule="evenodd"
          ></path>
        </svg>
      </div>
    </div>

    <div class="sidebar-tabs text-tabs">
      <button
        :class="{ active: activeRightTab === 'properties' }"
        @click="uiStore.setActiveRightTab('properties')"
      >
        Props
      </button>
      <button
        :class="{ active: activeRightTab === 'script' }"
        @click="uiStore.setActiveRightTab('script')"
      >
        Script
      </button>
      <button
        :class="{ active: activeRightTab === 'export' }"
        @click="uiStore.setActiveRightTab('export')"
      >
        Export
      </button>
    </div>

    <div class="sidebar-content">
      <NodePropertiesPanel
        v-show="activeRightTab === 'properties'"
        :selected-element="selectedElement"
        :validation-errors="validationErrors"
        @update-element="$emit('update-element', $event)"
        @delete-element="$emit('delete-element', $event)"
      />

      <LocalScriptPanel
        v-show="activeRightTab === 'script'"
        :is-active="activeRightTab === 'script'"
        @open-settings="$emit('open-script-settings')"
        @download="$emit('download-script')"
        @generate="$emit('generate-script')"
      />

      <div v-show="activeRightTab === 'export'" class="export-panel">
        <div class="menu-panel flex-col gap-3">
          <h5 class="section-title">Image Export</h5>
          <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'png')"
            ><i class="fas fa-image"></i> PNG Image</BaseButton
          >
          <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'jpg')"
            ><i class="fas fa-file-image"></i> JPG Image</BaseButton
          >
          <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'svg')"
            ><i class="fas fa-draw-polygon"></i> SVG Vector</BaseButton
          >

          <div class="divider"></div>

          <h5 class="section-title">Model Export</h5>
          <BaseButton type="ghost" class="menu-btn" @click="$emit('export-json')"
            ><i class="fas fa-file-code"></i>Export Graph, Data & Inits as JSON</BaseButton
          >
        </div>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.floating-sidebar {
  position: absolute;
  top: 16px;
  height: calc(100dvh - 32px);
  bottom: auto;
  z-index: 50;
  display: flex;
  flex-direction: column;
  border-radius: var(--radius-lg);
  overflow: hidden;
  transition:
    transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1),
    opacity 0.3s ease;
  background: var(--theme-bg-panel);
  box-shadow: var(--shadow-floating);
}

.floating-sidebar.right {
  right: 16px;
  width: 320px;
  transform-origin: top right;
}

@media (max-width: 768px) {
  .floating-sidebar.right {
    width: calc(100vw - 32px) !important;
  }
  .sidebar-tabs button {
    padding: 8px 4px;
    font-size: 0.8rem;
  }
  .sidebar-content {
    padding-bottom: 80px; /* Space for floating toolbar on mobile */
  }
}

.sidebar-header {
  padding: 12px 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--theme-border);
  background: var(--theme-bg-panel-transparent);
  color: var(--theme-text-primary);
  flex-shrink: 0;
}

.sidebar-title {
  font-weight: 600;
  font-size: var(--font-size-md);
  user-select: none;
}

.toggle-icon {
  color: var(--theme-text-secondary);
}

.status-indicator {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  cursor: help;
}

.validation-status {
  font-size: 1.1em;
  margin: 0 5px;
}
.validation-status.valid {
  color: var(--theme-success);
}
.validation-status.invalid {
  color: var(--theme-warning);
}

.instant-tooltip {
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  background: var(--color-background-dark);
  color: var(--color-text-light);
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 0.75rem;
  white-space: nowrap;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.1s;
  margin-top: 6px;
  z-index: 100;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.status-indicator:hover .instant-tooltip {
  opacity: 1;
}

.header-icon-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--theme-text-secondary);
  font-size: 14px;
  padding: 6px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.header-icon-btn:hover {
  background-color: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.sidebar-tabs {
  display: flex;
  background: var(--theme-bg-hover);
  padding: 4px;
  gap: 4px;
  border-bottom: 1px solid var(--theme-border);
}

.sidebar-tabs button {
  flex: 1;
  background: transparent;
  border: none;
  padding: 8px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  color: var(--theme-text-secondary);
  transition: all 0.2s;
  font-weight: 500;
}

.sidebar-tabs button:hover {
  background: rgba(0, 0, 0, 0.05);
  color: var(--theme-text-primary);
}

.sidebar-tabs button.active {
  background: var(--theme-bg-panel);
  color: var(--theme-primary);
  box-shadow: var(--shadow-sm);
}

.sidebar-content {
  flex: 1;
  overflow-y: auto;
  background: var(--theme-bg-panel);
}

.export-panel {
  padding: 10px;
}

.menu-panel {
  display: flex;
  padding: 8px;
}

.menu-btn {
  justify-content: flex-start !important;
  gap: 10px;
  width: 100%;
  padding: 10px !important;
  font-size: var(--font-size-sm);
  color: var(--theme-text-primary);
  border-radius: var(--radius-sm);
  transition: background-color 0.2s;
}
.menu-btn:hover {
  background-color: var(--theme-bg-hover);
}

.divider {
  height: 1px;
  background: var(--theme-border);
  margin: 12px 0;
}

.section-title {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--theme-text-secondary);
  margin: 0 0 4px 4px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
</style>
