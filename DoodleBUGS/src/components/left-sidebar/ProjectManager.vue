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
  <div class="db-project-manager">
    <div class="db-panel-header">
      <h4>Projects</h4>
      <div class="db-header-actions">
        <BaseButton
          @click="handleNewGraph"
          type="ghost"
          size="small"
          class="db-action-icon-btn"
          title="New Graph in Current Project"
          :disabled="!currentProject"
        >
          <i class="fas fa-hexagon-nodes"></i>
        </BaseButton>
        <BaseButton
          @click="handleNewProject"
          type="ghost"
          size="small"
          class="db-action-icon-btn"
          title="New Project"
        >
          <i class="fas fa-folder" style="color: #10b981"></i>
        </BaseButton>
      </div>
    </div>

    <!-- Empty state namespaced -->
    <div v-if="projectStore.projects.length === 0" class="db-empty-state">
      <p>No projects yet.</p>
      <BaseButton @click="handleNewProject" type="primary">Create New Project</BaseButton>
    </div>

    <!-- Project list structure namespaced -->
    <div v-else class="db-project-list">
      <div v-for="project in projectStore.projects" :key="project.id" class="db-project-item">
        <div
          class="db-project-header"
          @click="projectStore.selectProject(project.id)"
          @touchend.prevent="projectStore.selectProject(project.id)"
          :class="{ 'db-active': projectStore.currentProjectId === project.id }"
        >
          <i
            class="db-icon-chevron fas fa-chevron-right"
            :class="{ 'db-open': projectStore.currentProjectId === project.id }"
          ></i>
          <i class="db-icon-folder fas fa-folder"></i>
          <span class="db-project-name">{{ project.name }}</span>
          <div class="db-project-actions">
            <button
              @click.stop="openContextMenu($event, 'project', project.id)"
              class="db-context-trigger-btn"
            >
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
        </div>
        <transition name="slide-fade">
          <div v-if="projectStore.currentProject?.id === project.id" class="db-graph-list">
            <div
              v-for="graph in currentProjectGraphs"
              :key="graph.id"
              class="db-graph-item"
              :class="{ 'db-active': graphStore.currentGraphId === graph.id }"
              @click="selectGraph(graph.id)"
              @touchend.prevent="selectGraph(graph.id)"
            >
              <i class="db-icon-file fas fa-hexagon-nodes"></i>
              <span>{{ graph.name }}</span>
              <button
                @click.stop="openContextMenu($event, 'graph', graph.id)"
                class="db-context-trigger-btn"
              >
                <i class="fas fa-ellipsis-v"></i>
              </button>
            </div>
            <div v-if="currentProjectGraphs.length === 0" class="db-empty-state-inner">
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
        class="db-context-menu"
        :style="{ top: `${contextMenu.y}px`, left: `${contextMenu.x}px` }"
      >
        <template v-if="contextMenu.type === 'project'">
          <div class="db-context-menu-item" @click="handleNewGraph">
            <i class="fas fa-hexagon-nodes"></i> New Graph
          </div>
          <div
            class="db-context-menu-item"
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
            class="db-context-menu-item db-danger"
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
            class="db-context-menu-item"
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
            class="db-context-menu-item db-danger"
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
        <div class="db-confirm-body">
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
        <div class="db-rename-body">
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
/*
  CRITICAL: All classes MUST have the 'db-' prefix (DoodleBUGS).
  This acts as a namespace to prevent collision with host application CSS
  when running as a widget.
*/

.db-project-manager {
  display: flex;
  flex-direction: column;
  height: 100%;
  background-color: transparent;
}

.db-panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 10px;
  border-bottom: 1px solid var(--theme-border);
  flex-shrink: 0;
}

.db-panel-header h4 {
  margin: 0;
  color: var(--theme-text-primary);
  font-size: 0.95em;
  font-weight: 600;
}

.db-header-actions {
  display: flex;
  align-items: center;
  gap: 4px;
}

