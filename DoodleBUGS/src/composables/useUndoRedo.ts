import { ref, computed } from 'vue';
import { useGraphInstance } from './useGraphInstance';
import { useGraphStore } from '../stores/graphStore';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

export function useUndoRedo() {
  const { undo, redo, isUndoStackEmpty, isRedoStackEmpty, resetUndoRedoStack, getCyInstance } = useGraphInstance();
  const graphStore = useGraphStore();
  
  // Reactive state for UI updates
  const canUndo = ref(false);
  const canRedo = ref(false);

  // Sync cytoscape elements with Vue store
  const syncCytoscapeWithStore = () => {
    try {
      const cy = getCyInstance();
      if (!cy || !graphStore.currentGraphId) return;

      const cytoscapeElements: GraphElement[] = [];
      
      // Get nodes from cytoscape
      cy.nodes().forEach(node => {
        const nodeData: GraphNode = {
          id: node.id(),
          type: 'node',
          name: node.data('name') || node.id(),
          nodeType: node.data('nodeType') || 'stochastic',
          position: node.position(),
          parent: node.data('parent'),
          distribution: node.data('distribution'),
          param1: node.data('param1'),
          param2: node.data('param2'),
          param3: node.data('param3'),
          isObserved: node.data('isObserved'),
          observedValue: node.data('observedValue'),
          expression: node.data('expression'),
          constantValue: node.data('constantValue'),
          loopVariable: node.data('loopVariable'),
          loopRange: node.data('loopRange'),
          indices: node.data('indices'),
          hasError: node.data('hasError')
        };
        cytoscapeElements.push(nodeData);
      });

      // Get edges from cytoscape
      cy.edges().forEach(edge => {
        const edgeData: GraphEdge & { relationshipType?: 'stochastic' | 'deterministic' } = {
          id: edge.id(),
          type: 'edge',
          source: edge.source().id(),
          target: edge.target().id(),
          relationshipType: (edge.data() as any).relationshipType || 'stochastic',
          name: (edge.data() as any).name
        };
        cytoscapeElements.push(edgeData);
      });

      // Update the store
      graphStore.updateGraphElements(graphStore.currentGraphId, cytoscapeElements);
    } catch (error) {
      console.warn('⚠️ Failed to sync cytoscape with store:', error);
    }
  };

  // Update the state
  const updateUndoRedoState = () => {
    canUndo.value = !isUndoStackEmpty();
    canRedo.value = !isRedoStackEmpty();
  };

  // Perform undo operation
  const performUndo = (): boolean => {
    const result = undo();
    if (result) {
      syncCytoscapeWithStore();
    }
    updateUndoRedoState();
    return result;
  };

  // Perform redo operation
  const performRedo = (): boolean => {
    const result = redo();
    if (result) {
      syncCytoscapeWithStore();
    }
    updateUndoRedoState();
    return result;
  };

  // Reset undo/redo stacks
  const resetStacks = (): void => {
    resetUndoRedoStack();
    updateUndoRedoState();
  };

  // Keyboard shortcuts handler
  const handleKeyboardShortcuts = (event: KeyboardEvent): void => {
    // Ctrl+Z for undo
    if (event.ctrlKey && event.key === 'z' && !event.shiftKey) {
      event.preventDefault();
      performUndo();
    }
    // Ctrl+Shift+Z or Ctrl+Y for redo
    else if ((event.ctrlKey && event.shiftKey && event.key === 'Z') || 
             (event.ctrlKey && event.key === 'y')) {
      event.preventDefault();
      performRedo();
    }
  };

  return {
    canUndo: computed(() => canUndo.value),
    canRedo: computed(() => canRedo.value),
    performUndo,
    performRedo,
    resetStacks,
    updateUndoRedoState,
    handleKeyboardShortcuts,
    syncCytoscapeWithStore
  };
}