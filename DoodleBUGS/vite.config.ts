import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'

function copyWidgetDemo() {
  return {
    name: 'copy-widget-demo',
    closeBundle() {
      const widgetDir = resolve(__dirname, 'dist/DoodleWidget')
      if (!existsSync(widgetDir)) mkdirSync(widgetDir, { recursive: true })
      copyFileSync(
        resolve(__dirname, 'docs/DoodleWidget/index.html'),
        resolve(widgetDir, 'index.html')
      )
    },
  }
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const baseUrl = env.VITE_APP_BASE_URL || '/'

  return {
    base: baseUrl,
    plugins: [copyWidgetDemo()],
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
