import { defineCustomElement, h, createApp, getCurrentInstance } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import Aura from '@primevue/themes/aura'
import DoodleWidget from './DoodleWidget.vue'

// Import global CSS so it is included in the build bundle.
import './assets/styles/global.css'
import 'primeicons/primeicons.css'

export const DoodleBugsElement = defineCustomElement({
  ...DoodleWidget,
  props: DoodleWidget.props,
  setup(props: any) {
    const app = createApp(DoodleWidget) 
    
    app.use(createPinia())
    app.use(PrimeVue, { 
      theme: { 
        preset: Aura,
        options: {
          darkModeSelector: '.dark-mode',
        }
      } 
    })
    app.use(ToastService)
    
    const inst = getCurrentInstance()
    if (inst) {
      Object.assign(inst.appContext, app._context)
      Object.assign((inst as any).provides, app._context.provides)
    }
    
    return () => h(DoodleWidget, props)
  },
  styles: DoodleWidget.styles
} as any)

customElements.define('doodle-bugs', DoodleBugsElement)
