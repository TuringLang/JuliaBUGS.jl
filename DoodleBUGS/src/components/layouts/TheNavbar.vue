<script setup lang="ts">
import { ref } from 'vue';
import { storeToRefs } from 'pinia';
import Toolbar from 'primevue/toolbar';
import Button from 'primevue/button';
import Drawer from 'primevue/drawer';
import ToggleSwitch from 'primevue/toggleswitch';
import InputNumber from 'primevue/inputnumber';
import Accordion from 'primevue/accordion';
import AccordionPanel from 'primevue/accordionpanel';
import AccordionHeader from 'primevue/accordionheader';
import AccordionContent from 'primevue/accordioncontent';
import type { NodeType } from '../../types';
import BaseButton from '../ui/BaseButton.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseSelect from '../ui/BaseSelect.vue';
import DropdownMenu from '../common/DropdownMenu.vue';
import { nodeDefinitions, exampleModels } from '../../config/nodeDefinitions';
import { useExecutionStore } from '../../stores/executionStore';
import { useUiStore } from '../../stores/uiStore';

defineProps<{
  projectName: string | null;
  activeGraphName: string | null;
  isGridEnabled: boolean;
  gridSize: number;
  currentMode: string;
  currentNodeType: NodeType;
  isLeftSidebarOpen: boolean;
  isRightSidebarOpen: boolean;
  isModelValid: boolean;
  showDebugPanel: boolean;
  showZoomControls: boolean;
  isMultiCanvasView?: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:isGridEnabled', value: boolean): void;
  (e: 'update:gridSize', value: number): void;
  (e: 'update:currentMode', mode: string): void;
  (e: 'update:currentNodeType', type: NodeType): void;
  (e: 'new-project'): void;
  (e: 'new-graph'): void;
  (e: 'toggle-left-sidebar'): void;
  (e: 'toggle-right-sidebar'): void;
  (e: 'open-about-modal'): void;
  (e: 'open-export-modal', format: 'png' | 'jpg' | 'svg'): void;
  (e: 'export-json'): void;
  (e: 'apply-layout', layoutName: string): void;
  (e: 'load-example', exampleKey: string): void;
  (e: 'validate-model'): void;
  (e: 'show-validation-issues'): void;
  (e: 'connect-to-backend-url', url: string): void;
  (e: 'run-model'): void;
  (e: 'abort-run'): void;
  (e: 'generate-standalone'): void;
  (e: 'update:showDebugPanel', value: boolean): void;
  (e: 'update:showZoomControls', value: boolean): void;
  (e: 'toggle-canvas-view'): void;
  (e: 'save-current-graph'): void;
}>();

const executionStore = useExecutionStore();
const uiStore = useUiStore();
const { isConnected, isExecuting, isConnecting, backendUrl } = storeToRefs(executionStore);
const { workspaceGridStyle, canvasGridStyle, workspaceGridSize, isWorkspaceGridEnabled } = storeToRefs(uiStore);

const navBackendUrl = ref(backendUrl.value || 'http://localhost:8081');
const cloneCmd = 'git clone https://github.com/TuringLang/JuliaBUGS.jl.git';
const instantiateCmd = 'julia --project=DoodleBUGS/runtime -e "using Pkg; Pkg.instantiate()"';
const startCmd = 'julia --project=DoodleBUGS/runtime DoodleBUGS/runtime/server.jl';

// Copy helpers
const copiedBackendUrl = ref(false);
const copiedCloneCmd = ref(false);
const copiedInstantiateCmd = ref(false);
const copiedStartCmd = ref(false);

function copyWithFeedback(text: string, flag: typeof copiedBackendUrl) {
  navigator.clipboard.writeText(text).then(() => {
    flag.value = true;
    setTimeout(() => (flag.value = false), 1500);
  }).catch(err => console.error('Clipboard copy failed:', err));
}

