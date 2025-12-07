import {
  defineCustomElement,
  h,
  createApp,
  getCurrentInstance,
  type ComponentInternalInstance,
} from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import Aura from '@primevue/themes/aura'
import DoodleWidget from './DoodleWidget.vue'

import './assets/styles/global.css'
import 'primeicons/primeicons.css'

interface WidgetProps {
  initialState?: string
}

export const DoodleBugsElement = defineCustomElement({
  props: { initialState: String },
  setup(props: WidgetProps) {
    const app = createApp(DoodleWidget)

    app.use(createPinia())
    app.use(PrimeVue, {
      theme: {
        preset: Aura,
        options: {
          darkModeSelector: '.dark-mode',
        },
      },
    })
    app.use(ToastService)

    const inst = getCurrentInstance()
    if (inst) {
      Object.assign(inst.appContext, app._context)
      Object.assign(
        (inst as ComponentInternalInstance & { provides: Record<string, unknown> }).provides,
        app._context.provides
      )
    }

    return () => h(DoodleWidget, props)
  },
  styles: DoodleWidget.styles,
})

customElements.define('doodle-bugs', DoodleBugsElement)