.db-action-icon-btn {
  padding: 2px 6px !important;
}

.db-empty-state {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 20px;
  color: var(--theme-text-secondary);
}

.db-empty-state p {
  margin: 0 0 10px 0;
  font-size: 0.9em;
}

.db-empty-state-inner {
  color: var(--theme-text-secondary);
  text-align: center;
  padding: 8px;
  font-size: 0.8em;
}

.db-empty-state-inner p {
  margin: 0 0 6px 0;
}

.db-project-list {
  flex-grow: 1;
  overflow-y: auto;
  padding: 4px;
}

.db-project-item {
  margin-bottom: 2px;
}

.db-project-header {
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

.db-project-header:hover {
  background-color: var(--theme-bg-hover);
}

.db-project-header.db-active {
  background-color: var(--theme-primary);
}

.db-project-header.db-active .db-project-name,
.db-project-header.db-active .db-icon-folder,
.db-project-header.db-active .db-icon-chevron {
  color: var(--theme-text-inverse);
}

.db-icon-chevron {
  font-size: 0.6em;
  color: var(--theme-text-secondary);
  transition: transform 0.2s ease-in-out;
  width: 10px;
  text-align: center;
}

.db-icon-chevron.db-open {
  transform: rotate(90deg);
}

.db-icon-folder {
  color: var(--theme-primary);
  font-size: 0.8em;
}

.db-project-header.db-active .db-icon-folder {
  color: var(--theme-text-inverse);
}

.db-project-name {
  flex-grow: 1;
  font-weight: 500;
  color: var(--theme-text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  font-size: 0.85em;
}

.db-project-actions {
  display: flex;
  align-items: center;
  margin-left: auto;
}

.db-context-trigger-btn {
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

.db-project-header:hover .db-context-trigger-btn,
.db-graph-item:hover .db-context-trigger-btn,
.db-project-header.db-active .db-context-trigger-btn {
  opacity: 1;
}

.db-project-header.db-active .db-context-trigger-btn {
  color: var(--theme-text-inverse);
}

.db-context-trigger-btn:hover {
  background-color: var(--theme-border);
  color: var(--theme-text-primary);
}

.db-project-header.db-active .db-context-trigger-btn:hover {
  background-color: rgba(255, 255, 255, 0.2);
  color: white;
}

.db-graph-list {
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

.db-graph-item {
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

.db-graph-item:hover {
  background-color: var(--theme-bg-hover);
}

.db-graph-item.db-active {
  background-color: var(--theme-primary);
}

.db-graph-item.db-active span,
.db-graph-item.db-active .db-icon-file {
  color: var(--theme-text-inverse);
}

.db-graph-item span {
  flex-grow: 1;
  font-size: 0.85em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: var(--theme-text-primary);
}

.db-icon-file {
  font-size: 0.75em;
  color: var(--theme-text-secondary);
}

.db-graph-item.db-active .db-context-trigger-btn {
  color: var(--theme-text-inverse);
}

.db-graph-item.db-active .db-context-trigger-btn:hover {
  background-color: rgba(255, 255, 255, 0.2);
  color: white;
}

.db-graph-item .db-context-trigger-btn {
  margin-left: auto;
}

.db-context-menu {
  position: fixed;
  background-color: var(--theme-bg-panel);
  border: 1px solid var(--theme-border);
  box-shadow: var(--shadow-md);
  border-radius: 6px;
  padding: 4px 0;
  z-index: 100000; /* Increased z-index to appear above sidebars */
  min-width: 160px;
}

.db-context-menu-item {
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

.db-context-menu-item:hover {
  background-color: var(--theme-primary);
  color: var(--theme-text-inverse);
}

.db-context-menu-item.db-danger:hover {
  background-color: var(--theme-danger);
  color: white;
}

.db-context-menu-item .fas {
  width: 14px;
  text-align: center;
}

.db-rename-body,
.db-confirm-body {
  padding: 10px 0;
}
</style>