const copyBackendUrl = () => copyWithFeedback(navBackendUrl.value, copiedBackendUrl);
const copyCloneCmd = () => copyWithFeedback(cloneCmd, copiedCloneCmd);
const copyInstantiateCmd = () => copyWithFeedback(instantiateCmd, copiedInstantiateCmd);
const copyStartCmd = () => copyWithFeedback(startCmd, copiedStartCmd);

const setAddNodeType = (type: NodeType) => {
  emit('update:currentNodeType', type);
  emit('update:currentMode', 'add-node');
};

const updateGridEnabled = (val: boolean) => emit('update:isGridEnabled', val);
const updateGridSize = (val: number | null) => {
    if (val !== null) emit('update:gridSize', val);
};
const updateWorkspaceGridSize = (val: number | null) => {
    if (val !== null) workspaceGridSize.value = val;
};
const updateShowZoomControls = (val: boolean) => emit('update:showZoomControls', val);
const updateShowDebugPanel = (val: boolean) => emit('update:showDebugPanel', val);

// Dark Mode
const isDarkMode = ref(localStorage.getItem('darkMode') === 'true');

const applyDarkMode = () => {
    const element = document.querySelector('html');
    if (isDarkMode.value) {
        element?.classList.add('dark-mode');
    } else {
        element?.classList.remove('dark-mode');
    }
};

// Apply on load
applyDarkMode();

const toggleDarkMode = () => {
    isDarkMode.value = !isDarkMode.value;
    localStorage.setItem('darkMode', String(isDarkMode.value));
    applyDarkMode();
};

// Mobile Menu
const mobileMenuOpen = ref(false);

const gridStyleOptions = [
    { label: 'Dots', value: 'dots' },
    { label: 'Lines', value: 'lines' }
];
</script>

