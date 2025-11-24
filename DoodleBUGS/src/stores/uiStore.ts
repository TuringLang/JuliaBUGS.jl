import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json' | 'connection';
// Expanded to include all new sidebar menu items
export type LeftSidebarTab = 'project' | 'palette' | 'data' | 'settings' | 'view' | 'export' | 'connect' | 'help';
export type GridStyle = 'dots' | 'lines';

export const useUiStore = defineStore('ui', () => {
  // Right Sidebar State
  const storedRight = localStorage.getItem('doodlebugs-activeRightTab') as RightSidebarTab | 'execution' | null;
  const initialRightTab: RightSidebarTab = storedRight === 'execution' ? 'connection' : (storedRight as RightSidebarTab) || 'code';
  const activeRightTab = ref<RightSidebarTab>(initialRightTab);
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );
  // Default to closed (false) if not set or not 'true'
  const isRightSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightSidebarOpen') === 'true'
  );
  const rightSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-rightSidebarWidth') || '310')
  );

  // Left Sidebar State
  const activeLeftTab = ref<LeftSidebarTab>(
    (localStorage.getItem('doodlebugs-activeLeftTab') as LeftSidebarTab) || 'project'
  );
  // Default to closed (false) if not set or not 'true'
  const isLeftSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isLeftSidebarOpen') === 'true'
  );
  const leftSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-leftSidebarWidth') || '265')
  );

  // Canvas View Mode
  const isMultiCanvasView = ref<boolean>(
    localStorage.getItem('doodlebugs-isMultiCanvasView') === 'true'
  );
  
  // Pinned Graph State (Fullscreen mode)
  const pinnedGraphId = ref<string | null>(
    localStorage.getItem('doodlebugs-pinnedGraphId') || null
  );

  // Grid Settings
  const isWorkspaceGridEnabled = ref<boolean>(
    localStorage.getItem('doodlebugs-isWorkspaceGridEnabled') !== 'false'
  );
  const workspaceGridStyle = ref<GridStyle>(
    (localStorage.getItem('doodlebugs-workspaceGridStyle') as GridStyle) || 'dots'
  );
  const canvasGridStyle = ref<GridStyle>(
    (localStorage.getItem('doodlebugs-canvasGridStyle') as GridStyle) || 'lines'
  );
  const workspaceGridSize = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-workspaceGridSizeVal') || '20')
  );

  // Watchers for Persistence
  watch(activeRightTab, (newTab) => {
    localStorage.setItem('doodlebugs-activeRightTab', newTab);
  });
  watch(isRightTabPinned, (isPinned) => {
    localStorage.setItem('doodlebugs-isRightTabPinned', isPinned.toString());
  });
  watch(isRightSidebarOpen, (isOpen) => {
    localStorage.setItem('doodlebugs-isRightSidebarOpen', isOpen.toString());
  });
  watch(rightSidebarWidth, (newWidth) => {
    localStorage.setItem('doodlebugs-rightSidebarWidth', newWidth.toString());
  });
  watch(activeLeftTab, (newTab) => {
    localStorage.setItem('doodlebugs-activeLeftTab', newTab);
  });
  watch(isLeftSidebarOpen, (isOpen) => {
    localStorage.setItem('doodlebugs-isLeftSidebarOpen', isOpen.toString());
  });
  watch(leftSidebarWidth, (newWidth) => {
    localStorage.setItem('doodlebugs-leftSidebarWidth', newWidth.toString());
  });
  watch(isMultiCanvasView, (isMulti) => {
    localStorage.setItem('doodlebugs-isMultiCanvasView', isMulti.toString());
  });
  watch(pinnedGraphId, (id) => {
    if (id) {
        localStorage.setItem('doodlebugs-pinnedGraphId', id);
    } else {
        localStorage.removeItem('doodlebugs-pinnedGraphId');
    }
  });
  watch(isWorkspaceGridEnabled, (enabled) => {
    localStorage.setItem('doodlebugs-isWorkspaceGridEnabled', enabled.toString());
  });
  watch(workspaceGridStyle, (style) => {
    localStorage.setItem('doodlebugs-workspaceGridStyle', style);
  });
  watch(canvasGridStyle, (style) => {
    localStorage.setItem('doodlebugs-canvasGridStyle', style);
  });
  watch(workspaceGridSize, (size) => {
    localStorage.setItem('doodlebugs-workspaceGridSizeVal', size.toString());
  });

  // Actions
  const setActiveRightTab = (tab: RightSidebarTab) => {
    activeRightTab.value = tab;
    if (!isRightSidebarOpen.value) {
        isRightSidebarOpen.value = true;
    }
  };
  const toggleRightTabPinned = () => {
    isRightTabPinned.value = !isRightTabPinned.value;
  };
  const toggleRightSidebar = () => {
    isRightSidebarOpen.value = !isRightSidebarOpen.value;
  };

  const handleLeftTabClick = (tab: LeftSidebarTab) => {
    // If clicking the same tab, toggle sidebar visibility
    // If sidebar is closed, open it and set tab
    if (activeLeftTab.value === tab && isLeftSidebarOpen.value) {
      isLeftSidebarOpen.value = false;
    } else {
      isLeftSidebarOpen.value = true;
      activeLeftTab.value = tab;
    }
  };

  const toggleLeftSidebar = () => {
    isLeftSidebarOpen.value = !isLeftSidebarOpen.value;
  };

  const toggleCanvasView = () => {
    isMultiCanvasView.value = !isMultiCanvasView.value;
  };

  const setPinnedGraph = (graphId: string | null) => {
    pinnedGraphId.value = graphId;
  };

  return {
    activeRightTab,
    isRightTabPinned,
    isRightSidebarOpen,
    rightSidebarWidth,
    setActiveRightTab,
    toggleRightTabPinned,
    toggleRightSidebar,
    activeLeftTab,
    isLeftSidebarOpen,
    leftSidebarWidth,
    handleLeftTabClick,
    toggleLeftSidebar,
    isMultiCanvasView,
    toggleCanvasView,
    isWorkspaceGridEnabled,
    workspaceGridStyle,
    canvasGridStyle,
    workspaceGridSize,
    pinnedGraphId,
    setPinnedGraph
  };
});
