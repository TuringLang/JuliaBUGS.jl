<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick } from 'vue';
import { useProjectStore, type Project, type GraphMeta } from '../../stores/projectStore';
import { useGraphStore } from '../../stores/graphStore';
import BaseButton from '../ui/BaseButton.vue';
import BaseModal from '../common/BaseModal.vue';

const projectStore = useProjectStore();
const graphStore = useGraphStore();

const showDeleteConfirmModal = ref(false);
const itemToDelete = ref<{ type: 'project' | 'graph', id: string, name: string, projectId?: string } | null>(null);

const contextMenu = ref<{ type: 'project' | 'graph', id: string, x: number, y: number } | null>(null);
const contextMenuRef = ref<HTMLElement | null>(null);

const currentProject = computed(() => projectStore.currentProject);
const currentProjectGraphs = computed(() => {
  if (currentProject.value) {
    return projectStore.getGraphsForProject(currentProject.value.id);
  }
  return [];
});

const handleClickOutside = (event: MouseEvent) => {
  if (contextMenuRef.value && !contextMenuRef.value.contains(event.target as Node)) {
    contextMenu.value = null;
  }
};

onMounted(() => {
  projectStore.loadProjects();
  if (projectStore.projects.length > 0 && !projectStore.currentProjectId) {
    projectStore.selectProject(projectStore.projects[0].id);
  }
  document.addEventListener('click', handleClickOutside);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
});

const selectGraph = (graphId: string) => {
  graphStore.selectGraph(graphId);
};

const openContextMenu = async (event: MouseEvent, type: 'project' | 'graph', id: string) => {
  event.stopPropagation();
  event.preventDefault();
  contextMenu.value = null;
  await nextTick();
  contextMenu.value = { type, id, x: event.clientX, y: event.clientY };
};

const confirmDeletion = (type: 'project' | 'graph', id: string, name: string, projectId?: string) => {
  itemToDelete.value = { type, id, name, projectId };
  showDeleteConfirmModal.value = true;
  contextMenu.value = null;
};

const executeDeletion = () => {
  if (itemToDelete.value) {
    if (itemToDelete.value.type === 'project') {
      projectStore.deleteProject(itemToDelete.value.id);
    } else if (itemToDelete.value.type === 'graph' && itemToDelete.value.projectId) {
      projectStore.deleteGraphFromProject(itemToDelete.value.projectId, itemToDelete.value.id);
      if (graphStore.currentGraphId === itemToDelete.value.id) {
        graphStore.selectGraph(null);
      }
    }
    showDeleteConfirmModal.value = false;
    itemToDelete.value = null;
  }
};

const cancelDeletion = () => {
  showDeleteConfirmModal.value = false;
  itemToDelete.value = null;
};

const emit = defineEmits(['newProject', 'newGraph']);

const handleNewProject = () => {
  emit('newProject');
  contextMenu.value = null;
}

const handleNewGraph = () => {
  emit('newGraph');
  contextMenu.value = null;
}
</script>

<template>
  <div class="project-manager">
    <div class="header">
      <h4>Projects</h4>
      <BaseButton @click="handleNewProject" type="primary" size="small" class="add-project-btn" title="New Project">
        <i class="fas fa-plus"></i>
      </BaseButton>
    </div>

    <div v-if="projectStore.projects.length === 0" class="empty-state">
      <p>No projects yet.</p>
      <BaseButton @click="handleNewProject" type="primary">Create New Project</BaseButton>
    </div>

    <div v-else class="project-list">
      <div v-for="project in projectStore.projects" :key="project.id" class="project-item">
        <div class="project-header" @click="projectStore.selectProject(project.id)"
          :class="{ 'active': projectStore.currentProjectId === project.id }">
          <i class="icon-chevron fas fa-chevron-right"
            :class="{ 'open': projectStore.currentProjectId === project.id }"></i>
          <i class="icon-folder fas fa-folder"></i>
          <span class="project-name">{{ project.name }}</span>
          <button @click="openContextMenu($event, 'project', project.id)" class="context-menu-btn">
            <i class="fas fa-ellipsis-v"></i>
          </button>
        </div>
        <transition name="slide-fade">
          <div v-if="projectStore.currentProject?.id === project.id" class="graph-list">
            <div v-for="graph in currentProjectGraphs" :key="graph.id" class="graph-item"
              :class="{ 'active': graphStore.currentGraphId === graph.id }" @click="selectGraph(graph.id)">
              <i class="icon-file fas fa-file-alt"></i>
              <span>{{ graph.name }}</span>
              <button @click="openContextMenu($event, 'graph', graph.id)" class="context-menu-btn">
                <i class="fas fa-ellipsis-v"></i>
              </button>
            </div>
            <div v-if="currentProjectGraphs.length === 0" class="empty-state-inner">
              <p>No graphs in this project.</p>
              <BaseButton @click="handleNewGraph" type="secondary" size="small">Create New Graph</BaseButton>
            </div>
          </div>
        </transition>
      </div>
    </div>

    <div v-if="contextMenu" ref="contextMenuRef" class="context-menu"
      :style="{ top: `${contextMenu.y}px`, left: `${contextMenu.x}px` }">
      <template v-if="contextMenu.type === 'project'">
        <div class="context-menu-item" @click="handleNewGraph"><i class="fas fa-plus"></i> New Graph</div>
        <div class="context-menu-item danger"
          @click="confirmDeletion('project', contextMenu!.id, projectStore.projects.find((p: Project) => p.id === contextMenu!.id)!.name)">
          <i class="fas fa-trash-alt"></i> Delete Project</div>
      </template>
      <template v-if="contextMenu.type === 'graph'">
        <div class="context-menu-item danger"
          @click="confirmDeletion('graph', contextMenu!.id, currentProjectGraphs.find((g: GraphMeta) => g.id === contextMenu!.id)!.name, currentProject!.id)">
          <i class="fas fa-trash-alt"></i> Delete Graph</div>
      </template>
    </div>

    <BaseModal :is-open="showDeleteConfirmModal" @close="cancelDeletion">
      <template #header>
        <h3>Confirm Deletion</h3>
      </template>
      <template #body>
        <p v-if="itemToDelete">
          Are you sure you want to delete the {{ itemToDelete.type }}
          <strong>"{{ itemToDelete.name }}"</strong>?
          <span v-if="itemToDelete.type === 'project'">This will also delete all of its graphs.</span>
          This action cannot be undone.
        </p>
      </template>
      <template #footer>
        <BaseButton @click="cancelDeletion" type="secondary">Cancel</BaseButton>
        <BaseButton @click="executeDeletion" type="danger">Delete</BaseButton>
      </template>
    </BaseModal>
  </div>
