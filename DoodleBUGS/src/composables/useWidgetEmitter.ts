import { watch, nextTick, ref } from 'vue'
import type { Ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useProjectStore } from '../stores/projectStore'
import { useGraphStore } from '../stores/graphStore'
import { useDataStore } from '../stores/dataStore'

export interface WidgetEmitFn {
  (e: 'state-update', payload: string): void
  (e: 'code-update', payload: string): void
  (e: 'ready', payload: string): void
}

export function useWidgetEmitter(
  emit: WidgetEmitFn,
  generatedCode: Ref<string>,
  options: { debounceMs?: number } = {}
) {
  const projectStore = useProjectStore()
  const graphStore = useGraphStore()
  const dataStore = useDataStore()

  const debounceMs = options.debounceMs ?? 250
  const isReady = ref(false)

  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let lastEmittedState = ''

  const buildFullState = () => ({
    project: projectStore.exportState(),
    graphs: Array.from(graphStore.graphContents.entries()).map(([, v]) => v),
    data: Array.from(graphStore.graphContents.keys()).map((gid) => ({
      graphId: gid,
      content: dataStore.getGraphData(gid).content,
    })),
    currentGraphId: graphStore.currentGraphId,
  })

  const emitStateDebounced = () => {
    if (!isReady.value) return
    if (debounceTimer) clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => {
      const json = JSON.stringify(buildFullState())
      if (json !== lastEmittedState) {
        lastEmittedState = json
        emit('state-update', json)
      }
    }, debounceMs)
  }

  const emitStateImmediate = () => {
    if (!isReady.value) return
    if (debounceTimer) clearTimeout(debounceTimer)
    debounceTimer = null
    const json = JSON.stringify(buildFullState())
    if (json !== lastEmittedState) {
      lastEmittedState = json
      emit('state-update', json)
    }
  }

  const { dataContent: dataContentRef } = storeToRefs(dataStore)
  const { currentGraphId: currentGraphIdRef } = storeToRefs(graphStore)

  watch([dataContentRef, currentGraphIdRef], emitStateImmediate)

  watch([() => projectStore.projects, () => graphStore.graphContents], emitStateDebounced, {
    deep: true,
  })

  watch(generatedCode, (code) => {
    if (isReady.value) {
      emit('code-update', code)
    }
  })

  const emitReady = () => {
    isReady.value = true
    const state = buildFullState()
    const json = JSON.stringify(state)
    lastEmittedState = json

    nextTick(() => {
      emit('state-update', json)
      emit('code-update', generatedCode.value)
      emit('ready', json)
    })
  }

  return { emitReady, isReady }
}
