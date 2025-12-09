import { defineStore } from 'pinia'
import { ref, watch } from 'vue'
import { nodeDefinitions, defaultEdgeStyles, type EdgeStyle } from '../config/nodeDefinitions'

export type RightSidebarTab = 'properties' | 'script' | 'export'
export type LeftSidebarTab =
  | 'project'
  | 'palette'
  | 'data'
  | 'settings'
  | 'view'
  | 'connect'
  | 'help'
  | 'devtools'
export type GridStyle = 'dots' | 'lines'

export interface NodeStyle {
  backgroundColor: string
  borderColor: string
  borderWidth: number
  borderStyle: string
  backgroundOpacity: number
  shape: string
  width: number
  height: number
  labelFontSize: number
  labelColor: string
}

export const useUiStore = defineStore('ui', () => {
  const storagePrefix = ref('doodlebugs')

  const getStorageKey = (key: string) => `${storagePrefix.value}-${key}`

  // Initial State - Hydrate from localStorage immediately for the main app
  const activeRightTab = ref<RightSidebarTab>(
    (localStorage.getItem(getStorageKey('activeRightTab')) as RightSidebarTab) || 'properties'
  )
  
  const isRightTabPinned = ref<boolean>(
    localStorage.getItem(getStorageKey('isRightTabPinned')) === 'true'
  )
  
  // Default to closed (false) only if not set or false in storage, but we check specific 'true' string
  const isRightSidebarOpen = ref<boolean>(
    localStorage.getItem(getStorageKey('isRightSidebarOpen')) === 'true'
  )
  
  const activeLeftTab = ref<LeftSidebarTab>(
    (localStorage.getItem(getStorageKey('activeLeftTab')) as LeftSidebarTab) || 'project'
  )
  
  const isLeftSidebarOpen = ref<boolean>(
    localStorage.getItem(getStorageKey('isLeftSidebarOpen')) === 'true'
  )
  
  const storedAccordion = localStorage.getItem(getStorageKey('activeLeftAccordionTabs'))
  const activeLeftAccordionTabs = ref<string[]>(
    storedAccordion ? JSON.parse(storedAccordion) : ['project']
  )
  
  const isGridEnabled = ref<boolean>(
    localStorage.getItem(getStorageKey('isGridEnabled')) !== 'false'
  )
  
  const gridSize = ref<number>(
    parseInt(localStorage.getItem(getStorageKey('gridSize')) || '30', 10)
  )
  
  const showZoomControls = ref<boolean>(
    localStorage.getItem(getStorageKey('showZoomControls')) !== 'false'
  )
  
  const showDebugPanel = ref<boolean>(
    localStorage.getItem(getStorageKey('showDebugPanel')) === 'true'
  )
  
  const showDetachModeControl = ref<boolean>(
    localStorage.getItem(getStorageKey('showDetachModeControl')) === 'true'
  )
  
  const isDetachModeActive = ref<boolean>(false)
  
  const canvasGridStyle = ref<GridStyle>(
    (localStorage.getItem(getStorageKey('canvasGridStyle')) as GridStyle) || 'dots'
  )
  
  const isDarkMode = ref<boolean>(
    localStorage.getItem(getStorageKey('darkMode')) === 'true'
  )

  // Node Styles
  const storedStyles = localStorage.getItem(getStorageKey('nodeStyles'))
  const initialNodeStyles: Record<string, NodeStyle> = {}
  
  nodeDefinitions.forEach((def) => {
    initialNodeStyles[def.nodeType] = { ...def.defaultStyle }
  })

  if (storedStyles) {
    try {
      const parsed = JSON.parse(storedStyles)
      Object.keys(initialNodeStyles).forEach((key) => {
        if (parsed[key]) {
          initialNodeStyles[key] = { ...initialNodeStyles[key], ...parsed[key] }
        }
      })
    } catch(e) { console.error(e) }
  }
  const nodeStyles = ref<Record<string, NodeStyle>>({ ...initialNodeStyles })

  // Edge Styles
  const storedEdgeStyles = localStorage.getItem(getStorageKey('edgeStyles'))
  let initialEdgeStylesVal = { ...defaultEdgeStyles }

  if (storedEdgeStyles) {
    try {
      initialEdgeStylesVal = { ...initialEdgeStylesVal, ...JSON.parse(storedEdgeStyles) }
    } catch(e) { console.error(e) }
  }
  const edgeStyles = ref<Record<'stochastic' | 'deterministic', EdgeStyle>>(initialEdgeStylesVal)

  // Function to initialize/reload store with new prefix (Used by Widget)
  const setPrefix = (prefix: string) => {
    storagePrefix.value = prefix
    
    // Re-hydrate state from new keys
    activeRightTab.value = (localStorage.getItem(getStorageKey('activeRightTab')) as RightSidebarTab) || 'properties'
    isRightTabPinned.value = localStorage.getItem(getStorageKey('isRightTabPinned')) === 'true'
    isRightSidebarOpen.value = localStorage.getItem(getStorageKey('isRightSidebarOpen')) === 'true'
    activeLeftTab.value = (localStorage.getItem(getStorageKey('activeLeftTab')) as LeftSidebarTab) || 'project'
    isLeftSidebarOpen.value = localStorage.getItem(getStorageKey('isLeftSidebarOpen')) === 'true'
    
    const storedAccordion = localStorage.getItem(getStorageKey('activeLeftAccordionTabs'))
    activeLeftAccordionTabs.value = storedAccordion ? JSON.parse(storedAccordion) : ['project']
    
    isGridEnabled.value = localStorage.getItem(getStorageKey('isGridEnabled')) !== 'false'
    gridSize.value = parseInt(localStorage.getItem(getStorageKey('gridSize')) || '30', 10)
    showZoomControls.value = localStorage.getItem(getStorageKey('showZoomControls')) !== 'false'
    showDebugPanel.value = localStorage.getItem(getStorageKey('showDebugPanel')) === 'true'
    showDetachModeControl.value = localStorage.getItem(getStorageKey('showDetachModeControl')) === 'true'
    canvasGridStyle.value = (localStorage.getItem(getStorageKey('canvasGridStyle')) as GridStyle) || 'dots'
    isDarkMode.value = localStorage.getItem(getStorageKey('darkMode')) === 'true'

    // Styles
    const storedStyles = localStorage.getItem(getStorageKey('nodeStyles'))
    if (storedStyles) {
        try {
            const parsed = JSON.parse(storedStyles)
            Object.keys(initialNodeStyles).forEach((key) => {
                if (parsed[key]) {
                    nodeStyles.value[key] = { ...initialNodeStyles[key], ...parsed[key] }
                }
            })
        } catch(e) { console.error(e) }
    } else {
        // Reset to defaults if nothing stored for this prefix
        Object.keys(initialNodeStyles).forEach(key => {
             nodeStyles.value[key] = { ...initialNodeStyles[key] }
        })
    }

    const storedEdgeStyles = localStorage.getItem(getStorageKey('edgeStyles'))
    if (storedEdgeStyles) {
        try {
            edgeStyles.value = { ...defaultEdgeStyles, ...JSON.parse(storedEdgeStyles) }
        } catch(e) { console.error(e) }
    } else {
        edgeStyles.value = { ...defaultEdgeStyles }
    }
  }

  // Watchers for Persistence
  watch(activeRightTab, (newTab) => localStorage.setItem(getStorageKey('activeRightTab'), newTab))
  watch(isRightTabPinned, (isPinned) => localStorage.setItem(getStorageKey('isRightTabPinned'), isPinned.toString()))
  watch(isRightSidebarOpen, (isOpen) => localStorage.setItem(getStorageKey('isRightSidebarOpen'), isOpen.toString()))
  watch(activeLeftTab, (newTab) => localStorage.setItem(getStorageKey('activeLeftTab'), newTab))
  watch(isLeftSidebarOpen, (isOpen) => localStorage.setItem(getStorageKey('isLeftSidebarOpen'), isOpen.toString()))
  watch(activeLeftAccordionTabs, (tabs) => localStorage.setItem(getStorageKey('activeLeftAccordionTabs'), JSON.stringify(tabs)), { deep: true })
  watch(isGridEnabled, (val) => localStorage.setItem(getStorageKey('isGridEnabled'), String(val)))
  watch(gridSize, (val) => localStorage.setItem(getStorageKey('gridSize'), String(val)))
  watch(showZoomControls, (val) => localStorage.setItem(getStorageKey('showZoomControls'), String(val)))
  watch(showDebugPanel, (val) => localStorage.setItem(getStorageKey('showDebugPanel'), String(val)))
  watch(showDetachModeControl, (val) => localStorage.setItem(getStorageKey('showDetachModeControl'), String(val)))
  watch(canvasGridStyle, (style) => localStorage.setItem(getStorageKey('canvasGridStyle'), style))
  watch(isDarkMode, (val) => localStorage.setItem(getStorageKey('darkMode'), String(val)))
  watch(nodeStyles, (styles) => localStorage.setItem(getStorageKey('nodeStyles'), JSON.stringify(styles)), { deep: true })
  watch(edgeStyles, (styles) => localStorage.setItem(getStorageKey('edgeStyles'), JSON.stringify(styles)), { deep: true })

  // Actions
  const setActiveRightTab = (tab: RightSidebarTab) => {
    activeRightTab.value = tab
    if (!isRightSidebarOpen.value) {
      isRightSidebarOpen.value = true
    }
  }

  const toggleRightTabPinned = () => {
    isRightTabPinned.value = !isRightTabPinned.value
  }

  const toggleRightSidebar = () => {
    isRightSidebarOpen.value = !isRightSidebarOpen.value
  }

  const handleLeftTabClick = (tab: LeftSidebarTab) => {
    if (activeLeftTab.value === tab && isLeftSidebarOpen.value) {
      isLeftSidebarOpen.value = false
    } else {
      isLeftSidebarOpen.value = true
      activeLeftTab.value = tab
    }
  }

  const toggleLeftSidebar = () => {
    isLeftSidebarOpen.value = !isLeftSidebarOpen.value
  }

  const toggleDarkMode = () => {
    isDarkMode.value = !isDarkMode.value
  }

  const toggleDetachMode = () => {
    isDetachModeActive.value = !isDetachModeActive.value
  }

  return {
    setPrefix,
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
    activeLeftAccordionTabs,
    canvasGridStyle,
    isDarkMode,
    toggleDarkMode,
    nodeStyles,
    edgeStyles,
    isGridEnabled,
    gridSize,
    showZoomControls,
    showDebugPanel,
    showDetachModeControl,
    isDetachModeActive,
    toggleDetachMode,
  }
})
