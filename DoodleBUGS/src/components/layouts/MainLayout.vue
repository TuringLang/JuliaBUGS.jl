<script setup lang="ts">
import { ref, watch, computed, onUnmounted, onMounted } from 'vue';
import type { StyleValue } from 'vue';
import { storeToRefs } from 'pinia';
import GraphEditor from '../canvas/GraphEditor.vue';
import ProjectManager from '../left-sidebar/ProjectManager.vue';
import NodePalette from '../left-sidebar/NodePalette.vue';
import DataInputPanel from '../panels/DataInputPanel.vue';
import NodePropertiesPanel from '../right-sidebar/NodePropertiesPanel.vue';
import CodePreviewPanel from '../panels/CodePreviewPanel.vue';
import JsonEditorPanel from '../right-sidebar/JsonEditorPanel.vue';
import TheNavbar from './TheNavbar.vue';
import BaseModal from '../common/BaseModal.vue';
import BaseInput from '../ui/BaseInput.vue';
import BaseButton from '../ui/BaseButton.vue';
import AboutModal from './AboutModal.vue';
import ExportModal from './ExportModal.vue';
import ValidationIssuesModal from './ValidationIssuesModal.vue';

import { useGraphElements } from '../../composables/useGraphElements';
import { useProjectStore } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import { useUiStore } from '../../stores/uiStore';
import { useDataStore } from '../../stores/dataStore';
import { useGraphInstance } from '../../composables/useGraphInstance';
import { useGraphValidator } from '../../composables/useGraphValidator';
import type { GraphElement, NodeType, PaletteItemType, GraphNode, ExampleModel } from '../../types';

const projectStore = useProjectStore();
const graphStore = useGraphStore();
const uiStore = useUiStore();
const dataStore = useDataStore();

const { parsedGraphData } = storeToRefs(dataStore);
const { elements, selectedElement, updateElement, deleteElement } = useGraphElements();
const { getCyInstance } = useGraphInstance();
const { validateGraph, validationErrors } = useGraphValidator(elements, parsedGraphData);

const activeLeftTab = ref<'project' | 'palette' | 'data' | null>('project');
const isLeftSidebarOpen = ref(true);
const isRightSidebarOpen = ref(true);
const currentMode = ref<string>('select');
const currentNodeType = ref<NodeType>('stochastic');
const isGridEnabled = ref(true);
const gridSize = ref(20);

const isResizingLeft = ref(false);
const isResizingRight = ref(false);

const showNewProjectModal = ref(false);
const newProjectName = ref('');
const showNewGraphModal = ref(false);
const newGraphName = ref('');
const showAboutModal = ref(false);
const showValidationModal = ref(false);

const showExportModal = ref(false);
const currentExportType = ref<'png' | 'jpg' | 'svg' | null>(null);

onMounted(() => {
  projectStore.loadProjects();

  // If no projects exist (e.g., first time user or incognito), create a default project and graph.
  if (projectStore.projects.length === 0) {
    projectStore.createProject('Default Project');
    if (projectStore.currentProjectId) {
      projectStore.addGraphToProject(projectStore.currentProjectId, 'Untitled Graph');
    }
  }

  const lastGraphId = localStorage.getItem('doodlebugs-currentGraphId');
  if (lastGraphId) {
    const project = projectStore.currentProject;
    if (project && project.graphs.some(g => g.id === lastGraphId)) {
      graphStore.selectGraph(lastGraphId);
    }
  }
  validateGraph();
});

const currentProjectName = computed(() => projectStore.currentProject?.name || null);
const activeGraphName = computed(() => {
  if (projectStore.currentProject && graphStore.currentGraphId) {
    const graphMeta = projectStore.currentProject.graphs.find(g => g.id === graphStore.currentGraphId);
    return graphMeta?.name || null;
  }
  return null;
});

const handleLeftTabClick = (tabName: 'project' | 'palette' | 'data') => {
  if (activeLeftTab.value === tabName && isLeftSidebarOpen.value) {
    isLeftSidebarOpen.value = false;
  } else {
    isLeftSidebarOpen.value = true;
    activeLeftTab.value = tabName;
  }
};

const toggleLeftSidebar = () => {
  isLeftSidebarOpen.value = !isLeftSidebarOpen.value;
};

const toggleRightSidebar = () => {
  isRightSidebarOpen.value = !isRightSidebarOpen.value;
};

const leftSidebarStyle = computed((): StyleValue => ({
  width: isLeftSidebarOpen.value ? `${uiStore.leftSidebarWidth}px` : 'var(--vertical-tab-width)',
  transition: isResizingLeft.value ? 'none' : 'width 0.3s ease-in-out',
}));

