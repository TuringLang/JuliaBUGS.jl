<script setup lang="ts">
import { type StyleValue } from 'vue'
import { storeToRefs } from 'pinia'
import Tooltip from 'primevue/tooltip'
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
  isFullScreen?: boolean
  showFullscreenToggle?: boolean
}>()

const emit = defineEmits<{
  (e: 'toggle-right-sidebar'): void
  (e: 'update-element', element: GraphElement): void
  (e: 'delete-element', elementId: string): void
  (e: 'show-validation-issues'): void
  (e: 'open-script-settings'): void
  (e: 'download-script'): void
  (e: 'download-stan'): void
  (e: 'download-stan-script'): void
  (e: 'download-stan-data'): void
  (e: 'download-stan-inits'): void
  (e: 'generate-script'): void
  (e: 'share'): void
  (e: 'open-export-modal', format: 'png' | 'jpg' | 'svg'): void
  (e: 'export-json'): void
  (e: 'header-drag-start', event: MouseEvent | TouchEvent): void
  (e: 'toggle-fullscreen'): void
}>()

const uiStore = useUiStore()
const { isRightSidebarOpen, activeRightTab } = storeToRefs(uiStore)

const vTooltip = Tooltip

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
  <aside
    class="db-floating-sidebar db-right db-glass-panel"
    :style="sidebarStyle(isRightSidebarOpen)"
  >
    <div
      class="db-sidebar-header"
      @mousedown="handleHeaderMouseDown"
      @touchstart="handleHeaderMouseDown"
      @click="handleHeaderClick"
      :style="{ cursor: enableDrag ? 'move' : 'pointer' }"
    >
      <span class="db-sidebar-title">Inspector</span>

      <div class="db-flex db-items-center ml-auto" @click.stop @mousedown.stop @touchstart.stop>
        <div
          v-tooltip.top="{
            value: isModelValid ? 'Model is valid' : 'Model has validation issues',
            showDelay: 0,
            hideDelay: 0,
          }"
          class="db-status-indicator db-validation-status"
          @click="$emit('show-validation-issues')"
          :class="isModelValid ? 'db-valid' : 'db-invalid'"
        >
          <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
        </div>

        <button
          v-tooltip.top="{ value: 'Share via URL', showDelay: 0, hideDelay: 0 }"
          class="db-header-icon-btn"
          @click="$emit('share')"
        >
          <i class="fas fa-share-alt"></i>
        </button>

        <!-- Maximize / Exit Fullscreen Button -->
        <button
          v-if="showFullscreenToggle"
          v-tooltip.top="{
            value: isFullScreen ? 'Exit Full Screen' : 'Maximize Graph',
            showDelay: 0,
            hideDelay: 0,
          }"
          class="db-header-icon-btn"
          :class="{ 'db-exit-btn': isFullScreen }"
          @click="$emit('toggle-fullscreen')"
        >
          <svg
            v-if="!isFullScreen"
            viewBox="0 0 24 24"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            style="width: 16px; height: 16px"
          >
            <path
              d="M18 20.75H12C11.8011 20.75 11.6103 20.671 11.4697 20.5303C11.329 20.3897 11.25 20.1989 11.25 20C11.25 19.8011 11.329 19.6103 11.4697 19.4697C11.6103 19.329 11.8011 19.25 12 19.25H18C18.3315 19.25 18.6495 19.1183 18.8839 18.8839C19.1183 18.6495 19.25 18.3315 19.25 18V6C19.25 5.66848 19.1183 5.35054 18.8839 5.11612C18.6495 4.8817 18.3315 4.75 18 4.75H6C5.66848 4.75 5.35054 4.8817 5.11612 5.11612C4.8817 5.35054 4.75 5.66848 4.75 6V12C4.75 12.1989 4.67098 12.3897 4.53033 12.5303C4.38968 12.671 4.19891 12.75 4 12.75C3.80109 12.75 3.61032 12.671 3.46967 12.5303C3.32902 12.3897 3.25 12.1989 3.25 12V6C3.25 5.27065 3.53973 4.57118 4.05546 4.05546C4.57118 3.53973 5.27065 3.25 6 3.25H18C18.7293 3.25 19.4288 3.53973 19.9445 4.05546C20.4603 4.57118 20.75 5.27065 20.75 6V18C20.75 18.7293 20.4603 19.4288 19.9445 19.9445C19.4288 20.4603 18.7293 20.75 18 20.75Z"
              fill="currentColor"
            />
            <path
              d="M16 12.75C15.8019 12.7474 15.6126 12.6676 15.4725 12.5275C15.3324 12.3874 15.2526 12.1981 15.25 12V8.75H12C11.8011 8.75 11.6103 8.67098 11.4697 8.53033C11.329 8.38968 11.25 8.19891 11.25 8C11.25 7.80109 11.329 7.61032 11.4697 7.46967C11.6103 7.32902 11.8011 7.25 12 7.25H16C16.1981 7.25259 16.3874 7.33244 16.5275 7.47253C16.6676 7.61263 16.7474 7.80189 16.75 8V12C16.7474 12.1981 16.6676 12.3874 16.5275 12.5275C16.3874 12.6676 16.1981 12.7474 16 12.75Z"
              fill="currentColor"
            />
            <path
              d="M11.5 13.25C11.3071 13.2352 11.1276 13.1455 11 13C10.877 12.8625 10.809 12.6845 10.809 12.5C10.809 12.3155 10.877 12.1375 11 12L15.5 7.5C15.6422 7.36752 15.8302 7.29539 16.0245 7.29882C16.2188 7.30225 16.4042 7.38096 16.5416 7.51838C16.679 7.65579 16.7578 7.84117 16.7612 8.03548C16.7646 8.22978 16.6925 8.41782 16.56 8.56L12 13C11.8724 13.1455 11.6929 13.2352 11.5 13.25Z"
              fill="currentColor"
            />
            <path
              d="M8 20.75H5C4.53668 20.7474 4.09309 20.5622 3.76546 20.2345C3.43784 19.9069 3.25263 19.4633 3.25 19V16C3.25263 15.5367 3.43784 15.0931 3.76546 14.7655C4.09309 14.4378 4.53668 14.2526 5 14.25H8C8.46332 14.2526 8.90691 14.4378 9.23454 14.7655C9.56216 15.0931 9.74738 15.5367 9.75 16V19C9.74738 19.4633 9.56216 19.9069 9.23454 20.2345C8.90691 20.5622 8.46332 20.7474 8 20.75ZM5 15.75C4.9337 15.75 4.87011 15.7763 4.82322 15.8232C4.77634 15.8701 4.75 15.9337 4.75 16V19C4.75 19.0663 4.77634 19.1299 4.82322 19.1768C4.87011 19.2237 4.9337 19.25 5 19.25H8C8.0663 19.25 8.12989 19.2237 8.17678 19.1768C8.22366 19.1299 8.25 19.0663 8.25 19V16C8.25 15.9337 8.22366 15.8701 8.17678 15.8232C8.12989 15.7763 8.0663 15.75 8 15.75H5Z"
              fill="currentColor"
            />
          </svg>
          <i v-else class="pi pi-window-minimize"></i>
        </button>
      </div>

      <div
        v-tooltip.top="{ value: 'Collapse Sidebar', showDelay: 0, hideDelay: 0 }"
        class="pointer-events-auto db-flex db-items-center ml-2"
        @mousedown.stop
        @touchstart.stop
        @click.stop="$emit('toggle-right-sidebar')"
        style="cursor: pointer"
      >
        <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="db-toggle-icon">
          <path
            fill="currentColor"
            fill-rule="evenodd"
            d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"
            clip-rule="evenodd"
          ></path>
        </svg>
      </div>
    </div>

    <div class="db-sidebar-tabs">
      <button
        :class="{ 'db-active': activeRightTab === 'properties' }"
        @click="uiStore.setActiveRightTab('properties')"
      >
        Props
      </button>
      <button
        :class="{ 'db-active': activeRightTab === 'script' }"
        @click="uiStore.setActiveRightTab('script')"
      >
        Script
      </button>
      <button
        :class="{ 'db-active': activeRightTab === 'export' }"
        @click="uiStore.setActiveRightTab('export')"
      >
        Export
      </button>
    </div>

    <div class="db-sidebar-content">
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
        @download-stan-script="$emit('download-stan-script')"
        @download-stan-data="$emit('download-stan-data')"
        @download-stan-inits="$emit('download-stan-inits')"
        @generate="$emit('generate-script')"
      />

      <div v-show="activeRightTab === 'export'" class="db-export-panel">
        <div class="db-menu-panel db-flex-col db-gap-3">
          <h5 class="db-section-title">Image Export</h5>
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('open-export-modal', 'png')"
            ><i class="fas fa-image"></i> PNG Image</BaseButton
          >
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('open-export-modal', 'jpg')"
            ><i class="fas fa-file-image"></i> JPG Image</BaseButton
          >
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('open-export-modal', 'svg')"
            ><i class="fas fa-draw-polygon"></i> SVG Vector</BaseButton
          >

          <div class="db-divider"></div>

          <h5 class="db-section-title">Model Export</h5>
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('export-json')"
            ><i class="fas fa-file-code"></i>Export Graph, Data & Inits as JSON</BaseButton
          >
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('download-stan')"
            ><i class="fas fa-file-alt"></i>Download Stan Model (.stan)</BaseButton
          >
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('download-stan-data')"
            ><i class="fas fa-database"></i>Download Stan Data (data.json)</BaseButton
          >
          <BaseButton type="ghost" class="db-menu-btn" @click="$emit('download-stan-inits')"
            ><i class="fas fa-play-circle"></i>Download Stan Inits (inits.json)</BaseButton
          >
        </div>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.db-floating-sidebar {
  position: absolute;
  top: 16px;
  height: auto;
  max-height: calc(var(--db-container-height, 100dvh) - 32px);
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

.db-floating-sidebar.db-right {
  right: 16px;
  width: 320px;
  transform-origin: top right;
}

@media (max-width: 768px) {
  .db-floating-sidebar.db-right {
    width: calc(100vw - 32px) !important;
  }
  .db-sidebar-tabs button {
    padding: 8px 4px;
    font-size: 0.8rem;
  }
  .db-sidebar-content {
    padding-bottom: 80px; /* Space for floating toolbar on mobile */
  }
  .db-sidebar-header {
    padding: 8px 12px;
  }
  .db-sidebar-title {
    font-size: 0.85rem;
  }
  .db-header-icon-btn {
    font-size: 12px;
    padding: 4px;
  }
  .db-status-indicator {
    width: 20px;
    height: 20px;
  }
  .db-validation-status {
    font-size: 0.9em;
    margin: 0 2px;
  }
}

.db-sidebar-header {
  padding: 12px 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--theme-border);
  background: var(--theme-bg-panel-transparent);
  color: var(--theme-text-primary);
  flex-shrink: 0;
  gap: 8px;
  flex-wrap: wrap;
}

