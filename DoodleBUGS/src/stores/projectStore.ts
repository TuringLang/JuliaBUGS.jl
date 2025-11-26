import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import { useGraphStore } from './graphStore';
import type { GridStyle } from './uiStore';

export interface GraphMeta {
  id: string;
  name: string;
  createdAt: number;
  lastModified: number;
  // Layout props
  x: number;
  y: number;
  width: number;
  height: number;
  // Code Panel Props
  showCodePanel?: boolean;
  codePanelX?: number;
  codePanelY?: number;
  codePanelWidth?: number;
  codePanelHeight?: number;
  // Per-graph Grid Settings
  gridEnabled?: boolean;
  gridSize?: number;
  gridStyle?: GridStyle;
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
      const offset = project.graphs.length * 40;
      
      const newGraphMeta: GraphMeta = {
        id: `graph_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        name: graphName,
        createdAt: Date.now(),
        lastModified: Date.now(),
        x: 100 + offset,
        y: 100 + offset,
        width: 600,
        height: 400,
        showCodePanel: false,
        codePanelWidth: 400,
        codePanelHeight: 400,
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

  const updateGraphLayout = (
    projectId: string, 
    graphId: string, 
    layout: Partial<{ 
        x: number; y: number; width: number; height: number; 
        showCodePanel: boolean; codePanelX: number; codePanelY: number; codePanelWidth: number; codePanelHeight: number;
        gridEnabled: boolean; gridSize: number; gridStyle: GridStyle;
    }>,
    shouldSave: boolean = true
  ) => {
    const project = projects.value.find(p => p.id === projectId);
    if (project) {
        const graph = project.graphs.find(g => g.id === graphId);
        if (graph) {
            if (layout.x !== undefined) graph.x = layout.x;
            if (layout.y !== undefined) graph.y = layout.y;
            if (layout.width !== undefined) graph.width = layout.width;
            if (layout.height !== undefined) graph.height = layout.height;
            
            if (layout.showCodePanel !== undefined) graph.showCodePanel = layout.showCodePanel;
            if (layout.codePanelX !== undefined) graph.codePanelX = layout.codePanelX;
            if (layout.codePanelY !== undefined) graph.codePanelY = layout.codePanelY;
            if (layout.codePanelWidth !== undefined) graph.codePanelWidth = layout.codePanelWidth;
            if (layout.codePanelHeight !== undefined) graph.codePanelHeight = layout.codePanelHeight;

            if (layout.gridEnabled !== undefined) graph.gridEnabled = layout.gridEnabled;
            if (layout.gridSize !== undefined) graph.gridSize = layout.gridSize;
            if (layout.gridStyle !== undefined) graph.gridStyle = layout.gridStyle;

            if (graph.showCodePanel && graph.codePanelX === undefined) {
                graph.codePanelX = graph.x + graph.width + 20;
                graph.codePanelY = graph.y;
                graph.codePanelWidth = 400;
                graph.codePanelHeight = graph.height;
            }

            if (shouldSave) {
              saveProjects();
            }
        }
    }
  }

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
      const loaded = JSON.parse(storedProjects) as Project[];
      loaded.forEach((p) => {
          if (p.graphs) {
              p.graphs.forEach((g, index) => {
                  if (g.x === undefined) g.x = 100 + (index * 40);
                  if (g.y === undefined) g.y = 100 + (index * 40);
                  if (g.width === undefined) g.width = 600;
                  if (g.height === undefined) g.height = 400;
              });
          }
      });
      projects.value = loaded;
    }
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
    updateGraphLayout,
    deleteGraphFromProject,
    getGraphsForProject,
    loadProjects,
    saveProjects,
  };
});
