<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick } from 'vue'
import { useProjectStore, type Project, type GraphMeta } from '../../stores/projectStore'
import { useGraphStore } from '../../stores/graphStore'
import BaseButton from '../ui/BaseButton.vue'
import BaseModal from '../common/BaseModal.vue'
import BaseInput from '../ui/BaseInput.vue'

const projectStore = useProjectStore()
const graphStore = useGraphStore()

const showDeleteConfirmModal = ref(false)
const itemToDelete = ref<{
  type: 'project' | 'graph'
  id: string
  name: string
  projectId?: string
} | null>(null)

const showRenameModal = ref(false)
const itemToRename = ref<{
  type: 'project' | 'graph'
  id: string
  name: string
  projectId?: string
} | null>(null)
const newItemName = ref('')

const contextMenu = ref<{ type: 'project' | 'graph'; id: string; x: number; y: number } | null>(
  null
)
const contextMenuRef = ref<HTMLElement | null>(null)

const currentProject = computed(() => projectStore.currentProject)
const currentProjectGraphs = computed(() => {
  if (currentProject.value) {
    return projectStore.getGraphsForProject(currentProject.value.id)
  }
  return []
})

const handleClickOutside = (event: MouseEvent) => {
  if (contextMenuRef.value && !contextMenuRef.value.contains(event.target as Node)) {
    contextMenu.value = null
  }
}

onMounted(() => {
  projectStore.loadProjects()
  if (projectStore.projects.length > 0 && !projectStore.currentProjectId) {
    projectStore.selectProject(projectStore.projects[0].id)
  }
  document.addEventListener('click', handleClickOutside)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})

const selectGraph = (graphId: string) => {
  graphStore.selectGraph(graphId)
}

const openContextMenu = async (event: MouseEvent, type: 'project' | 'graph', id: string) => {
  event.stopPropagation()
  event.preventDefault()
  contextMenu.value = null
  await nextTick()
  contextMenu.value = { type, id, x: event.clientX, y: event.clientY }
}

const confirmDeletion = (
  type: 'project' | 'graph',
  id: string,
  name: string,
  projectId?: string
) => {
  itemToDelete.value = { type, id, name, projectId }
  showDeleteConfirmModal.value = true
  contextMenu.value = null
}

const executeDeletion = () => {
  if (itemToDelete.value) {
    if (itemToDelete.value.type === 'project') {
      projectStore.deleteProject(itemToDelete.value.id)
    } else if (itemToDelete.value.type === 'graph' && itemToDelete.value.projectId) {
      projectStore.deleteGraphFromProject(itemToDelete.value.projectId, itemToDelete.value.id)
      if (graphStore.currentGraphId === itemToDelete.value.id) {
        graphStore.selectGraph(null)
      }
    }
    showDeleteConfirmModal.value = false
    itemToDelete.value = null
  }
}

const openRenameModal = (
  type: 'project' | 'graph',
  id: string,
  name: string,
  projectId?: string
) => {
  itemToRename.value = { type, id, name, projectId }
  newItemName.value = name
  showRenameModal.value = true
  contextMenu.value = null
}

const executeRename = () => {
  if (itemToRename.value && newItemName.value.trim()) {
    if (itemToRename.value.type === 'project') {
      projectStore.renameProject(itemToRename.value.id, newItemName.value)
    } else if (itemToRename.value.type === 'graph' && itemToRename.value.projectId) {
      projectStore.renameGraphInProject(
        itemToRename.value.projectId,
        itemToRename.value.id,
        newItemName.value
      )
    }
  }
  showRenameModal.value = false
  itemToRename.value = null
  newItemName.value = ''
}

const emit = defineEmits(['newProject', 'newGraph'])

const handleNewProject = () => {
  emit('newProject')
  contextMenu.value = null
}

const handleNewGraph = () => {
  emit('newGraph')
  contextMenu.value = null
}
</script>

