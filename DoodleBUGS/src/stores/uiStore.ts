import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json';
export type LeftSidebarTab = 'project' | 'palette' | 'data';

export const useUiStore = defineStore('ui', () => {
  // Right Sidebar State
  const activeRightTab = ref<RightSidebarTab>(
    (localStorage.getItem('doodlebugs-activeRightTab') as RightSidebarTab) || 'code'
  );
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );
  const isRightSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightSidebarOpen') !== 'false' // Default to true
  );
  const rightSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-rightSidebarWidth') || '320')
  );

  // Left Sidebar State
  const activeLeftTab = ref<LeftSidebarTab>(
    (localStorage.getItem('doodlebugs-activeLeftTab') as LeftSidebarTab) || 'project'
  );
  const isLeftSidebarOpen = ref<boolean>(
    localStorage.getItem('doodlebugs-isLeftSidebarOpen') !== 'false' // Default to true
  );
  const leftSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-leftSidebarWidth') || '330')
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

  // Actions
  const setActiveRightTab = (tab: RightSidebarTab) => {
    activeRightTab.value = tab;
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

  return {
    // Right Sidebar
    activeRightTab,
    isRightTabPinned,
    isRightSidebarOpen,
    rightSidebarWidth,
    setActiveRightTab,
    toggleRightTabPinned,
    toggleRightSidebar,
    // Left Sidebar
    activeLeftTab,
    isLeftSidebarOpen,
    leftSidebarWidth,
    handleLeftTabClick,
    toggleLeftSidebar,
  };
});
