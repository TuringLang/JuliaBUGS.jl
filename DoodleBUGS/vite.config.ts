import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import { resolve } from 'node:path'
import { copyFileSync, mkdirSync, existsSync, readFileSync, writeFileSync } from 'node:fs'

function copyWidgetDemo() {
  return {
    name: 'copy-widget-demo',
    closeBundle() {
      const distDir = resolve(__dirname, 'dist')
      const widgetDir = resolve(distDir, 'DoodleWidget')
      const libDir = resolve(distDir, 'lib')

      if (!existsSync(widgetDir)) mkdirSync(widgetDir, { recursive: true })
      if (!existsSync(libDir)) mkdirSync(libDir, { recursive: true })

      const libFiles = ['doodlebugs.js', 'doodlebugs.css', 'doodlebugs.umd.cjs']
      libFiles.forEach((file) => {
        const src = resolve(__dirname, 'dist-lib', file)
        if (existsSync(src)) copyFileSync(src, resolve(libDir, file))
      })

      const demoSrc = resolve(__dirname, 'experiments/DoodleWidget/DoodleWidget.html')
      let demoContent = readFileSync(demoSrc, 'utf-8')
      demoContent = demoContent
        .replace('../../dist-lib/doodlebugs.css', '../lib/doodlebugs.css')
        .replace('../../dist-lib/doodlebugs.js', '../lib/doodlebugs.js')
      writeFileSync(resolve(widgetDir, 'index.html'), demoContent)
    },
  }
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const baseUrl = env.VITE_APP_BASE_URL || '/'

  return {
    base: baseUrl,
    plugins: [vue(), vueDevTools(), copyWidgetDemo()],
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },
    build: {
      outDir: 'dist',
      emptyOutDir: true,
    },
  }
})
