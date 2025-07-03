import { defineStore } from 'pinia';
import { ref, computed, watch } from 'vue';
import { useGraphStore } from './graphStore';

export interface GraphMeta {
  id: string;
  name: string;
  createdAt: number;
  lastModified: number;
}

export interface Project {
  id: string;
  name: string;
  createdAt: number;
  lastModified: number;
  graphs: GraphMeta[];
}

export const useProjectStore = defineStore('project', () => {
  const projects = ref<Project[]>([]);
  const currentProjectId = ref<string | null>(null);

  const graphStore = useGraphStore();

  const createProject = (name: string) => {
    const newProject: Project = {
      id: `project_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
      name: name,
      createdAt: Date.now(),
      lastModified: Date.now(),
      graphs: [],
    };
    projects.value.push(newProject);
    saveProjects();
    selectProject(newProject.id);
  };

  const selectProject = (projectId: string | null) => {
    currentProjectId.value = projectId;
    if (projectId) {
      const project = projects.value.find(p => p.id === projectId);
      if (project && project.graphs.length > 0) {
        if (!graphStore.currentGraphId || !project.graphs.some(g => g.id === graphStore.currentGraphId)) {
            graphStore.selectGraph(project.graphs[0].id);
        }
      } else {
        graphStore.selectGraph(null);
      }
    } else {
      graphStore.selectGraph(null);
    }
  };

  const deleteProject = (projectId: string) => {
    const projectToDelete = projects.value.find(p => p.id === projectId);
    if (projectToDelete) {
      projectToDelete.graphs.forEach(graphMeta => {
        graphStore.deleteGraphContent(graphMeta.id);
      });
      projects.value = projects.value.filter(p => p.id !== projectId);
      if (currentProjectId.value === projectId) {
        currentProjectId.value = null;
        graphStore.selectGraph(null);
      }
      saveProjects();
    }
  };

  const currentProject = computed(() => {
    return projects.value.find(p => p.id === currentProjectId.value) || null;
  });

  const addGraphToProject = (projectId: string, graphName: string): GraphMeta | undefined => {
    const project = projects.value.find(p => p.id === projectId);
    if (project) {
      const newGraphMeta: GraphMeta = {
        id: `graph_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        name: graphName,
        createdAt: Date.now(),
        lastModified: Date.now(),
      };
      project.graphs.push(newGraphMeta);
      project.lastModified = Date.now();
      saveProjects();
      graphStore.createNewGraphContent(newGraphMeta.id);
      graphStore.selectGraph(newGraphMeta.id);
      return newGraphMeta;
    }
    return undefined;
  };

  const deleteGraphFromProject = (projectId: string, graphId: string) => {
    const project = projects.value.find(p => p.id === projectId);
    if (project) {
      project.graphs = project.graphs.filter(g => g.id !== graphId);
      project.lastModified = Date.now();
      saveProjects();
      graphStore.deleteGraphContent(graphId);
    }
  };

  const getGraphsForProject = (projectId: string): GraphMeta[] => {
    return projects.value.find(p => p.id === projectId)?.graphs || [];
  };

  const saveProjects = () => {
    localStorage.setItem('doodlebugs-projects', JSON.stringify(projects.value));
  };

  const loadProjects = () => {
    const storedProjects = localStorage.getItem('doodlebugs-projects');
    if (storedProjects) {
      projects.value = JSON.parse(storedProjects);
    }
  };

  watch(currentProjectId, (newProjectId) => {
    if (newProjectId) {
      const project = projects.value.find(p => p.id === newProjectId);
      if (project && project.graphs.length > 0) {
        if (!graphStore.currentGraphId || !project.graphs.some(g => g.id === graphStore.currentGraphId)) {
          graphStore.selectGraph(project.graphs[0].id);
        }
      } else {
        graphStore.selectGraph(null);
      }
    } else {
      graphStore.selectGraph(null);
    }
  }, { immediate: true });

  return {
    projects,
    currentProjectId,
    currentProject,
    createProject,
    selectProject,
    deleteProject,
    addGraphToProject,
    deleteGraphFromProject,
    getGraphsForProject,
    loadProjects,
  };
});
