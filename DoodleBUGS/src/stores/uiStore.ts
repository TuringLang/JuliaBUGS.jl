import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json';

export const useUiStore = defineStore('ui', () => {
  const activeRightTab = ref<RightSidebarTab>(
    (localStorage.getItem('doodlebugs-activeRightTab') as RightSidebarTab) || 'properties'
  );
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );

  const leftSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-leftSidebarWidth') || '330')
  );
  
  const rightSidebarWidth = ref<number>(
    parseInt(localStorage.getItem('doodlebugs-rightSidebarWidth') || '320')
  );

  watch(activeRightTab, (newTab) => {
    localStorage.setItem('doodlebugs-activeRightTab', newTab);
  });

  watch(isRightTabPinned, (isPinned) => {
    localStorage.setItem('doodlebugs-isRightTabPinned', isPinned.toString());
  });

  watch(leftSidebarWidth, (newWidth) => {
    localStorage.setItem('doodlebugs-leftSidebarWidth', newWidth.toString());
  });

  watch(rightSidebarWidth, (newWidth) => {
    localStorage.setItem('doodlebugs-rightSidebarWidth', newWidth.toString());
  });

  const setActiveRightTab = (tab: RightSidebarTab) => {
    activeRightTab.value = tab;
  };

  const toggleRightTabPinned = () => {
    isRightTabPinned.value = !isRightTabPinned.value;
  };

  return {
    activeRightTab,
    isRightTabPinned,
    setActiveRightTab,
    toggleRightTabPinned,
    leftSidebarWidth,
    rightSidebarWidth,
  };
});
