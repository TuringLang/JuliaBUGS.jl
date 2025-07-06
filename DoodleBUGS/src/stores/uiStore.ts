import { defineStore } from 'pinia';
import { ref } from 'vue';

export type RightSidebarTab = 'properties' | 'code' | 'json';

export const useUiStore = defineStore('ui', () => {
  const activeRightTab = ref<RightSidebarTab>(
    (localStorage.getItem('doodlebugs-activeRightTab') as RightSidebarTab) || 'properties'
  );
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem('doodlebugs-isRightTabPinned') === 'true'
  );

  const setActiveRightTab = (tab: RightSidebarTab) => {
    activeRightTab.value = tab;
    localStorage.setItem('doodlebugs-activeRightTab', tab);
  };

  const toggleRightTabPinned = () => {
    isRightTabPinned.value = !isRightTabPinned.value;
    localStorage.setItem('doodlebugs-isRightTabPinned', isRightTabPinned.value.toString());
  };

  return {
    activeRightTab,
    isRightTabPinned,
    setActiveRightTab,
    toggleRightTabPinned,
  };
});
