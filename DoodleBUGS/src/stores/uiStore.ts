import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json' | 'connection';
export type LeftSidebarTab = 'project' | 'palette' | 'data' | 'settings';

export const useUiStore = defineStore('ui', () => {
  // Right Sidebar State
  // Normalize legacy stored value 'execution' to 'connection'
  const storedRight = localStorage.getItem('doodlebugs-activeRightTab') as RightSidebarTab | 'execution' | null;
  const initialRightTab: RightSidebarTab = storedRight === 'execution' ? 'connection' : (storedRight as RightSidebarTab) || 'code';
  const activeRightTab = ref<RightSidebarTab>(initialRightTab);
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );
  const isRightSidebarOpen = ref<boolean>(
    typeof window !== 'undefined' && window.innerWidth <= 768
      ? false
      : localStorage.getItem('doodlebugs-isRightSidebarOpen') !== 'false'
  );
  const rightSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-rightSidebarWidth') || '400') // Increased default width
  );

  // Left Sidebar State
  const activeLeftTab = ref<LeftSidebarTab>(
    (localStorage.getItem('doodlebugs-activeLeftTab') as LeftSidebarTab) || 'project'
  );
  const isLeftSidebarOpen = ref<boolean>(
    typeof window !== 'undefined' && window.innerWidth <= 768
      ? false
      : localStorage.getItem('doodlebugs-isLeftSidebarOpen') !== 'false'
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
  };
});
