import { defineStore } from 'pinia';
import { ref, watch } from 'vue';
import { nodeDefinitions, defaultEdgeStyles, type EdgeStyle } from '../config/nodeDefinitions';

export type RightSidebarTab = 'properties' | 'code' | 'json' | 'script';
export type LeftSidebarTab = 'project' | 'palette' | 'data' | 'settings' | 'view' | 'export' | 'connect' | 'help';
export type GridStyle = 'dots' | 'lines';

export interface NodeStyle {
    backgroundColor: string;
    borderColor: string;
    borderWidth: number;
    borderStyle: string;
    backgroundOpacity: number;
    shape: string;
    width: number;
    height: number;
}

export const useUiStore = defineStore('ui', () => {
  // Right Sidebar State
  const storedRight = localStorage.getItem('doodlebugs-activeRightTab') as string | null;
  let initialRightTab: RightSidebarTab = 'properties';
  
  if (storedRight === 'properties' || storedRight === 'code' || storedRight === 'json' || storedRight === 'script') {
      initialRightTab = storedRight as RightSidebarTab;
  } else if (storedRight === 'connection') {
      initialRightTab = 'properties'; // Fallback since connection is removed
  }

  const activeRightTab = ref<RightSidebarTab>(initialRightTab);
  
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );

  // Default to closed (false) if not set or not 'true'
  const isRightSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightSidebarOpen') === 'true'
  );

  // Left Sidebar State
  const activeLeftTab = ref<LeftSidebarTab>(
    (localStorage.getItem('doodlebugs-activeLeftTab') as LeftSidebarTab) || 'project'
  );
  // Default to closed (false) if not set or not 'true'
  const isLeftSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isLeftSidebarOpen') === 'true'
  );

  // Grid Settings
  const canvasGridStyle = ref<GridStyle>(
    (localStorage.getItem('doodlebugs-canvasGridStyle') as GridStyle) || 'lines'
  );

  // Theme State
  const isDarkMode = ref<boolean>(localStorage.getItem('doodlebugs-darkMode') === 'true');

  // Node Styles
  const storedStyles = localStorage.getItem('doodlebugs-nodeStyles');
  const initialNodeStyles: Record<string, NodeStyle> = {};
  
  // Initialize from definitions first
  nodeDefinitions.forEach(def => {
      initialNodeStyles[def.nodeType] = { ...def.defaultStyle };
  });

  // Override with stored
  if (storedStyles) {
      try {
          const parsed = JSON.parse(storedStyles);
          Object.keys(initialNodeStyles).forEach(key => {
              if (parsed[key]) {
                  initialNodeStyles[key] = { ...initialNodeStyles[key], ...parsed[key] };
              }
          });
      } catch (e) {
          console.error("Failed to load node styles", e);
      }
  }

  const nodeStyles = ref<Record<string, NodeStyle>>(initialNodeStyles);

  // Edge Styles
  const storedEdgeStyles = localStorage.getItem('doodlebugs-edgeStyles');
  let initialEdgeStyles = { ...defaultEdgeStyles };

  if (storedEdgeStyles) {
      try {
          initialEdgeStyles = { ...initialEdgeStyles, ...JSON.parse(storedEdgeStyles) };
      } catch (e) {
          console.error("Failed to load edge styles", e);
      }
  }

  const edgeStyles = ref<Record<'stochastic' | 'deterministic', EdgeStyle>>(initialEdgeStyles);

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
  watch(activeLeftTab, (newTab) => {
    localStorage.setItem('doodlebugs-activeLeftTab', newTab);
  });
  watch(isLeftSidebarOpen, (isOpen) => {
    localStorage.setItem('doodlebugs-isLeftSidebarOpen', isOpen.toString());
  });
  watch(canvasGridStyle, (style) => {
    localStorage.setItem('doodlebugs-canvasGridStyle', style);
  });
  watch(isDarkMode, (val) => {
    localStorage.setItem('doodlebugs-darkMode', String(val));
  });
  watch(nodeStyles, (styles) => {
      localStorage.setItem('doodlebugs-nodeStyles', JSON.stringify(styles));
  }, { deep: true });
  watch(edgeStyles, (styles) => {
      localStorage.setItem('doodlebugs-edgeStyles', JSON.stringify(styles));
  }, { deep: true });

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

  const toggleDarkMode = () => {
    isDarkMode.value = !isDarkMode.value;
  };

  return {
    activeRightTab,
    isRightTabPinned,
    isRightSidebarOpen,
    setActiveRightTab,
    toggleRightTabPinned,
    toggleRightSidebar,
    activeLeftTab,
    isLeftSidebarOpen,
    handleLeftTabClick,
    toggleLeftSidebar,
    canvasGridStyle,
    isDarkMode,
    toggleDarkMode,
    nodeStyles,
    edgeStyles
  };
});