</template>

<style scoped>
.project-manager {
  display: flex;
  flex-direction: column;
  height: 100%;
  background-color: var(--color-background-soft);
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 15px;
  border-bottom: 1px solid var(--color-border-light);
  flex-shrink: 0;
}

.header h4 {
  margin: 0;
  color: var(--color-heading);
  font-size: 1.1em;
  font-weight: 600;
}

.add-project-btn {
  padding: 4px 8px;
}

.empty-state {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 20px;
  color: var(--color-secondary);
}

.empty-state p {
  margin: 0 0 10px 0;
  font-size: 1.1em;
  font-weight: 500;
}

.empty-state-inner {
  color: var(--color-secondary);
  text-align: center;
  padding: 15px;
  font-size: 0.9em;
}

.empty-state-inner p {
  margin: 0 0 10px 0;
}

.project-list {
  flex-grow: 1;
  overflow-y: auto;
  padding: 10px;
}

.project-item {
  margin-bottom: 5px;
}

.project-header {
  display: flex;
  align-items: center;
  padding: 8px 10px;
  cursor: pointer;
  transition: background-color 0.2s ease;
  gap: 8px;
  border-radius: 4px;
}

.project-header:hover {
  background-color: var(--color-background-mute);
}

.project-header.active {
  background-color: var(--color-primary);
  color: white;
}

.project-header.active .project-name,
.project-header.active .icon-folder,
.project-header.active .icon-chevron {
  color: white;
}

.icon-chevron {
  font-size: 0.7em;
  color: var(--color-secondary);
  transition: transform 0.2s ease-in-out;
  width: 12px;
  text-align: center;
}

.icon-chevron.open {
  transform: rotate(90deg);
}

.icon-folder {
  color: var(--color-primary);
  font-size: 0.9em;
}

.project-name {
  flex-grow: 1;
  font-weight: 500;
  color: var(--color-heading);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.graph-list {
  padding-left: 20px;
  overflow: hidden;
  border-left: 1px solid var(--color-border-light);
  margin-left: 14px;
}

.slide-fade-enter-active {
  transition: all 0.3s ease-out;
}

.slide-fade-leave-active {
  transition: all 0.2s cubic-bezier(1, 0.5, 0.8, 1);
}

.slide-fade-enter-from,
.slide-fade-leave-to {
  max-height: 0;
  opacity: 0;
}

.slide-fade-enter-to,
.slide-fade-leave-from {
  max-height: 500px;
}

.graph-item {
  display: flex;
  align-items: center;
  padding: 6px 10px;
  margin-top: 4px;
  cursor: pointer;
  transition: background-color 0.2s ease, color 0.2s ease;
  gap: 8px;
  border-radius: 4px;
}

.graph-item:hover {
  background-color: var(--color-background-mute);
}

.graph-item.active {
  background-color: var(--color-primary);
}

.graph-item.active span,
.graph-item.active .icon-file {
  color: white;
}

.graph-item span {
  flex-grow: 1;
  font-size: 0.9em;
}

.icon-file {
  font-size: 0.9em;
  color: var(--color-secondary);
}

.context-menu-btn {
  padding: 4px 8px;
  font-size: 0.8em;
  background-color: transparent;
  color: var(--color-secondary);
  border: none;
  border-radius: 3px;
  opacity: 0;
  transition: opacity 0.2s ease, color 0.2s ease;
}

.project-header:hover .context-menu-btn,
.graph-item:hover .context-menu-btn {
  opacity: 1;
}

.context-menu-btn:hover {
  color: var(--color-heading);
}

.context-menu {
  position: fixed;
  background-color: var(--color-background-soft);
  border: 1px solid var(--color-border);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  border-radius: 6px;
  padding: 8px 0;
  z-index: 1000;
  min-width: 180px;
}

.context-menu-item {
  padding: 8px 16px;
  cursor: pointer;
  font-size: 0.9em;
  display: flex;
  align-items: center;
  gap: 10px;
}

.context-menu-item:hover {
  background-color: var(--color-primary);
  color: white;
}

.context-menu-item.danger:hover {
  background-color: var(--color-danger);
  color: white;
}

.context-menu-item .fas {
  width: 14px;
  text-align: center;
}
</style>