<template>
  <Toolbar class="navbar-toolbar">
    <template #start>
      <div class="flex items-center gap-2">
        <span class="text-lg font-bold mr-3">DoodleBUGS</span>
        
        <!-- Desktop Menu -->
        <div class="desktop-menu flex gap-1">
          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Project</BaseButton>
            </template>
            <template #content>
              <a href="#" @click.prevent="emit('new-project')">New Project...</a>
              <a href="#" @click.prevent="emit('new-graph')">New Graph...</a>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Export</BaseButton>
            </template>
            <template #content>
              <a href="#" @click.prevent="emit('open-export-modal', 'png')">as PNG...</a>
              <a href="#" @click.prevent="emit('open-export-modal', 'jpg')">as JPG...</a>
              <a href="#" @click.prevent="emit('open-export-modal', 'svg')">as SVG...</a>
              <div class="dropdown-divider"></div>
              <a href="#" @click.prevent="emit('export-json')">as JSON</a>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Add</BaseButton>
            </template>
            <template #content>
              <div class="dropdown-section-title">Nodes</div>
              <a v-for="nodeDef in nodeDefinitions" :key="nodeDef.nodeType" href="#"
                @click.prevent="setAddNodeType(nodeDef.nodeType)">
                {{ nodeDef.label }}
              </a>
              <div class="dropdown-divider"></div>
              <a href="#" @click.prevent="emit('update:currentMode', 'add-edge')">Add Edge</a>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Layout</BaseButton>
            </template>
            <template #content>
              <a href="#" @click.prevent="emit('apply-layout', 'dagre')">Dagre (Hierarchical)</a>
              <a href="#" @click.prevent="emit('apply-layout', 'fcose')">fCoSE (Force-Directed)</a>
              <a href="#" @click.prevent="emit('apply-layout', 'cola')">Cola (Physics Simulation)</a>
              <a href="#" @click.prevent="emit('apply-layout', 'klay')">KLay (Layered)</a>
              <a href="#" @click.prevent="emit('apply-layout', 'preset')">Reset to Preset</a>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">View</BaseButton>
            </template>
            <template #content>
              <div class="view-options" @click.stop>
                <div class="view-option-row">
                  <label for="multi-canvas" class="view-label">Multi-Canvas View</label>
                  <ToggleSwitch :modelValue="isMultiCanvasView" @update:modelValue="emit('toggle-canvas-view')" inputId="multi-canvas" />
                </div>
                
                <div class="dropdown-divider"></div>

                <div class="view-option-row">
                  <label for="show-ws-grid" class="view-label">Workspace Grid</label>
                  <ToggleSwitch v-model="isWorkspaceGridEnabled" inputId="show-ws-grid" />
                </div>
                
                <div class="view-option-row grid-settings-row">
                  <label for="ws-grid-style" class="view-label">Workspace Style</label>
                  <div class="flex gap-2 items-center justify-end settings-controls">
                    <BaseSelect 
                        id="ws-grid-style"
                        v-model="workspaceGridStyle"
                        :options="gridStyleOptions"
                        class="grid-style-select"
                    />
                    <InputNumber 
                        :modelValue="workspaceGridSize" 
                        @update:modelValue="updateWorkspaceGridSize" 
                        showButtons 
                        buttonLayout="stacked" 
                        :step="10" 
                        :min="10" 
                        :max="200"
                        decrementButtonIcon="pi pi-angle-down"
                        incrementButtonIcon="pi pi-angle-up"
                        class="grid-size-input"
                        :allowEmpty="false"
                    />
                  </div>
                </div>

                <div class="view-option-row">
                  <label for="show-canvas-grid" class="view-label">Canvas Grid</label>
                  <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="updateGridEnabled" inputId="show-canvas-grid" />
                </div>

                <div class="view-option-row grid-settings-row">
                  <label for="canvas-grid-style" class="view-label">Canvas Style</label>
                  <div class="flex gap-2 items-center justify-end settings-controls">
                    <BaseSelect 
                        id="canvas-grid-style"
                        v-model="canvasGridStyle"
                        :options="gridStyleOptions"
                        class="grid-style-select"
                    />
                    <InputNumber 
                        :modelValue="gridSize" 
                        @update:modelValue="updateGridSize" 
                        showButtons 
                        buttonLayout="stacked" 
                        :step="5" 
                        :min="5" 
                        :max="100" 
                        decrementButtonIcon="pi pi-angle-down"
                        incrementButtonIcon="pi pi-angle-up"
                        class="grid-size-input"
                        :allowEmpty="false"
                    />
                  </div>
                </div>
                
                <div class="dropdown-divider"></div>
                
                <div class="view-option-row">
                  <label for="show-zoom" class="view-label">Zoom Controls</label>
                  <ToggleSwitch :modelValue="showZoomControls" @update:modelValue="updateShowZoomControls" inputId="show-zoom" />
                </div>
                
                <div class="view-option-row">
                  <label for="show-debug" class="view-label">Debug Console</label>
                  <ToggleSwitch :modelValue="showDebugPanel" @update:modelValue="updateShowDebugPanel" inputId="show-debug" />
                </div>
              </div>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Examples</BaseButton>
            </template>
            <template #content>
               <a v-for="example in exampleModels" :key="example.key" href="#" @click.prevent="emit('load-example', example.key)">
                {{ example.name }}
              </a>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Connection</BaseButton>
            </template>
            <template #content>
              <div class="execution-dropdown" @click.stop>
                <div class="dropdown-section-title">Backend</div>
                <div class="dropdown-input-group">
                  <label for="backend-url-nav">URL:</label>
                  <BaseInput id="backend-url-nav" v-model="navBackendUrl" placeholder="http://localhost:8081" class="backend-url-input" />
                  <BaseButton size="small" type="secondary" class="copy-btn" title="Copy URL" @click.stop="copyBackendUrl">
                    <i v-if="copiedBackendUrl" class="fas fa-check"></i>
                    <i v-else class="fas fa-copy"></i>
                  </BaseButton>
                </div>
                <div class="dropdown-actions">
                  <span class="connection-status" :class="{ connected: isConnected }">
                    <strong>{{ isConnected ? 'Connected' : 'Disconnected' }}</strong>
                  </span>
                  <BaseButton @click="emit('connect-to-backend-url', navBackendUrl)" :disabled="isConnecting" size="small" type="primary">
                    <span v-if="isConnecting">Connecting...</span>
                    <span v-else>Connect</span>
                  </BaseButton>
                </div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-section-title">Setup Instructions</div>
                <div class="setup-instructions">
                  <div class="instruction-item">
                    <span class="instruction-label">1. Clone repository:</span>
                    <div class="instruction-command">
                      <code>{{ cloneCmd }}</code>
                      <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyCloneCmd">
                        <i v-if="copiedCloneCmd" class="fas fa-check"></i>
                        <i v-else class="fas fa-copy"></i>
                      </BaseButton>
                    </div>
                  </div>
                  <div class="instruction-item">
                    <span class="instruction-label">2. First time only (instantiate deps):</span>
                    <div class="instruction-command">
                      <code>{{ instantiateCmd }}</code>
                      <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyInstantiateCmd">
                        <i v-if="copiedInstantiateCmd" class="fas fa-check"></i>
                        <i v-else class="fas fa-copy"></i>
                      </BaseButton>
                    </div>
                  </div>
                  <div class="instruction-item">
                    <span class="instruction-label">3. Start backend:</span>
                    <div class="instruction-command">
                      <code>{{ startCmd }}</code>
                      <BaseButton size="small" type="secondary" class="copy-btn-inline" title="Copy command" @click.stop="copyStartCmd">
                        <i v-if="copiedStartCmd" class="fas fa-check"></i>
                        <i v-else class="fas fa-copy"></i>
                      </BaseButton>
                    </div>
                  </div>
                </div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-section-title">Standalone</div>
                <a href="#" @click.prevent="emit('generate-standalone')">Generate Standalone Julia Script</a>
              </div>
            </template>
          </DropdownMenu>

          <DropdownMenu>
            <template #trigger>
              <BaseButton type="ghost" size="small">Help</BaseButton>
            </template>
            <template #content>
              <a href="#" @click.prevent="emit('open-about-modal')">About DoodleBUGS</a>
              <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" rel="noopener noreferrer" class="report-issue-link">
                 Report an Issue
                 <i class="fas fa-external-link-alt external-link-icon"></i>
              </a>
            </template>
          </DropdownMenu>
        </div>
      </div>
    </template>

    <template #center>
      <div class="desktop-actions flex items-center gap-2">
        <div class="status-indicator backend-status" 
             :class="{ 'connected': isConnected, 'disconnected': !isConnected }">
            <i class="fas fa-circle"></i>
            <div class="instant-tooltip">{{ isConnected ? 'Backend Connected' : 'Backend Disconnected' }}</div>
        </div>
        
        <div class="status-indicator validation-status"
            @click="emit('show-validation-issues')"
            :class="isModelValid ? 'valid' : 'invalid'">
            <i :class="isModelValid ? 'fas fa-check-circle' : 'fas fa-exclamation-triangle'"></i>
            <div class="instant-tooltip">{{ isModelValid ? 'Model Valid' : 'Validation Errors Found' }}</div>
        </div>

        <BaseButton @click="emit('run-model')" type="primary" size="small" title="Run Model on Backend" :disabled="!isConnected || isExecuting">
            <i v-if="isExecuting" class="fas fa-spinner fa-spin"></i>
            <i v-else class="fas fa-play"></i>
            Run
        </BaseButton>
        <BaseButton v-if="isExecuting" @click="emit('abort-run')" type="danger" size="small" title="Abort current run">
            <i class="fas fa-stop"></i>
            Abort
        </BaseButton>
      </div>
    </template>

    <template #end>
      <div class="flex items-center gap-1">
        <Button 
            :icon="isDarkMode ? 'pi pi-sun' : 'pi pi-moon'" 
            @click="toggleDarkMode" 
            text 
            rounded 
            aria-label="Toggle Dark Mode" 
            size="small"
        />
        
        <Button @click="emit('toggle-left-sidebar')" :class="{ 'p-button-outlined': isLeftSidebarOpen }" icon="pi pi-align-left" text rounded size="small" title="Toggle Left Sidebar" />
        <Button @click="emit('toggle-right-sidebar')" :class="{ 'p-button-outlined': isRightSidebarOpen }" icon="pi pi-align-right" text rounded size="small" title="Toggle Right Sidebar" />
        
        <Button icon="pi pi-bars" class="mobile-toggle" @click="mobileMenuOpen = true" text rounded size="small" />
      </div>
    </template>
  </Toolbar>

  <Drawer v-model:visible="mobileMenuOpen" header="Menu" position="right" class="w-80">
    <Accordion :multiple="true" :value="['run', 'view']">
        <AccordionPanel value="run">
            <AccordionHeader>Run</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton @click="emit('run-model'); mobileMenuOpen = false" type="primary" :disabled="!isConnected || isExecuting" class="w-full justify-center py-3">
                        <i v-if="isExecuting" class="fas fa-spinner fa-spin mr-2"></i>
                        <i v-else class="fas fa-play mr-2"></i>
                        Run Model
                    </BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>
        
        <AccordionPanel value="view">
            <AccordionHeader>View Settings</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-5 pt-3 mobile-view-options">
                    <div class="mobile-option-row">
                        <label for="mobile-multi-canvas">Multi-Canvas</label>
                        <ToggleSwitch :modelValue="isMultiCanvasView" @update:modelValue="emit('toggle-canvas-view')" inputId="mobile-multi-canvas" />
                    </div>
                    <div class="mobile-option-row">
                        <label for="mobile-show-ws-grid">Workspace Grid</label>
                        <ToggleSwitch v-model="isWorkspaceGridEnabled" inputId="mobile-show-ws-grid" />
                    </div>
                    <div class="mobile-option-row">
                        <label>Workspace Style</label>
                        <div class="flex gap-3 items-center">
                            <BaseSelect 
                                v-model="workspaceGridStyle"
                                :options="gridStyleOptions"
                                class="w-24"
                            />
                            <InputNumber 
                                :modelValue="workspaceGridSize" 
                                @update:modelValue="updateWorkspaceGridSize" 
                                showButtons 
                                buttonLayout="stacked" 
                                :step="10" 
                                :min="10" 
                                :max="200"
                                decrementButtonIcon="pi pi-angle-down"
                                incrementButtonIcon="pi pi-angle-up"
                                class="grid-size-input"
                                :allowEmpty="false"
                            />
                        </div>
                    </div>
                    <div class="mobile-option-row">
                        <label for="mobile-show-canvas-grid">Canvas Grid</label>
                        <ToggleSwitch :modelValue="isGridEnabled" @update:modelValue="updateGridEnabled" inputId="mobile-show-canvas-grid" />
                    </div>
                    <div class="mobile-option-row">
                        <label>Canvas Style</label>
                        <div class="flex gap-3 items-center">
                            <BaseSelect 
                                v-model="canvasGridStyle"
                                :options="gridStyleOptions"
                                class="w-24"
                            />
                            <InputNumber 
                                :modelValue="gridSize" 
                                @update:modelValue="updateGridSize" 
                                showButtons 
                                buttonLayout="stacked" 
                                :step="5" 
                                :min="5" 
                                :max="100" 
                                decrementButtonIcon="pi pi-angle-down"
                                incrementButtonIcon="pi pi-angle-up"
                                class="grid-size-input"
                                :allowEmpty="false"
                            />
                        </div>
                    </div>
                    <div class="mobile-option-row">
                        <label for="mobile-show-zoom">Zoom Controls</label>
                        <ToggleSwitch :modelValue="showZoomControls" @update:modelValue="updateShowZoomControls" inputId="mobile-show-zoom" />
                    </div>
                    <div class="mobile-option-row">
                        <label for="mobile-show-debug">Debug Console</label>
                        <ToggleSwitch :modelValue="showDebugPanel" @update:modelValue="updateShowDebugPanel" inputId="mobile-show-debug" />
                    </div>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="project">
            <AccordionHeader>Project</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton @click="emit('new-project'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">New Project</BaseButton>
                    <BaseButton @click="emit('new-graph'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">New Graph</BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="export">
            <AccordionHeader>Export</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton @click="emit('open-export-modal', 'png'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as PNG</BaseButton>
                    <BaseButton @click="emit('open-export-modal', 'jpg'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as JPG</BaseButton>
                    <BaseButton @click="emit('open-export-modal', 'svg'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as SVG</BaseButton>
                    <BaseButton @click="emit('export-json'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">as JSON</BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="add">
            <AccordionHeader>Add Nodes</AccordionHeader>
            <AccordionContent>
                <div class="grid grid-cols-2 gap-3 pt-3">
                    <BaseButton v-for="nodeDef in nodeDefinitions" :key="nodeDef.nodeType" 
                        @click="setAddNodeType(nodeDef.nodeType); mobileMenuOpen = false" type="ghost" size="small" class="text-xs p-3 border border-gray-200 dark:border-gray-700 rounded h-full flex items-center justify-center">
                        {{ nodeDef.label }}
                    </BaseButton>
                    <BaseButton @click="emit('update:currentMode', 'add-edge'); mobileMenuOpen = false" type="ghost" size="small" class="text-xs p-3 border border-gray-200 dark:border-gray-700 rounded h-full flex items-center justify-center">Add Edge</BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="layout">
            <AccordionHeader>Layout</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton @click="emit('apply-layout', 'dagre'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Dagre</BaseButton>
                    <BaseButton @click="emit('apply-layout', 'fcose'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">fCoSE</BaseButton>
                    <BaseButton @click="emit('apply-layout', 'cola'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Cola</BaseButton>
                    <BaseButton @click="emit('apply-layout', 'klay'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">KLay</BaseButton>
                    <BaseButton @click="emit('apply-layout', 'preset'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">Reset</BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="examples">
            <AccordionHeader>Examples</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton v-for="example in exampleModels" :key="example.key" 
                        @click="emit('load-example', example.key); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">
                        {{ example.name }}
                    </BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="connection">
            <AccordionHeader>Connection</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-5 pt-3">
                    <div class="flex flex-col gap-2">
                        <label for="backend-url-mobile" class="text-sm font-medium">URL:</label>
                        <BaseInput id="backend-url-mobile" v-model="navBackendUrl" placeholder="http://localhost:8081" class="w-full" />
                    </div>
                    <BaseButton @click="emit('connect-to-backend-url', navBackendUrl); mobileMenuOpen = false" :disabled="isConnecting" type="primary" class="w-full justify-center py-3">
                        <span v-if="isConnecting">Connecting...</span>
                        <span v-else>Connect</span>
                    </BaseButton>
                    <BaseButton @click="emit('generate-standalone'); mobileMenuOpen = false" type="ghost" class="w-full text-left text-sm p-3 border border-gray-200 dark:border-gray-700 rounded">Generate Standalone Script</BaseButton>
                </div>
            </AccordionContent>
        </AccordionPanel>

        <AccordionPanel value="help">
            <AccordionHeader>Help</AccordionHeader>
            <AccordionContent>
                <div class="flex flex-col gap-4 pt-3">
                    <BaseButton @click="emit('open-about-modal'); mobileMenuOpen = false" type="ghost" class="w-full text-left p-3 border border-gray-200 dark:border-gray-700 rounded">About</BaseButton>
                    <a href="https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md" target="_blank" rel="noopener noreferrer" class="p-button p-component p-button-ghost p-button-sm w-full text-left no-underline justify-start p-3 border border-gray-200 dark:border-gray-700 rounded">
                        Report an Issue
                    </a>
                </div>
            </AccordionContent>
        </AccordionPanel>
    </Accordion>
  </Drawer>
