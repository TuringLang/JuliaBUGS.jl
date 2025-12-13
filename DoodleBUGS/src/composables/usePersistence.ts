export interface UIState {
  leftSidebar?: {
    open: boolean
    x: number
    y: number
  }
  rightSidebar?: {
    open: boolean
    x: number
    y: number
  }
  codePanel?: {
    open: boolean
    x: number
    y: number
    width: number
    height: number
  }
  dataPanel?: {
    open: boolean
    x: number
    y: number
    width: number
    height: number
  }
  currentGraphId?: string
  editMode?: boolean
}

export interface GraphData {
  elements: unknown[]
  dataContent?: string
}

export function usePersistence(storageKeyPrefix = 'doodlebugs') {
  const isSSR = typeof window === 'undefined'

  const loadUIState = (key: string): UIState | null => {
    if (isSSR) return null
    try {
      const saved = localStorage.getItem(key)
      return saved ? JSON.parse(saved) : null
    } catch (e) {
      console.error('Failed to load UI state:', e)
      return null
    }
  }

  const saveUIState = (key: string, state: UIState): void => {
    if (isSSR) return
    try {
      localStorage.setItem(key, JSON.stringify(state))
    } catch (e) {
      console.error('Failed to save UI state:', e)
    }
  }

  const loadGraphData = (graphId: string): GraphData | null => {
    if (isSSR) return null
    try {
      const storedGraph = localStorage.getItem(`${storageKeyPrefix}-graph-${graphId}`)
      if (!storedGraph) return null

      const parsed = JSON.parse(storedGraph)
      return {
        elements: parsed.elements || [],
        dataContent: undefined,
      }
    } catch (e) {
      console.error('Failed to load graph data:', e)
      return null
    }
  }

  const loadDataContent = (graphId: string): string => {
    if (isSSR) return '{}'
    try {
      const storedData = localStorage.getItem(`${storageKeyPrefix}-data-${graphId}`)
      if (!storedData) return '{}'

      const parsed = JSON.parse(storedData)
      return (
        parsed.content ||
        (parsed.jsonData
          ? JSON.stringify({
              data: parsed.jsonData.data || {},
              inits: parsed.jsonData.inits || {},
            })
          : '{}')
      )
    } catch (e) {
      console.error('Failed to load data content:', e)
      return '{}'
    }
  }

  const loadLastGraphId = (): string | null => {
    if (isSSR) return null
    try {
      return localStorage.getItem(`${storageKeyPrefix}-currentGraphId`)
    } catch (e) {
      console.error('Failed to load last graph ID:', e)
      return null
    }
  }

  const saveLastGraphId = (graphId: string): void => {
    if (isSSR) return
    try {
      localStorage.setItem(`${storageKeyPrefix}-currentGraphId`, graphId)
    } catch (e) {
      console.error('Failed to save last graph ID:', e)
    }
  }

  const getStoredGraphElements = (graphId: string): unknown[] => {
    const graphData = loadGraphData(graphId)
    return graphData?.elements || []
  }

  const getStoredDataContent = (graphId: string): string => {
    return loadDataContent(graphId)
  }

  return {
    loadUIState,
    saveUIState,
    loadGraphData,
    loadDataContent,
    loadLastGraphId,
    saveLastGraphId,
    getStoredGraphElements,
    getStoredDataContent,
  }
}
