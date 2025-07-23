import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
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
  const currentProjectId = ref<string | null>(
    localStorage.getItem('doodlebugs-currentProjectId') || null
  );

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

  const renameProject = (projectId: string, newName: string) => {
    const project = projects.value.find(p => p.id === projectId);
    if (project && newName.trim()) {
        project.name = newName.trim();
        project.lastModified = Date.now();
        saveProjects();
    }
  };

  const selectProject = (projectId: string | null) => {
    currentProjectId.value = projectId;
    if (projectId) {
      localStorage.setItem('doodlebugs-currentProjectId', projectId);
    } else {
      localStorage.removeItem('doodlebugs-currentProjectId');
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
        selectProject(null);
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

  const renameGraphInProject = (projectId: string, graphId: string, newName: string) => {
    const project = projects.value.find(p => p.id === projectId);
    if (project && newName.trim()) {
        const graph = project.graphs.find(g => g.id === graphId);
        if (graph) {
            graph.name = newName.trim();
            graph.lastModified = Date.now();
            project.lastModified = Date.now();
            saveProjects();
        }
    }
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
    // Validate the persisted project ID - clear if no longer valid
    if (currentProjectId.value && !projects.value.some(p => p.id === currentProjectId.value)) {
      selectProject(null);
    }
  };

  return {
    projects,
    currentProjectId,
    currentProject,
    createProject,
    renameProject,
    selectProject,
    deleteProject,
    addGraphToProject,
    renameGraphInProject,
    deleteGraphFromProject,
    getGraphsForProject,
    loadProjects,
  };
});
