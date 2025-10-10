<template>
  <div class="undo-redo-controls">
    <button 
      class="undo-btn toolbar-btn"
      :disabled="!canUndo"
      @click="handleUndo"
      title="Undo (Ctrl+Z)"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M3 7v6h6"/>
        <path d="M21 17a9 9 0 00-9-9 9 9 0 00-6 2.3L3 13"/>
      </svg>
    </button>
    
    <button 
      class="redo-btn toolbar-btn"
      :disabled="!canRedo"
      @click="handleRedo"
      title="Redo (Ctrl+Shift+Z)"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 7v6h-6"/>
        <path d="M3 17a9 9 0 019-9 9 9 0 016 2.3L21 13"/>
      </svg>
    </button>
  </div>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue';
import { useUndoRedo } from '../../composables/useUndoRedo';

const { canUndo, canRedo, performUndo, performRedo, updateUndoRedoState } = useUndoRedo();

let interval: number;

// Update state when component mounts
onMounted(() => {
  updateUndoRedoState();
  
  // Set up periodic state updates to ensure buttons stay in sync
  interval = setInterval(updateUndoRedoState, 500);
});

onUnmounted(() => {
  if (interval) {
    clearInterval(interval);
  }
});

const handleUndo = () => {
  console.log('Undo button clicked');
  const result = performUndo();
  console.log(`Undo button result: ${result}`);
};

const handleRedo = () => {
  console.log('Redo button clicked');
  const result = performRedo();
  console.log(`Redo button result: ${result}`);
};
</script>

<style scoped>
.undo-redo-controls {
  display: flex;
  gap: 4px;
  align-items: center;
}

.toolbar-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 8px;
  border: 1px solid #ddd;
  background: white;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 14px;
  min-width: 32px;
  min-height: 32px;
}

.toolbar-btn:hover:not(:disabled) {
  background: #f5f5f5;
  border-color: #999;
}

.toolbar-btn:active:not(:disabled) {
  background: #e5e5e5;
}

.toolbar-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
  background: #f9f9f9;
}

.toolbar-btn svg {
  width: 16px;
  height: 16px;
}
</style>