const leftSidebarContentStyle = computed((): StyleValue => {
  const contentWidth = uiStore.leftSidebarWidth - 50;
  return {
    width: `${contentWidth}px`,
    opacity: isLeftSidebarOpen.value ? '1' : '0',
    pointerEvents: isLeftSidebarOpen.value ? 'auto' : 'none',
  }
});

const rightSidebarStyle = computed((): StyleValue => ({
  width: isRightSidebarOpen.value ? `${uiStore.rightSidebarWidth}px` : '0',
  opacity: isRightSidebarOpen.value ? '1' : '0',
  pointerEvents: isRightSidebarOpen.value ? 'auto' : 'none',
  borderLeft: isRightSidebarOpen.value ? '1px solid var(--color-border)' : 'none',
  transition: isResizingRight.value ? 'none' : 'width 0.3s ease-in-out, opacity 0.3s ease-in-out',
}));

const startResizeLeft = () => {
  isResizingLeft.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  window.addEventListener('mousemove', doResizeLeft);
  window.addEventListener('mouseup', stopResize);
};

const doResizeLeft = (event: MouseEvent) => {
  if (isResizingLeft.value) {
    const newWidth = event.clientX;
    uiStore.leftSidebarWidth = Math.max(250, Math.min(newWidth, 600));
  }
};

const startResizeRight = () => {
  isResizingRight.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  window.addEventListener('mousemove', doResizeRight);
  window.addEventListener('mouseup', stopResize);
};

const doResizeRight = (event: MouseEvent) => {
  if (isResizingRight.value) {
    const newWidth = window.innerWidth - event.clientX;
    uiStore.rightSidebarWidth = Math.max(280, Math.min(newWidth, 600));
  }
};

const stopResize = () => {
  isResizingLeft.value = false;
  isResizingRight.value = false;
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  window.removeEventListener('mousemove', doResizeLeft);
  window.removeEventListener('mousemove', doResizeRight);
  window.removeEventListener('mouseup', stopResize);
};

onUnmounted(() => {
  stopResize();
});

const handleElementSelected = (element: GraphElement | null) => {
  selectedElement.value = element;
  if (element && !uiStore.isRightTabPinned) {
    uiStore.setActiveRightTab('properties');
  }
};

const handleSelectNodeFromModal = (nodeId: string) => {
    const nodeToSelect = elements.value.find(el => el.id === nodeId);
    if (nodeToSelect) {
        handleElementSelected(nodeToSelect);
        const cy = getCyInstance();
        if (cy) {
            cy.elements().unselect();
            cy.getElementById(nodeId).select();
            cy.animate({
                center: {
                    eles: cy.getElementById(nodeId)
                },
                zoom: 1.2,
                duration: 500
            });
        }
    }
};

const handleUpdateElement = (updatedEl: GraphElement) => {
  updateElement(updatedEl);
};

const handleDeleteElement = (elementId: string) => {
  deleteElement(elementId);
};

const handlePaletteSelection = (itemType: PaletteItemType) => {
  if (itemType === 'add-edge') {
    currentMode.value = 'add-edge';
  } else {
    currentMode.value = 'add-node';
    currentNodeType.value = itemType;
  }
  isLeftSidebarOpen.value = false;
};

const createNewProject = () => {
  if (newProjectName.value.trim()) {
    projectStore.createProject(newProjectName.value.trim());
    showNewProjectModal.value = false;
    newProjectName.value = '';
    activeLeftTab.value = 'project';
    isLeftSidebarOpen.value = true;
  }
};

const createNewGraph = () => {
  if (projectStore.currentProject && newGraphName.value.trim()) {
    projectStore.addGraphToProject(projectStore.currentProject.id, newGraphName.value.trim());
    showNewGraphModal.value = false;
    newGraphName.value = '';
  }
};

const saveCurrentGraph = () => {
  if (graphStore.currentGraphId) {
    graphStore.saveGraph(graphStore.currentGraphId, graphStore.graphContents.get(graphStore.currentGraphId)!);
  } else {
    console.warn("No graph currently selected to save.");
  }
};

