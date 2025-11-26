import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json' | 'connection';
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

  // Code Panel State
  const isCodePanelOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isCodePanelOpen') === 'true'
  );

  // Theme State
  const isDarkMode = ref<boolean>(localStorage.getItem('doodlebugs-darkMode') === 'true');

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
  watch(isCodePanelOpen, (isOpen) => {
    localStorage.setItem('doodlebugs-isCodePanelOpen', String(isOpen));
  });
  watch(isDarkMode, (val) => {
    localStorage.setItem('doodlebugs-darkMode', String(val));
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

  const toggleCodePanel = () => {
    isCodePanelOpen.value = !isCodePanelOpen.value;
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
    isCodePanelOpen,
    toggleCodePanel,
    isDarkMode,
    toggleDarkMode
  };
});
