<script setup lang="ts">
import { type StyleValue } from 'vue';
import Accordion from 'primevue/accordion';
import AccordionPanel from 'primevue/accordionpanel';
import AccordionHeader from 'primevue/accordionheader';
import AccordionContent from 'primevue/accordioncontent';
import ToggleSwitch from 'primevue/toggleswitch';
import BaseSelect from '../ui/BaseSelect.vue';
import BaseButton from '../ui/BaseButton.vue';
import BaseInput from '../ui/BaseInput.vue';
import ProjectManager from '../left-sidebar/ProjectManager.vue';
import NodePalette from '../left-sidebar/NodePalette.vue';
import ExecutionSettingsPanel from '../left-sidebar/ExecutionSettingsPanel.vue';
import DataInputPanel from '../panels/DataInputPanel.vue';
import type { NodeType, PaletteItemType } from '../../types';
import { exampleModels } from '../../config/nodeDefinitions';
import { useUiStore } from '../../stores/uiStore';
import { useExecutionStore } from '../../stores/executionStore';
import { storeToRefs } from 'pinia';

defineProps<{
  activeAccordionTabs: string[];
  projectName: string | null;
  pinnedGraphTitle: string | null;
  isGridEnabled: boolean;
  gridSize: number;
  showZoomControls: boolean;
  showDebugPanel: boolean;
}>();

defineEmits<{
  (e: 'toggle-left-sidebar'): void;
  (e: 'new-project'): void;
  (e: 'new-graph'): void;
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'update:isGridEnabled', value: boolean): void;
  (e: 'update:gridSize', value: number): void;
  (e: 'update:showZoomControls', value: boolean): void;
  (e: 'update:showDebugPanel', value: boolean): void;
  (e: 'toggle-code-panel'): void;
  (e: 'load-example', key: string): void;
  (e: 'open-export-modal', format: 'png' | 'jpg' | 'svg'): void;
  (e: 'export-json'): void;
  (e: 'connect-to-backend-url', url: string): void;
  (e: 'run-model'): void;
  (e: 'abort-run'): void;
  (e: 'generate-standalone'): void;
  (e: 'open-about-modal'): void;
  (e: 'toggle-dark-mode'): void;
}>();

const uiStore = useUiStore();
const executionStore = useExecutionStore();
const { isLeftSidebarOpen, canvasGridStyle, isCodePanelOpen, isDarkMode } = storeToRefs(uiStore);
const { isConnected, isConnecting, isExecuting } = storeToRefs(executionStore);

import { ref } from 'vue';

const navBackendUrl = ref('');

const gridStyleOptions = [
    { label: 'Dots', value: 'dots' },
    { label: 'Lines', value: 'lines' }
];

const updateCanvasGridStyle = (val: string) => {
    canvasGridStyle.value = val as 'dots' | 'lines';
};

const sidebarStyle = (isOpen: boolean): StyleValue => {
    if (!isOpen) {
        return {
            transform: 'scale(0)',
            opacity: 0,
            pointerEvents: 'none'
        };
    }
    return {
        transform: 'scale(1)',
        opacity: 1,
        pointerEvents: 'auto'
    };
};
</script>