const triggerDownload = (blob: Blob, fileName: string) => {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

const handleExportJson = () => {
    if (!graphStore.currentGraphId) {
        alert("Please select a graph to export.");
        return;
    }
    const elementsToExport = graphStore.currentGraphElements;
    const jsonString = JSON.stringify(elementsToExport, null, 2);
    const blob = new Blob([jsonString], { type: 'application/json' });
    const fileName = `${activeGraphName.value || 'graph'}.json`;
    triggerDownload(blob, fileName);
};

const openExportModal = (format: 'png' | 'jpg' | 'svg') => {
    if (!graphStore.currentGraphId) {
        alert("Please select a graph to export.");
        return;
    }
    currentExportType.value = format;
    showExportModal.value = true;
};

const handleConfirmExport = (options: any) => {
    const cy = getCyInstance();
    if (!cy || !currentExportType.value) return;

    const fileName = `${activeGraphName.value || 'graph'}.${currentExportType.value}`;

    try {
        let blob: Blob;
        if (currentExportType.value === 'svg') {
            const svgContent = cy.svg(options);
            blob = new Blob([svgContent], { type: 'image/svg+xml;charset=utf-8' });
        } else if (currentExportType.value === 'jpg') {
            blob = cy.jpg({ ...options, output: 'blob' }) as unknown as Blob;
        } else {
            blob = cy.png({ ...options, output: 'blob' }) as unknown as Blob;
        }
        triggerDownload(blob, fileName);
    } catch (err) {
        console.error(`Failed to export ${currentExportType.value}:`, err);
        alert(`An error occurred while exporting the graph. Please check the console.`);
    }
};

const handleApplyLayout = (layoutName: string) => {
    const cy = getCyInstance();
    if (!cy) return;

    const layoutOptions = {
        name: layoutName,
        animate: true,
        padding: 50,
        fit: true,
        ...(layoutName === 'dagre' && { 
            rankDir: 'TB', 
            spacingFactor: 1.2 
        }),
        ...(layoutName === 'fcose' && { 
            idealEdgeLength: 120, 
            nodeSeparation: 150,
            nodeRepulsion: 4500,
            quality: 'proof',
        }),
    };

    const layout = cy.layout(layoutOptions);
    
    layout.on('layoutstop', () => {
        const updatedNodes = cy.nodes().map(node => {
            const originalNode = graphStore.currentGraphElements.find(el => el.id === node.id() && el.type === 'node') as GraphNode | undefined;
            if (originalNode) {
                return { ...originalNode, position: node.position() };
            }
            return null;
        }).filter(n => n !== null) as GraphNode[];

        updatedNodes.forEach(node => updateElement(node));
    });

    layout.run();
};

const handleLoadExample = async (exampleKey: string) => {
    if (!projectStore.currentProjectId) {
        alert("Please create or select a project before loading an example.");
        return;
    }

    try {
        const baseUrl = import.meta.env.BASE_URL;
        const modelUrl = `${baseUrl}examples/${exampleKey}/model.json`;
        const dataUrl = `${baseUrl}examples/${exampleKey}/data.json`;

        const [modelResponse, dataResponse] = await Promise.all([
            fetch(modelUrl),
            fetch(dataUrl)
        ]);

        if (!modelResponse.ok) {
            throw new Error(`Could not fetch example model: ${modelResponse.statusText}`);
        }
        const modelData: ExampleModel = await modelResponse.json();

        const newGraphMeta = projectStore.addGraphToProject(projectStore.currentProjectId, modelData.name);
        
        if (newGraphMeta) {
            graphStore.updateGraphElements(newGraphMeta.id, modelData.graphJSON);
            if (dataResponse.ok) {
                const data = await dataResponse.json();
                dataStore.currentGraphDataString = JSON.stringify(data, null, 2);
            }
        }
        
        setTimeout(() => handleApplyLayout('dagre'), 100);

    } catch (error) {
        console.error("Failed to load example model:", error);
        alert("Failed to load the example model. See console for details.");
    }
};

const isModelValid = computed(() => validationErrors.value.size === 0);
</script>

<template>
  <div class="main-layout">
    <TheNavbar
      :project-name="currentProjectName"
      :active-graph-name="activeGraphName"
      :is-grid-enabled="isGridEnabled"
      @update:is-grid-enabled="isGridEnabled = $event"
      :grid-size="gridSize"
      @update:grid-size="gridSize = $event"
      :current-mode="currentMode"
      @update:current-mode="currentMode = $event"
      :current-node-type="currentNodeType"
      @update:current-node-type="currentNodeType = $event"
      :is-left-sidebar-open="isLeftSidebarOpen"
      :is-right-sidebar-open="isRightSidebarOpen"
      @toggle-left-sidebar="toggleLeftSidebar"
      @toggle-right-sidebar="toggleRightSidebar"
      @new-project="showNewProjectModal = true"
      @new-graph="showNewGraphModal = true"
      @save-current-graph="saveCurrentGraph"
      @open-about-modal="showAboutModal = true"
      @export-json="handleExportJson"
      @open-export-modal="openExportModal"
      @apply-layout="handleApplyLayout"
      @load-example="handleLoadExample"
      @validate-model="validateGraph"
      :is-model-valid="isModelValid"
      @show-validation-issues="showValidationModal = true"
    />

    <div class="content-area">
      <aside class="left-sidebar" :style="leftSidebarStyle">
        <div class="vertical-tabs-container">
          <button :class="{ active: activeLeftTab === 'project' }" @click="handleLeftTabClick('project')"
            title="Project Manager">
            <i class="fas fa-folder"></i> <span v-show="isLeftSidebarOpen">Project</span>
          </button>
          <button :class="{ active: activeLeftTab === 'palette' }" @click="handleLeftTabClick('palette')"
            title="Node Palette">
            <i class="fas fa-shapes"></i> <span v-show="isLeftSidebarOpen">Palette</span>
          </button>
          <button :class="{ active: activeLeftTab === 'data' }" @click="handleLeftTabClick('data')" title="Data Input">
            <i class="fas fa-database"></i> <span v-show="isLeftSidebarOpen">Data</span>
          </button>
        </div>
        <div class="left-sidebar-content" :style="leftSidebarContentStyle">
          <div v-show="activeLeftTab === 'project'">
            <ProjectManager @new-project="showNewProjectModal = true" @new-graph="showNewGraphModal = true" />
          </div>
          <div v-show="activeLeftTab === 'palette'">
            <NodePalette @select-palette-item="handlePaletteSelection" />
          </div>
          <div v-show="activeLeftTab === 'data'">
            <DataInputPanel />
          </div>
        </div>
      </aside>
      
      <div class="resizer resizer-left" @mousedown.prevent="startResizeLeft"></div>

      <main class="graph-editor-wrapper">
        <GraphEditor
          :is-grid-enabled="isGridEnabled"
          :grid-size="gridSize"
          :current-mode="currentMode"
          :elements="elements"
          :current-node-type="currentNodeType"
          :validation-errors="validationErrors"
          @update:current-mode="currentMode = $event"
          @update:current-node-type="currentNodeType = $event"
          @element-selected="handleElementSelected"
        />
      </main>

      <div class="resizer resizer-right" @mousedown.prevent="startResizeRight"></div>

      <aside class="right-sidebar" :style="rightSidebarStyle">
        <div class="tabs-header">
          <div class="tab-buttons">
            <button :class="{ active: uiStore.activeRightTab === 'properties' }"
              @click="uiStore.setActiveRightTab('properties')">Properties</button>
            <button :class="{ active: uiStore.activeRightTab === 'code' }"
              @click="uiStore.setActiveRightTab('code')">Code</button>
            <button :class="{ active: uiStore.activeRightTab === 'json' }"
              @click="uiStore.setActiveRightTab('json')">JSON</button>
          </div>
          <button @click="uiStore.toggleRightTabPinned()" class="pin-button" :class="{ 'pinned': uiStore.isRightTabPinned }" title="Pin Tab">
            <i class="fas fa-thumbtack"></i>
          </button>
        </div>
        <div class="tabs-content">
          <div v-show="uiStore.activeRightTab === 'properties'" class="tab-pane">
            <NodePropertiesPanel
              :selected-element="selectedElement"
              :validation-errors="validationErrors"
              @update-element="handleUpdateElement"
              @delete-element="handleDeleteElement"
            />
          </div>
          <div v-show="uiStore.activeRightTab === 'code'" class="tab-pane">
            <CodePreviewPanel />
          </div>
          <div v-show="uiStore.activeRightTab === 'json'" class="tab-pane">
            <JsonEditorPanel />
          </div>
        </div>
      </aside>
    </div>

    <BaseModal :is-open="showNewProjectModal" @close="showNewProjectModal = false">
      <template #header>
        <h3>Create New Project</h3>
      </template>
      <template #body>
        <label for="new-project-name" style="display: block; margin-bottom: 8px; font-weight: 500;">Project
          Name:</label>
        <BaseInput id="new-project-name" v-model="newProjectName" placeholder="Enter project name"
          @keyup.enter="createNewProject" />
      </template>
      <template #footer>
        <BaseButton @click="showNewProjectModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewProject" type="primary">Create</BaseButton>
      </template>
    </BaseModal>
    <BaseModal :is-open="showNewGraphModal" @close="showNewGraphModal = false">
      <template #header>
        <h3>Create New Graph</h3>
      </template>
      <template #body>
        <label for="new-graph-name" style="display: block; margin-bottom: 8px; font-weight: 500;">Graph Name:</label>
        <BaseInput id="new-graph-name" v-model="newGraphName" placeholder="Enter graph name"
          @keyup.enter="createNewGraph" />
      </template>
      <template #footer>
        <BaseButton @click="showNewGraphModal = false" type="secondary">Cancel</BaseButton>
        <BaseButton @click="createNewGraph" type="primary">Create</BaseButton>
      </template>
    </BaseModal>
    <AboutModal :is-open="showAboutModal" @close="showAboutModal = false" />
    <ExportModal 
      :is-open="showExportModal" 
      :export-type="currentExportType"
      @close="showExportModal = false"
      @confirm-export="handleConfirmExport"
    />
    <ValidationIssuesModal
        :is-open="showValidationModal"
        :validation-errors="validationErrors"
        :elements="elements"
        @close="showValidationModal = false"
        @select-node="handleSelectNodeFromModal"
    />
  </div>
</template>

<style scoped>
.main-layout {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

.content-area {
  display: flex;
  flex-grow: 1;
  overflow: hidden;
}

.left-sidebar {
  display: flex;
  background-color: var(--color-background-soft);
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  /* z-index: 10; */
  flex-shrink: 0;
}

.vertical-tabs-container {
  display: flex;
  flex-direction: column;
  width: var(--vertical-tab-width);
  border-right: 1px solid var(--color-border-light);
  background-color: var(--color-background-dark);
  padding-top: 10px;
  flex-shrink: 0;
}

.vertical-tabs-container button {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  width: 100%;
  padding: 10px 0;
  border: none;
  background-color: transparent;
  color: var(--color-text-light);
  font-size: 0.75em;
  font-weight: 500;
  transition: all 0.2s ease;
  gap: 5px;
  cursor: pointer;
  white-space: nowrap;
}

.vertical-tabs-container button i {
  font-size: 1.3em;
  color: var(--color-secondary);
  transition: color 0.2s ease;
}

.vertical-tabs-container button:hover {
  background-color: var(--color-primary-hover);
  color: white;
}

.vertical-tabs-container button:hover i {
  color: white;
}

.vertical-tabs-container button.active {
  background-color: var(--color-primary);
  color: white;
  border-left: 2px solid white;
}

.vertical-tabs-container button.active i {
  color: white;
}

.left-sidebar-content {
  flex-grow: 1;
  overflow-y: auto;
  padding: 15px;
  -webkit-overflow-scrolling: touch;
  transition: opacity 0.3s ease-in-out;
  box-sizing: border-box;
}

.right-sidebar {
  display: flex;
  flex-direction: column;
  background-color: var(--color-background-soft);
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  /* z-index: 10; */
  flex-shrink: 0;
}

.tabs-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--color-border-light);
  flex-shrink: 0;
  padding-right: 10px;
}

