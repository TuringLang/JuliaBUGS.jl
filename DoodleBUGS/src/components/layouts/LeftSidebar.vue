<script setup lang="ts">
import { type StyleValue } from 'vue'
import Accordion from 'primevue/accordion'
import AccordionPanel from 'primevue/accordionpanel'
import AccordionHeader from 'primevue/accordionheader'
import AccordionContent from 'primevue/accordioncontent'
import ToggleSwitch from 'primevue/toggleswitch'
import BaseSelect from '../ui/BaseSelect.vue'
import BaseButton from '../ui/BaseButton.vue'
import ProjectManager from '../left-sidebar/ProjectManager.vue'
import type { NodeType } from '../../types'
import { exampleModels } from '../../config/nodeDefinitions'
import { useUiStore } from '../../stores/uiStore'
import { storeToRefs } from 'pinia'

defineProps<{
  activeAccordionTabs: string[]
  projectName: string | null
  pinnedGraphTitle: string | null
  isGridEnabled: boolean
  gridSize: number
  showZoomControls: boolean
  showDebugPanel: boolean
  isCodePanelOpen: boolean
}>()

const emit = defineEmits<{
  (e: 'toggle-left-sidebar'): void
  (e: 'new-project'): void
  (e: 'new-graph'): void
  (e: 'update:currentMode', mode: string): void
  (e: 'update:currentNodeType', type: NodeType): void
  (e: 'update:isGridEnabled', value: boolean): void
  (e: 'update:gridSize', value: number): void
  (e: 'update:showZoomControls', value: boolean): void
  (e: 'update:showDebugPanel', value: boolean): void
  (e: 'toggle-code-panel'): void
  (e: 'load-example', key: string): void
  (e: 'open-about-modal'): void
  (e: 'open-faq-modal'): void
  (e: 'toggle-dark-mode'): void
  (e: 'share-graph', graphId: string): void
  (e: 'share-project-url', projectId: string): void
}>()

const uiStore = useUiStore()
const { isLeftSidebarOpen, canvasGridStyle, isDarkMode } = storeToRefs(uiStore)

const gridStyleOptions = [
  { label: 'Dots', value: 'dots' },
  { label: 'Lines', value: 'lines' },
]

const updateCanvasGridStyle = (val: string) => {
  canvasGridStyle.value = val as 'dots' | 'lines'
}

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

const handleGridSizeInput = (event: Event) => {
  const target = event.target as HTMLInputElement
  emit('update:gridSize', Number(target.value))
}
</script>