<template>
  <div class="project-manager">
    <div class="header">
      <h4>Projects</h4>
      <div class="header-actions">
        <BaseButton
          @click="handleNewGraph"
          type="ghost"
          size="small"
          class="header-action-btn"
          title="New Graph in Current Project"
          :disabled="!currentProject"
        >
          <i class="fas fa-hexagon-nodes"></i>
        </BaseButton>
        <BaseButton
          @click="handleNewProject"
          type="ghost"
          size="small"
          class="header-action-btn"
          title="New Project"
        >
          <i class="fas fa-folder" style="color: #10b981"></i>
        </BaseButton>
      </div>
    </div>

    <div v-if="projectStore.projects.length === 0" class="empty-state">
      <p>No projects yet.</p>
      <BaseButton @click="handleNewProject" type="primary">Create New Project</BaseButton>
    </div>

    <div v-else class="project-list">
      <div v-for="project in projectStore.projects" :key="project.id" class="project-item">
        <div
          class="project-header"
          @click="projectStore.selectProject(project.id)"
          @touchend.prevent="projectStore.selectProject(project.id)"
          :class="{ active: projectStore.currentProjectId === project.id }"
        >
          <i
            class="icon-chevron fas fa-chevron-right"
            :class="{ open: projectStore.currentProjectId === project.id }"
          ></i>
          <i class="icon-folder fas fa-folder"></i>
          <span class="project-name">{{ project.name }}</span>
          <div class="project-actions">
            <button
              @click.stop="openContextMenu($event, 'project', project.id)"
              class="action-btn context-menu-btn"
            >
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
        </div>
        <transition name="slide-fade">
          <div v-if="projectStore.currentProject?.id === project.id" class="graph-list">
            <div
              v-for="graph in currentProjectGraphs"
              :key="graph.id"
              class="graph-item"
              :class="{ active: graphStore.currentGraphId === graph.id }"
              @click="selectGraph(graph.id)"
              @touchend.prevent="selectGraph(graph.id)"
            >
              <i class="icon-file fas fa-hexagon-nodes"></i>
              <span>{{ graph.name }}</span>
              <button
                @click.stop="openContextMenu($event, 'graph', graph.id)"
                class="action-btn context-menu-btn"
              >
                <i class="fas fa-ellipsis-v"></i>
              </button>
            </div>
            <div v-if="currentProjectGraphs.length === 0" class="empty-state-inner">
              <p>No graphs in this project.</p>
              <BaseButton @click="handleNewGraph" type="secondary" size="small"
                >Create New Graph</BaseButton
              >
            </div>
          </div>
        </transition>
      </div>
    </div>

    <Teleport to="body">
      <div
        v-if="contextMenu"
        ref="contextMenuRef"
        class="context-menu"
        :style="{ top: `${contextMenu.y}px`, left: `${contextMenu.x}px` }"
      >
        <template v-if="contextMenu.type === 'project'">
          <div class="context-menu-item" @click="handleNewGraph">
            <i class="fas fa-hexagon-nodes"></i> New Graph
          </div>
          <div
            class="context-menu-item"
            @click="
              openRenameModal(
                'project',
                contextMenu!.id,
                projectStore.projects.find((p) => p.id === contextMenu!.id)!.name
              )
            "
          >
            <i class="fas fa-edit"></i> Rename
          </div>
          <div
            class="context-menu-item danger"
            @click="
              confirmDeletion(
                'project',
                contextMenu!.id,
                projectStore.projects.find((p: Project) => p.id === contextMenu!.id)!.name
              )
            "
          >
            <i class="fas fa-trash-alt"></i> Delete Project
          </div>
        </template>
        <template v-if="contextMenu.type === 'graph'">
          <div
            class="context-menu-item"
            @click="
              openRenameModal(
                'graph',
                contextMenu!.id,
                currentProjectGraphs.find((g) => g.id === contextMenu!.id)!.name,
                currentProject!.id
              )
            "
          >
            <i class="fas fa-edit"></i> Rename
          </div>
          <div
            class="context-menu-item danger"
            @click="
              confirmDeletion(
                'graph',
                contextMenu!.id,
                currentProjectGraphs.find((g: GraphMeta) => g.id === contextMenu!.id)!.name,
                currentProject!.id
              )
            "
          >
            <i class="fas fa-trash-alt"></i> Delete Graph
          </div>
        </template>
      </div>
    </Teleport>

    <BaseModal :is-open="showDeleteConfirmModal" @close="showDeleteConfirmModal = false">
      <template #header>
        <h3>Confirm Deletion</h3>
      </template>
      <template #body>
        <div class="confirm-body">
          <p v-if="itemToDelete">
            Are you sure you want to delete the {{ itemToDelete.type }}
            <strong>"{{ itemToDelete.name }}"</strong>?
            <span v-if="itemToDelete.type === 'project'"
              >This will also delete all of its graphs.</span
            >
            This action cannot be undone.
          </p>
        </div>
      </template>
      <template #footer>
        <BaseButton @click="executeDeletion" type="danger">Delete</BaseButton>
      </template>
    </BaseModal>

    <BaseModal :is-open="showRenameModal" @close="showRenameModal = false">
      <template #header>
        <h3>Rename {{ itemToRename?.type }}</h3>
      </template>
      <template #body>
        <div class="rename-body">
          <label for="new-item-name" style="display: block; margin-bottom: 8px; font-weight: 500"
            >New Name:</label
          >
          <BaseInput
            id="new-item-name"
            v-model="newItemName"
            :placeholder="`Enter new ${itemToRename?.type} name`"
            @keyup.enter="executeRename"
          />
        </div>
      </template>
      <template #footer>
        <BaseButton @click="executeRename" type="primary">Rename</BaseButton>
      </template>
    </BaseModal>
  </div>
</template>

<style scoped>
.project-manager {
  display: flex;
  flex-direction: column;
  height: 100%;
  background-color: transparent;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 10px;
  border-bottom: 1px solid var(--theme-border);
  flex-shrink: 0;
}

.header h4 {
  margin: 0;
  color: var(--theme-text-primary);
  font-size: 0.95em;
  font-weight: 600;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 4px;
}

