import { computed } from 'vue'
import type { Ref } from 'vue'
import { generateBugsModel } from '@mcmcjs/doodleppl'
import type { GraphElement } from '../types'

/**
 * Composable that generates BUGS model code from graph elements.
 * @param elements - A ref to the graph elements.
 */
export function useBugsCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedCode = computed(() => {
    const hasNodes = elements.value.some((el) => el.type === 'node')
    if (!hasNodes) {
      return 'model {\n  # Your model will appear here...\n}'
    }
    return generateBugsModel(elements.value)
  })

  return {
    generatedCode,
  }
}

export {
  generateStandaloneScript,
  type StandaloneGeneratorSettings,
  type StandaloneScriptInput,
} from '@mcmcjs/doodleppl'
