# Undo/Redo Functionality in DoodleBUGS

## Overview

This implementation adds comprehensive undo/redo functionality to DoodleBUGS using the `cytoscape.js-undo-redo` extension. Users can now undo and redo graph operations including adding nodes, adding edges, deleting elements, and moving nodes.

## Features

### ✅ Implemented Features

1. **Undo/Redo Buttons**: Visual toolbar buttons with clear icons
2. **Keyboard Shortcuts**: 
   - `Ctrl+Z` for undo
   - `Ctrl+Shift+Z` or `Ctrl+Y` for redo
3. **Undoable Operations**:
   - Adding nodes
   - Adding edges
   - Deleting nodes and edges
   - Moving/dragging nodes
4. **State Synchronization**: Vue store stays in sync with cytoscape operations
5. **Visual Feedback**: Buttons are disabled when no actions are available

### 🎯 Key Components

#### 1. UndoRedoControls.vue
- Located: `src/components/ui/UndoRedoControls.vue`
- Provides undo/redo buttons with SVG icons
- Shows tooltips with keyboard shortcuts
- Buttons are automatically disabled when stacks are empty

#### 2. useUndoRedo.ts
- Located: `src/composables/useUndoRedo.ts`
- Main composable for undo/redo operations
- Handles keyboard shortcuts
- Syncs cytoscape state with Vue store
- Provides reactive state for UI components

#### 3. useGraphInstance.ts (Enhanced)
- Located: `src/composables/useGraphInstance.ts`
- Initializes cytoscape-undo-redo extension
- Provides low-level undo/redo API access
- Manages undo/redo instance lifecycle

#### 4. useGraphElements.ts (Enhanced)
- Located: `src/composables/useGraphElements.ts`
- Integrates element operations with undo/redo
- Ensures operations are properly tracked

## Installation

The implementation required adding the following dependency:

```bash
npm install cytoscape-undo-redo
```

## Usage

### For End Users

1. **Using Toolbar Buttons**:
   - Click the undo button (↶) to undo the last operation
   - Click the redo button (↷) to redo the last undone operation

2. **Using Keyboard Shortcuts**:
   - Press `Ctrl+Z` to undo
   - Press `Ctrl+Shift+Z` or `Ctrl+Y` to redo

3. **Visual Feedback**:
   - Buttons are grayed out when no actions are available
   - Tooltips show keyboard shortcuts

### For Developers

#### Using the composable:

```typescript
import { useUndoRedo } from '@/composables/useUndoRedo';

const { 
  canUndo, 
  canRedo, 
  performUndo, 
  performRedo, 
  resetStacks 
} = useUndoRedo();
```

#### Adding to components:

```vue
<template>
  <UndoRedoControls />
</template>

<script setup>
import UndoRedoControls from '@/components/ui/UndoRedoControls.vue';
</script>
```

## Technical Implementation

### Architecture

1. **Cytoscape Extension**: Uses `cytoscape-undo-redo` for core functionality
2. **Vue Integration**: Custom composables bridge cytoscape and Vue
3. **State Management**: Automatic synchronization between cytoscape and Pinia store
4. **Event Handling**: Global keyboard listeners for shortcuts

### Configuration

The undo-redo system is configured with:
- **Debug Mode**: Enabled for development (can be disabled in production)
- **Undoable Drag**: Node dragging operations are undoable
- **Unlimited Stack**: No limit on undo/redo history
- **Auto-sync**: Changes automatically sync with Vue store

### Integration Points

1. **MainLayout.vue**: Adds global keyboard shortcuts
2. **CanvasToolbar.vue**: Displays undo/redo buttons
3. **GraphEditor.vue**: All graph operations route through undo-redo system
4. **Graph Store**: Automatically updated when undo/redo operations occur

## File Structure

```
src/
├── components/
│   ├── ui/
│   │   └── UndoRedoControls.vue          # Undo/redo buttons
│   ├── canvas/
│   │   └── CanvasToolbar.vue             # Updated toolbar
│   └── layouts/
│       └── MainLayout.vue                # Global shortcuts
├── composables/
│   ├── useUndoRedo.ts                    # Main undo/redo logic
│   ├── useGraphInstance.ts               # Enhanced with undo-redo
│   └── useGraphElements.ts               # Enhanced with undo-redo
└── types/
    └── cytoscape-undo-redo.d.ts          # TypeScript definitions
```

## Testing

To test the functionality:

1. Start the development server: `npm run dev`
2. Open DoodleBUGS in your browser
3. Try the following operations:
   - Add some nodes
   - Connect nodes with edges
   - Move nodes around
   - Delete some elements
   - Use `Ctrl+Z` to undo operations
   - Use `Ctrl+Shift+Z` to redo operations

## Troubleshooting

### Common Issues

1. **Buttons not responding**: Check console for initialization messages
2. **Keyboard shortcuts not working**: Ensure MainLayout has focus
3. **State sync issues**: Check that operations go through the undo-redo system

### Debug Information

Enable debug mode by setting `isDebug: true` in `useGraphInstance.ts`. This will log all undo/redo operations to the console.

## Future Enhancements

Potential improvements for the future:

1. **Undo/Redo History Panel**: Show list of operations that can be undone
2. **Operation Descriptions**: Better labeling of operations in debug mode
3. **Selective Undo**: Ability to undo specific operations out of order
4. **Performance Optimization**: Limit stack size for large graphs
5. **Persistence**: Save undo/redo state across sessions

## Dependencies

- `cytoscape-undo-redo`: ^1.0.0+ (exact version managed by npm)
- All existing DoodleBUGS dependencies

## Compatibility

- Compatible with all existing DoodleBUGS features
- Works with all node types (stochastic, deterministic, constant, observed, plate)
- Integrates with existing graph layouts and styling
- Maintains compatibility with export/import functionality