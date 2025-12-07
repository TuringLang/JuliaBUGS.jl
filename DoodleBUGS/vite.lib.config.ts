import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  base: './',
  plugins: [
    vue({
      template: {
        compilerOptions: {
          isCustomElement: (tag) => tag === 'doodle-bugs',
        },
      },
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    outDir: 'dist-lib',
    lib: {
      entry: './src/main.ce.ts',
      name: 'DoodleBugs',
      fileName: 'doodlebugs',
    },
    rollupOptions: {
      output: {
        globals: {
          vue: 'Vue',
        },
        assetFileNames: (assetInfo) => {
          if (assetInfo.name === 'style.css') return 'doodlebugs.css'
          return assetInfo.name || ''
        },
      },
    },
    emptyOutDir: true,
    copyPublicDir: false,
  },
  define: {
    'process.env': {},
  },
})