</template>

<style scoped>
.navbar-toolbar {
    border: none;
    border-bottom: 1px solid var(--p-content-border-color);
    border-radius: 0;
    padding: 0.25rem 1rem;
    background: var(--p-content-background);
    min-height: var(--navbar-height);
}

/* Responsive Visibility */
@media (max-width: 1024px) {
    .desktop-menu, .desktop-actions {
        display: none !important;
    }
    .mobile-toggle {
        display: inline-flex !important;
    }
}

@media (min-width: 1025px) {
    .mobile-toggle {
        display: none !important;
    }
}

/* Instant Tooltip Status Indicator */
.status-indicator {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    cursor: help;
}

.backend-status { margin-right: 5px; }
.backend-status.connected { color: var(--color-success); }
.backend-status.disconnected { color: var(--color-danger); }

.validation-status { font-size: 1.1em; margin: 0 5px; }
.validation-status.valid { color: var(--color-success); }
.validation-status.invalid { color: var(--color-warning); }

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
    box-shadow: 0 2px 6px rgba(0,0,0,0.2);
}

.status-indicator:hover .instant-tooltip {
    opacity: 1;
}

.dropdown-checkbox {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 8px;
    cursor: pointer;
}
.dropdown-input-group {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 8px;
}

.execution-dropdown {
    padding: 5px;
    min-width: 300px;
}
.dropdown-actions {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 10px;
}
.connection-status {
    font-size: 0.85em;
}
.connection-status.connected { color: var(--color-success); }

