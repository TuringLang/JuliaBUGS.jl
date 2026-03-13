import { useGraphStore } from '../stores/graphStore'
import { useGraphInstance } from './useGraphInstance'
import { useGraphLayout } from './useGraphLayout'

const ZOOM_IN_FACTOR = 1.2
const ZOOM_OUT_FACTOR = 0.8

export function useViewportActions() {
  const graphStore = useGraphStore()
  const { getCyInstance, getUndoRedoInstance } = useGraphInstance()
  const { smartFit, applyLayoutWithFit } = useGraphLayout()

  const handleUndo = () => {
    if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.undo()
  }

  const handleRedo = () => {
    if (graphStore.currentGraphId) getUndoRedoInstance(graphStore.currentGraphId)?.redo()
  }

  const handleZoomIn = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.zoom(cy.zoom() * ZOOM_IN_FACTOR)
    }
  }

  const handleZoomOut = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) cy.zoom(cy.zoom() * ZOOM_OUT_FACTOR)
    }
  }

  const handleFit = () => {
    if (graphStore.currentGraphId) {
      const cy = getCyInstance(graphStore.currentGraphId)
      if (cy) smartFit(cy, true)
    }
  }

  const handleGraphLayout = (layoutName: string) => {
    const cy = graphStore.currentGraphId ? getCyInstance(graphStore.currentGraphId) : null
    if (!cy) return
    applyLayoutWithFit(cy, layoutName)
    if (graphStore.currentGraphId)
      graphStore.updateGraphLayout(graphStore.currentGraphId, layoutName)
  }

  return {
    handleUndo,
    handleRedo,
    handleZoomIn,
    handleZoomOut,
    handleFit,
    handleGraphLayout,
    getCyInstance,
    getUndoRedoInstance,
    smartFit,
  }
}
