import { ref, watch } from 'vue'
import type { Ref } from 'vue'
import { validateGraph as validateElements } from '@mcmcjs/doodleppl'
import type { GraphElement, ValidationError, ModelData } from '../types'

// Helper to compare error maps
const areErrorMapsEqual = (
  map1: Map<string, ValidationError[]>,
  map2: Map<string, ValidationError[]>
) => {
  if (map1.size !== map2.size) return false
  for (const [key, val1] of map1) {
    const val2 = map2.get(key)
    if (!val2) return false
    if (val1.length !== val2.length) return false
    for (let i = 0; i < val1.length; i++) {
      if (val1[i].field !== val2[i].field || val1[i].message !== val2[i].message) return false
    }
  }
  return true
}

/**
 * Composable for validating a BUGS graph model.
 * It produces a reactive map of errors without mutating the source elements.
 * @param elements - A ref containing the graph elements.
 * @param modelData - A ref containing the parsed model data and inits.
 */
export function useGraphValidator(elements: Ref<GraphElement[]>, modelData: Ref<ModelData>) {
  const validationErrors = ref<Map<string, ValidationError[]>>(new Map())

  const validateGraph = () => {
    const issues = validateElements(elements.value, modelData.value.data)
    const newErrors = new Map<string, ValidationError[]>()
    for (const issue of issues) {
      const list = newErrors.get(issue.nodeId)
      if (list) list.push({ field: issue.field, message: issue.message })
      else newErrors.set(issue.nodeId, [{ field: issue.field, message: issue.message }])
    }

    // Only update if content actually changed to prevent infinite loops
    if (!areErrorMapsEqual(validationErrors.value, newErrors)) {
      validationErrors.value = newErrors
    }
  }

  watch([elements, modelData], validateGraph, { deep: true, immediate: true })

  return {
    validateGraph,
    validationErrors,
  }
}
