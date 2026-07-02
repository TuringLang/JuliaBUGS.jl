import { computed } from 'vue'
import type { Ref } from 'vue'
import { generateStanModel } from '@mcmcjs/doodleppl/stan'
import type { GraphElement } from '../types'

/**
 * Composable that generates Stan model code from graph elements.
 * @param elements - A ref to the graph elements.
 */
export function useStanCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedStanCode = computed(() => {
    const hasNodes = elements.value.some((el) => el.type === 'node')
    if (!hasNodes) {
      return '// Your Stan model will appear here...\n'
    }
    return generateStanModel(elements.value)
  })

  return {
    generatedStanCode,
  }
}

export {
  extractCensoredFields,
  generateStanDataJson,
  generateStanInitsJson,
  generateStanStandaloneScript,
  type StanScriptInput,
} from '@mcmcjs/doodleppl/stan'
