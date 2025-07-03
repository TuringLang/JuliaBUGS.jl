import { ref, computed, watch } from 'vue';
import type { Core } from 'cytoscape';

export function useGridSnapping(getCyInstance: () => Core | null) {
  const isGridEnabledRef = ref<boolean>(false);
  const gridSizeRef = ref<number>(20);

  const cssGridSize = computed<string>(() => `${gridSizeRef.value}px`);

  const updateGridBackground = () => {
    const cy = getCyInstance();
    if (cy) {
      const container = cy.container();
      if (container) {
        if (isGridEnabledRef.value && gridSizeRef.value > 0) {
          container.classList.add('grid-background');
          container.style.setProperty('--grid-size', cssGridSize.value);
        } else {
          container.classList.remove('grid-background');
          container.style.removeProperty('--grid-size');
        }
      }
    }
  };

  const enableGridSnapping = (): void => {
    isGridEnabledRef.value = true;
    updateGridBackground();
  };

  const disableGridSnapping = (): void => {
    isGridEnabledRef.value = false;
    updateGridBackground();
  };

  const setGridSize = (size: number): void => {
    gridSizeRef.value = size;
    if (isGridEnabledRef.value) {
      updateGridBackground();
    }
  };

  watch([isGridEnabledRef, gridSizeRef], updateGridBackground);

  return {
    isGridEnabledRef,
    gridSizeRef,
    cssGridSize,
    enableGridSnapping,
    disableGridSnapping,
    setGridSize,
  };
}