.header-action-btn {
  padding: 2px 6px !important;
}

.empty-state {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 20px;
  color: var(--theme-text-secondary);
}

.empty-state p {
  margin: 0 0 10px 0;
  font-size: 0.9em;
}

.empty-state-inner {
  color: var(--theme-text-secondary);
  text-align: center;
  padding: 8px;
  font-size: 0.8em;
}

.empty-state-inner p {
  margin: 0 0 6px 0;
}

.project-list {
  flex-grow: 1;
  overflow-y: auto;
  padding: 4px;
}

.project-item {
  margin-bottom: 2px;
}

.project-header {
  display: flex;
  align-items: center;
  padding: 6px 8px;
  cursor: pointer;
  transition: background-color 0.2s ease;
  gap: 6px;
  border-radius: 4px;
  position: relative;
  color: var(--theme-text-primary);
}

.project-header:hover {
  background-color: var(--theme-bg-hover);
}

.project-header.active {
  background-color: var(--theme-primary);
}

.project-header.active .project-name,
.project-header.active .icon-folder,
.project-header.active .icon-chevron {
  color: var(--theme-text-inverse);
}

.icon-chevron {
  font-size: 0.6em;
  color: var(--theme-text-secondary);
  transition: transform 0.2s ease-in-out;
  width: 10px;
  text-align: center;
}

.icon-chevron.open {
  transform: rotate(90deg);
}

.icon-folder {
  color: var(--theme-primary);
  font-size: 0.8em;
}

.project-header.active .icon-folder {
  color: var(--theme-text-inverse);
}

.project-name {
  flex-grow: 1;
  font-weight: 500;
  color: var(--theme-text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  font-size: 0.85em;
}

.project-actions {
  display: flex;
  align-items: center;
  margin-left: auto;
}

.action-btn {
  padding: 2px 4px;
  font-size: 0.85em;
  background-color: transparent;
  color: var(--theme-text-secondary);
  border: none;
  border-radius: 3px;
  opacity: 0;
  transition:
    opacity 0.2s ease,
    color 0.2s ease,
    background-color 0.2s ease;
  line-height: 1;
  cursor: pointer;
}

.project-header:hover .action-btn,
.graph-item:hover .action-btn,
.project-header.active .action-btn {
  opacity: 1;
}

.project-header.active .action-btn {
  color: var(--theme-text-inverse);
}

.action-btn:hover {
  background-color: var(--theme-border);
  color: var(--theme-text-primary);
}

.project-header.active .action-btn:hover {
  background-color: rgba(255, 255, 255, 0.2);
  color: white;
}

.graph-list {
  padding-left: 12px;
  overflow: hidden;
  border-left: 1px solid var(--theme-border);
  margin-left: 10px;
  padding-top: 2px;
  padding-bottom: 2px;
}

.slide-fade-enter-active,
.slide-fade-leave-active {
  transition: all 0.2s ease-out;
  max-height: 500px;
}
.slide-fade-enter-from,
.slide-fade-leave-to {
  max-height: 0;
  opacity: 0;
  transform: translateY(-10px);
}

.graph-item {
  display: flex;
  align-items: center;
  padding: 4px 8px;
  margin-top: 1px;
  cursor: pointer;
  transition:
    background-color 0.2s ease,
    color 0.2s ease;
  gap: 6px;
  border-radius: 4px;
  position: relative;
  color: var(--theme-text-primary);
}

.graph-item:hover {
  background-color: var(--theme-bg-hover);
}

.graph-item.active {
  background-color: var(--theme-primary);
}

.graph-item.active span,
.graph-item.active .icon-file {
  color: var(--theme-text-inverse);
}

.graph-item span {
  flex-grow: 1;
  font-size: 0.85em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--theme-text-primary);
}

.icon-file {
  font-size: 0.75em;
  color: var(--theme-text-secondary);
}

.graph-item.active .action-btn {
  color: var(--theme-text-inverse);
}

.graph-item.active .action-btn:hover {
  background-color: rgba(255, 255, 255, 0.2);
  color: white;
}

.graph-item .action-btn {
  margin-left: auto;
}

.context-menu {
  position: fixed;
  background-color: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  box-shadow: var(--shadow-md);
  border-radius: 6px;
  padding: 4px 0;
  z-index: 100000; /* Increased z-index to appear above sidebars */
  min-width: 160px;
}

.context-menu-item {
  padding: 6px 12px;
  cursor: pointer;
  font-size: 0.85em;
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--theme-text-primary);
  transition:
    background-color 0.2s ease,
    color 0.2s ease;
}

.context-menu-item:hover {
  background-color: var(--theme-primary);
  color: var(--theme-text-inverse);
}

.context-menu-item.danger:hover {
  background-color: var(--theme-danger);
  color: white;
}

.context-menu-item .fas {
  width: 14px;
  text-align: center;
}

.rename-body,
.confirm-body {
  padding: 10px 0;
}
</style>
