import { defineCustomElement } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import Aura from '@primevue/themes/aura'
import DoodleWidget from './DoodleWidget.vue'

import './assets/styles/global.css'
import 'primeicons/primeicons.css'

export type {
  NodeDefinition,
  NodeProperty,
  NodePropertyType,
  SelectOption,
} from './config/nodeDefinitions'

export { getAllNodeDefinitions, getNodeDefinition } from './config/nodeDefinitions'

export type { GraphNode, GraphEdge, GraphElement, NodeType } from './types'

export { examples as availableModels } from './config/examples'
export type { ExampleModelConfig } from './config/examples'

export const DoodleBugsElement = defineCustomElement(DoodleWidget, {
  shadowRoot: false,
  configureApp(app) {
    app.use(createPinia())
    app.use(PrimeVue, {
      theme: {
        preset: Aura,
        options: {
          darkModeSelector: '.db-dark-mode',
        },
      },
    })
    app.use(ToastService)
  },
})

customElements.define('doodle-bugs', DoodleBugsElement)