.db-sidebar-title {
  font-weight: 600;
  font-size: var(--font-size-md);
  user-select: none;
}

.db-toggle-icon {
  color: var(--theme-text-secondary);
}

.db-status-indicator {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  cursor: help;
}

.db-validation-status {
  font-size: 1.1em;
  margin: 0 5px;
}
.db-validation-status.db-valid {
  color: var(--theme-success);
}
.db-validation-status.db-invalid {
  color: var(--theme-warning);
}

.db-header-icon-btn {
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

.db-header-icon-btn:hover {
  background-color: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}

.db-exit-btn {
  margin-left: 4px;
  color: var(--theme-text-primary);
}

.db-exit-btn:hover {
  background-color: var(--theme-bg-active);
  color: var(--theme-primary);
}

.db-collapsed-share-btn {
  width: 24px;
  height: 24px;
  padding: 0;
}

.db-sidebar-tabs {
  display: flex;
  background: var(--theme-bg-hover);
  padding: 4px;
  gap: 4px;
  border-bottom: 1px solid var(--theme-border);
}

.db-sidebar-tabs button {
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

.db-sidebar-tabs button:hover {
  background: rgba(0, 0, 0, 0.05);
  color: var(--theme-text-primary);
}

.db-sidebar-tabs button.db-active {
  background: var(--theme-bg-panel);
  color: var(--theme-primary);
  box-shadow: var(--shadow-sm);
}

.db-sidebar-content {
  flex: 1;
  overflow-y: auto;
  background: var(--theme-bg-panel);
}

.db-export-panel {
  padding: 10px;
}

.db-menu-panel {
  display: flex;
  padding: 8px;
}

.db-menu-btn {
  justify-content: flex-start !important;
  gap: 10px;
  width: 100%;
  padding: 10px !important;
  font-size: var(--font-size-sm);
  color: var(--theme-text-primary);
  border-radius: var(--radius-sm);
  transition: background-color 0.2s;
}
.db-menu-btn:hover {
  background-color: var(--theme-bg-hover);
}

.db-divider {
  height: 1px;
  background: var(--theme-border);
  margin: 12px 0;
}

.db-section-title {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--theme-text-secondary);
  margin: 0 0 4px 4px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.db-glass-panel {
  background: var(--theme-bg-panel-transparent, rgba(255, 255, 255, 0.95));
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--theme-border);
  box-shadow: var(--shadow-floating);
}
</style>