.report-issue-link {
    display: flex;
    justify-content: space-between;
    align-items: center;
}
.external-link-icon {
    font-size: 0.8em;
    opacity: 0.7;
}

.view-options {
    padding: 0.75rem;
    min-width: 320px;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}

.view-option-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
}

.view-label {
    cursor: pointer;
    font-size: 0.85rem;
    font-weight: 500;
    flex: 1;
    text-align: left;
    white-space: nowrap;
}

.settings-controls {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: 8px;
}

/* Compact InputNumber for Grid Size (Desktop) */
.grid-size-input {
    height: 34px;
    width: 3rem !important;
}

.grid-size-input :deep(.p-inputnumber-input) {
    width: 100% !important;
    text-align: left;
    padding: 0 0.25rem !important;
    font-size: 0.85rem;
    border-top-right-radius: 0;
    border-bottom-right-radius: 0;
}

.grid-size-input :deep(.p-inputnumber-button-group) {
    width: 1.25rem;
}

.grid-size-input :deep(.p-inputnumber-button) {
    width: 100% !important;
    padding: 0 !important;
    font-size: 0.6rem;
    height: 50%;
}

.grid-size-input :deep(.p-inputnumber-button-icon) {
    font-size: 0.7rem;
    font-weight: bold;
}

/* Select (Desktop) */
.grid-style-select {
    height: 34px;
    width: 90px !important; 
}