<template>
  <aside class="floating-sidebar left glass-panel" :style="sidebarStyle(isLeftSidebarOpen)">
    <div class="sidebar-header" @click="$emit('toggle-left-sidebar')">
      <span class="sidebar-title">
        {{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}
      </span>
      <div class="flex items-center ml-auto">
        <button
          @click.stop="uiStore.toggleDarkMode()"
          class="theme-toggle-header"
          :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'"
        >
          <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
        </button>
        <div class="flex items-center">
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
    </div>

    <div class="sidebar-content-scrollable">
      <Accordion :value="activeAccordionTabs" multiple class="sidebar-accordion">
        <AccordionPanel value="project">
          <AccordionHeader><i class="fas fa-folder icon-12"></i> Project</AccordionHeader>
          <AccordionContent>
            <div class="panel-content-wrapper">
              <ProjectManager
                @new-project="$emit('new-project')"
                @new-graph="$emit('new-graph')"
                @share-graph="(id: string) => $emit('share-graph', id)"
                @share-project-url="(id: string) => $emit('share-project-url', id)"
              />
              <div class="divider"></div>
              <div class="example-row">
                <label class="example-label">Examples</label>
                <BaseSelect
                  :modelValue="''"
                  :options="exampleModels.map((e) => ({ label: e.name, value: e.key }))"
                  @update:modelValue="$emit('load-example', $event)"
                  placeholder="Load..."
                  class="examples-dropdown"
                />
              </div>
            </div>
          </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="view">
          <AccordionHeader><i class="fas fa-eye icon-12"></i> View Options</AccordionHeader>
          <AccordionContent>
            <div class="menu-panel flex-col gap-3">
              <div class="menu-row">
                <label>Canvas Grid</label>
                <ToggleSwitch
                  :modelValue="isGridEnabled"
                  @update:modelValue="$emit('update:isGridEnabled', $event)"
                />
              </div>
              <div class="menu-row">
                <label>Canvas Style</label>
                <BaseSelect
                  :modelValue="canvasGridStyle"
                  :options="gridStyleOptions"
                  class="w-24"
                  @update:modelValue="updateCanvasGridStyle"
                />
              </div>
              <div class="menu-row">
                <label>Canvas Size</label>
                <input
                  type="number"
                  :value="gridSize"
                  @input="handleGridSizeInput"
                  step="5"
                  min="5"
                  max="100"
                  class="native-number-input"
                />
              </div>
              <div class="divider"></div>
              <div class="menu-row">
                <label>Zoom Controls</label>
                <ToggleSwitch
                  :modelValue="showZoomControls"
                  @update:modelValue="$emit('update:showZoomControls', $event)"
                />
              </div>
            </div>
          </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="help">
          <AccordionHeader><i class="fas fa-question-circle icon-12"></i> Help</AccordionHeader>
          <AccordionContent>
            <div class="menu-panel flex-col gap-1">
              <BaseButton type="ghost" class="menu-btn" @click="$emit('open-faq-modal')"
                ><i class="fas fa-question"></i> FAQ</BaseButton
              >
              <BaseButton type="ghost" class="menu-btn" @click="$emit('open-about-modal')"
                ><i class="fas fa-info-circle"></i> About</BaseButton
              >
              <a
                href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md"
                target="_blank"
                class="menu-btn ghost-btn"
              >
                <i class="fab fa-github"></i> Report Issue
              </a>
            </div>
          </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="devtools">
          <AccordionHeader><i class="fas fa-terminal icon-12"></i> Developer Tools</AccordionHeader>
          <AccordionContent>
            <div class="menu-panel flex-col gap-3">
              <div class="menu-row">
                <label>Debug Console</label>
                <ToggleSwitch
                  :modelValue="showDebugPanel"
                  @update:modelValue="$emit('update:showDebugPanel', $event)"
                />
              </div>
            </div>
          </AccordionContent>
        </AccordionPanel>
      </Accordion>
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

.floating-sidebar.left {
  left: 16px;
  width: 300px !important;
  transform-origin: top left;
}

@media (max-width: 768px) {
  .floating-sidebar.left {
    width: calc(100vw - 32px) !important;
  }

  .sidebar-content-scrollable {
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
  cursor: pointer;
}

.sidebar-title {
  font-weight: 600;
  font-size: var(--font-size-md);
}

.theme-toggle-header {
  background: transparent;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 4px;
  color: var(--theme-text-secondary);
  font-size: 0.85rem;
  transition: color 0.2s;
  border-radius: 4px;
}
.theme-toggle-header:hover {
  color: var(--theme-text-primary);
  background: var(--theme-bg-hover);
}

.toggle-icon {
  color: var(--theme-text-secondary);
}

.sidebar-content-scrollable {
  overflow-y: auto;
  flex: 1;
  background: var(--theme-bg-panel);
  min-height: 0;
}

:deep(.sidebar-accordion .p-accordion-header-link) {
  padding: 0.75rem 1rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--theme-text-primary);
  background: transparent;
  border: none;
  border-bottom: 1px solid var(--theme-border);
  outline: none;
  justify-content: flex-start;
}

:deep(.sidebar-accordion .p-accordion-header:not(.p-disabled) .p-accordion-header-link:focus) {
  box-shadow: none;
  background: var(--theme-bg-hover);
}

:deep(.sidebar-accordion .p-accordion-content-content) {
  padding: 0;
  background: transparent;
}

:deep(.sidebar-accordion .p-accordion-panel) {
  border: none;
}

:deep(.p-inputtext) {
  font-size: 12px !important;
  padding: 0.4rem 0.5rem !important;
}

:deep(.p-inputtext::placeholder) {
  font-size: 12px !important;
}

:deep(.p-select-label) {
  font-size: 12px !important;
  padding: 0.4rem 0.5rem !important;
}

:deep(.p-select-option) {
  font-size: 12px !important;
}

:deep(.p-inputnumber-input) {
  font-size: 12px !important;
  padding: 0.4rem 0.5rem !important;
}

:deep(.p-select-dropdown) {
  width: 2rem;
}

.icon-12 {
  font-size: 12px;
  width: 20px;
  text-align: center;
  margin-right: 8px;
  color: var(--theme-text-secondary);
}

.panel-content-wrapper {
  padding: 4px;
  background: var(--theme-bg-panel);
}

:deep(.project-manager) {
  background: transparent;
  height: auto !important;
  overflow: visible !important;
  padding: 8px;
  border: none;
}

.menu-panel {
  display: flex;
  padding: 8px;
}
.menu-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: var(--font-size-sm);
  color: var(--theme-text-primary);
  margin-bottom: 8px;
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
.ghost-btn {
  color: var(--theme-text-secondary);
  text-decoration: none;
  display: flex;
  align-items: center;
  border-radius: var(--radius-sm);
  padding: 8px;
}
.ghost-btn:hover {
  background: var(--theme-bg-hover);
  color: var(--theme-text-primary);
}
.divider {
  height: 1px;
  background: var(--theme-border);
  margin: 12px 0;
}
.native-number-input {
  width: 60px;
  padding: 0.25rem 0.5rem;
  border: 1px solid var(--theme-border);
  border-radius: var(--radius-sm);
  background: var(--theme-bg-panel);
  color: var(--theme-text-primary);
  font-size: 0.85rem;
  text-align: left;
}
.native-number-input:focus {
  outline: none;
  border-color: var(--theme-primary);
}

.example-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 8px 8px 8px;
  gap: 10px;
}

.example-label {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--theme-text-secondary);
  white-space: nowrap;
}

.examples-dropdown {
  width: 100% !important;
  flex-grow: 1;
}
</style>