<template>
    <aside class="floating-sidebar left glass-panel" :style="sidebarStyle(isLeftSidebarOpen)">
        <div class="sidebar-header" @click="$emit('toggle-left-sidebar')">
            <span class="sidebar-title">
                {{ pinnedGraphTitle ? `DoodleBUGS / ${pinnedGraphTitle}` : 'DoodleBUGS' }}
            </span>
            <div class="flex items-center gap-1 ml-auto">
                <button @click.stop="uiStore.toggleDarkMode()" class="theme-toggle-header" :title="isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode'">
                    <i :class="isDarkMode ? 'fas fa-sun' : 'fas fa-moon'"></i>
                </button>
                <div class="flex items-center">
                    <svg width="20" height="20" fill="none" viewBox="0 0 24 24" class="toggle-icon"><path fill="currentColor" fill-rule="evenodd" d="M10 7h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-8zM9 7H6a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h3zM4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" clip-rule="evenodd"></path></svg>
                </div>
            </div>
        </div>
        
        <div class="sidebar-content-scrollable">
             <Accordion :value="activeAccordionTabs" multiple class="sidebar-accordion">
                <AccordionPanel value="project">
                    <AccordionHeader><i class="fas fa-folder icon-12"></i> Project</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <ProjectManager @new-project="$emit('new-project')" @new-graph="$emit('new-graph')" />
                            <div class="divider"></div>
                            <div class="example-row">
                                <label class="example-label">Examples</label>
                                <BaseSelect :modelValue="''" :options="exampleModels.map(e => ({ label: e.name, value: e.key }))" @update:modelValue="$emit('load-example', $event)" placeholder="Load..." class="examples-dropdown" />
                            </div>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="palette">
                    <AccordionHeader><i class="fas fa-shapes icon-12"></i> Nodes</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <NodePalette @select-palette-item="(type: PaletteItemType) => { 
                                if (type === 'add-edge') {
                                    $emit('update:currentMode', 'add-edge');
                                } else {
                                    $emit('update:currentNodeType', type as NodeType); 
                                    $emit('update:currentMode', 'add-node'); 
                                }
                            }" />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="data">
                    <AccordionHeader><i class="fas fa-database icon-12"></i> Data</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <DataInputPanel :is-active="true" />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="settings">
                    <AccordionHeader><i class="fas fa-sliders-h icon-12"></i> Run Settings</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper">
                            <ExecutionSettingsPanel />
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="view">
                    <AccordionHeader><i class="fas fa-eye icon-12"></i> View Options</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <div class="menu-row">
                                <label>Canvas Grid</label>
                                <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="$emit('update:isGridEnabled', $event)" />
                            </div>
                            <div class="menu-row">
                                <label>Canvas Style</label>
                                <BaseSelect :modelValue="canvasGridStyle" :options="gridStyleOptions" class="w-24" @update:modelValue="updateCanvasGridStyle" />
                            </div>
                            <div class="menu-row">
                                <label>Canvas Size</label>
                                <input 
                                    type="number" 
                                    :value="gridSize" 
                                    @input="(e) => $emit('update:gridSize', Number((e.target as HTMLInputElement).value))"
                                    step="5" min="5" max="100"
                                    class="native-number-input"
                                />
                            </div>
                            <div class="divider"></div>
                            <div class="menu-row">
                                <label>Zoom Controls</label>
                                <ToggleSwitch :modelValue="showZoomControls" @update:modelValue="$emit('update:showZoomControls', $event)" />
                            </div>
                            <div class="menu-row">
                                <label>Debug Console</label>
                                <ToggleSwitch :modelValue="showDebugPanel" @update:modelValue="$emit('update:showDebugPanel', $event)" />
                            </div>
                            <div class="menu-row">
                                <label>Code Panel</label>
                                <ToggleSwitch :modelValue="isCodePanelOpen" @update:modelValue="$emit('toggle-code-panel')" />
                            </div>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="export">
                    <AccordionHeader><i class="fas fa-file-export icon-12"></i> Export</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'png')"><i class="fas fa-image"></i> PNG Image</BaseButton>
                            <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'jpg')"><i class="fas fa-file-image"></i> JPG Image</BaseButton>
                            <BaseButton type="ghost" class="menu-btn" @click="$emit('open-export-modal', 'svg')"><i class="fas fa-vector-square"></i> SVG Vector</BaseButton>
                            <div class="divider"></div>
                            <BaseButton type="ghost" class="menu-btn" @click="$emit('export-json')"><i class="fas fa-file-code"></i> JSON Data</BaseButton>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="connect">
                    <AccordionHeader><i class="fas fa-network-wired icon-12"></i> Connection</AccordionHeader>
                    <AccordionContent>
                        <div class="panel-content-wrapper relative">
                            <div class="experimental-badge">Experimental</div>
                            <div class="menu-panel flex-col gap-3 pt-4">
                                <div class="flex-col gap-2">
                                    <label class="text-xs font-bold">Backend URL</label>
                                    <BaseInput v-model="navBackendUrl" placeholder="http://localhost:8081" />
                                </div>
                                <div class="status-display" :class="{ connected: isConnected }">
                                    Status: {{ isConnected ? 'Connected' : 'Disconnected' }}
                                </div>
                                <BaseButton @click="$emit('connect-to-backend-url', navBackendUrl)" :disabled="isConnecting" type="primary" class="w-full justify-center">
                                    {{ isConnecting ? 'Connecting...' : 'Connect' }}
                                </BaseButton>
                                
                                <BaseButton @click="$emit('run-model')" type="primary" size="small" class="w-full justify-center" :disabled="!isConnected || isExecuting">
                                    <i v-if="isExecuting" class="fas fa-spinner fa-spin"></i>
                                    <i v-else class="fas fa-play"></i>
                                    <span class="ml-2">Run Model</span>
                                </BaseButton>
                                <BaseButton v-if="isExecuting" @click="$emit('abort-run')" type="danger" size="small" class="w-full justify-center">
                                    <i class="fas fa-stop"></i>
                                    <span class="ml-2">Abort</span>
                                </BaseButton>

                                <div class="divider"></div>
                                <BaseButton @click="$emit('generate-standalone')" type="ghost" class="menu-btn"><i class="fas fa-file-alt"></i> Generate Script</BaseButton>
                            </div>
                        </div>
                    </AccordionContent>
                </AccordionPanel>

                <AccordionPanel value="help">
                    <AccordionHeader><i class="fas fa-question-circle icon-12"></i> Help</AccordionHeader>
                    <AccordionContent>
                        <div class="menu-panel flex-col gap-3">
                            <BaseButton type="ghost" class="menu-btn" @click="$emit('open-about-modal')"><i class="fas fa-info-circle"></i> About</BaseButton>
                            <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" class="menu-btn ghost-btn">
                                <i class="fab fa-github"></i> Report Issue
                            </a>
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
  transition: transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1), opacity 0.3s ease;
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

.panel-content-wrapper.relative {
    position: relative;
}

.experimental-badge {
    position: absolute;
    top: 6px;
    right: 10px;
    background-color: var(--theme-warning);
    color: white;
    font-size: 9px;
    padding: 2px 6px;
    border-radius: 4px;
    font-weight: 600;
    text-transform: uppercase;
    pointer-events: none;
    opacity: 0.8;
}

:deep(.project-manager), :deep(.node-palette), :deep(.execution-settings-panel) {
    background: transparent;
    height: auto !important;
    overflow: visible !important;
    padding: 8px;
    border: none;
}

:deep(.data-input-panel) {
    height: 100%;
    padding: 8px;
    min-height: 300px;
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
.status-display {
    font-size: var(--font-size-xs);
    padding: 8px;
    border-radius: var(--radius-sm);
    background: rgba(16, 185, 129, 0.1);
    text-align: center;
    color: var(--theme-text-secondary);
    margin-bottom: 8px;
}
.status-display.connected {
    color: var(--theme-success);
    background: rgba(16, 185, 129, 0.15);
}
.native-number-input {
    width: 60px;
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--theme-border);
    border-radius: var(--radius-sm);
    background: var(--theme-bg-panel);
    color: var(--theme-text-primary);
    font-size: 0.85rem;
    text-align: right;
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