.grid-style-select :deep(.p-select-label) {
    padding: 0 8px;
    font-size: 0.8rem;
    line-height: 30px;
    display: flex;
    align-items: center;
}

.grid-style-select :deep(.p-select-dropdown) {
    width: 24px;
}

.setup-instructions {
    padding: 0.5rem 0;
}

.instruction-item {
    margin-bottom: 1rem;
}

.instruction-item:last-child {
    margin-bottom: 0;
}

.instruction-label {
    display: block;
    font-size: 0.8rem;
    font-weight: 500;
    margin-bottom: 0.25rem;
    color: var(--p-text-color);
}

.instruction-command {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background-color: var(--color-background-mute);
    border: 1px solid var(--p-content-border-color);
    border-radius: 4px;
    padding: 0.5rem;
}

:global(.dark-mode) .instruction-command {
    background-color: var(--color-background-soft);
}

.instruction-command code {
    flex: 1;
    font-family: 'Courier New', monospace;
    font-size: 0.75rem;
    color: var(--p-text-color);
    word-break: break-all;
}

.copy-btn-inline {
    flex-shrink: 0;
    padding: 0.15rem 0.4rem;
}

/* Mobile Menu Spacing */
.mobile-view-options {
    gap: 1.5rem;
}

.mobile-option-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 0.5rem 0;
    border-bottom: 1px solid var(--p-content-border-color);
}

.mobile-option-row:last-child {
    border-bottom: none;
}

.mobile-option-row label {
    font-size: 0.95rem;
    cursor: pointer;
    font-weight: 500;
}
</style>