.tab-buttons {
  display: flex;
  flex-grow: 1;
}

.tab-buttons button {
  flex: 1;
  padding: 10px 15px;
  border: none;
  background-color: transparent;
  border-bottom: 2px solid transparent;
  font-weight: 500;
  color: var(--color-text);
  transition: all 0.2s ease;
  white-space: nowrap;
}

.tab-buttons button:hover {
  background-color: var(--color-background-mute);
}

.tab-buttons button.active {
  color: var(--color-primary);
  border-bottom-color: var(--color-primary);
  background-color: var(--color-background-soft);
}

.pin-button {
  background: none;
  border: none;
  color: var(--color-secondary);
  cursor: pointer;
  padding: 5px;
  font-size: 0.9em;
  border-radius: 4px;
  transition: all 0.2s ease;
}

.pin-button:hover {
  background-color: var(--color-background-mute);
}

.pin-button.pinned {
  color: var(--color-primary);
  transform: rotate(45deg);
}

.tabs-content {
  flex-grow: 1;
  overflow-y: auto;
  position: relative;
  min-height: 0;
}

.tab-pane {
  height: 100%;
  width: 100%;
  overflow-y: auto;
  position: absolute;
  top: 0;
  left: 0;
  background-color: var(--color-background-soft);
}

.graph-editor-wrapper {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  position: relative;
  background-color: var(--color-background-mute);
  min-width: 0;
}

.resizer {
  flex-shrink: 0;
  width: 2px;
  background-color: transparent;
  cursor: col-resize;
  /* z-index: 20; */
  transition: background-color 0.2s ease;
}
.resizer:hover, .resizer-left:active, .resizer-right:active {
  background-color: var(--color-primary);
}
.resizer-left {
  border-right: 1px solid var(--color-border);
}
.resizer-right {
  border-left: 1px solid var(--color-border);
}

</style>
