import { ref, computed } from 'vue';
import { useGraphInstance } from './useGraphInstance';
import { useGraphStore } from '../stores/graphStore';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

export function useUndoRedo() {
  const { undo, redo, isUndoStackEmpty, isRedoStackEmpty, resetUndoRedoStack, getCyInstance, getUndoRedoInstance } = useGraphInstance();
  const graphStore = useGraphStore();
  
  // Reactive state for UI updates
  const canUndo = ref(false);
  const canRedo = ref(false);

  // Update the state by checking the actual undo-redo instance
  const updateUndoRedoState = () => {
    try {
      const newCanUndo = !isUndoStackEmpty();
      const newCanRedo = !isRedoStackEmpty();
      
      if (newCanUndo !== canUndo.value || newCanRedo !== canRedo.value) {
        canUndo.value = newCanUndo;
        canRedo.value = newCanRedo;
        console.log(`Undo/Redo state updated: undo=${newCanUndo}, redo=${newCanRedo}`);
      }
    } catch (error) {
      console.warn('Failed to update undo/redo state:', error);
      canUndo.value = false;
      canRedo.value = false;
    }
  };

  // Perform undo operation
  const performUndo = (): boolean => {
    console.log('Attempting undo...');
    try {
      const result = undo();
      console.log(`Undo result: ${result}`);
      updateUndoRedoState();
      return result;
    } catch (error) {
      console.error('Undo failed:', error);
      return false;
    }
  };

  // Perform redo operation
  const performRedo = (): boolean => {
    console.log('Attempting redo...');
    try {
      const result = redo();
      console.log(`Redo result: ${result}`);
      updateUndoRedoState();
      return result;
    } catch (error) {
      console.error('Redo failed:', error);
      return false;
    }
  };

  // Reset undo/redo stacks
  const resetStacks = (): void => {
    try {
      resetUndoRedoStack();
      updateUndoRedoState();
      console.log('Reset undo/redo stacks');
    } catch (error) {
      console.warn('Failed to reset stacks:', error);
    }
  };

  // Keyboard shortcuts handler
  const handleKeyboardShortcuts = (event: KeyboardEvent): void => {
    // Only handle shortcuts if not typing in an input field
    const target = event.target as HTMLElement;
    if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.contentEditable === 'true') {
      return;
    }

    // Ctrl+Z for undo
    if (event.ctrlKey && event.key === 'z' && !event.shiftKey) {
      event.preventDefault();
      console.log('Keyboard shortcut: Ctrl+Z (Undo)');
      performUndo();
    }
    // Ctrl+Shift+Z or Ctrl+Y for redo
    else if ((event.ctrlKey && event.shiftKey && event.key === 'Z') || 
             (event.ctrlKey && event.key === 'y')) {
      event.preventDefault();
      console.log('Keyboard shortcut: Ctrl+Shift+Z or Ctrl+Y (Redo)');
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
    handleKeyboardShortcuts
  };
}