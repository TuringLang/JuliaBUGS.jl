import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import { mathjaxPlugin } from './mathjax-plugin'
import { juliaReplTransformer } from './julia-repl-transformer'
import footnote from "markdown-it-footnote";
import path from 'path'

const mathjax = mathjaxPlugin()

function getBaseRepository(base: string): string {
  if (!base || base === '/') return '/';
  const parts = base.split('/').filter(Boolean);
  return parts.length > 0 ? `/${parts[0]}/` : '/';
}

const baseTemp = {
  base: '/JuliaBUGS.jl/',
}

const navTemp = {
  nav: [
{ text: 'Home', link: '/index' },
{ text: 'Examples', collapsed: false, items: [
{ text: 'Pumps', link: '/generated/pumps' },
{ text: 'Rats', link: '/generated/rats' }]
 },
{ text: 'API Reference', link: '/api' }
]
,
}

const nav = [
  ...navTemp.nav,
  { component: 'VersionPicker' }
]

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: '/JuliaBUGS.jl/',
  title: 'BUGSExamples.jl',
  description: 'Documentation for JuliaBUGS.jl',
  lastUpdated: true,
  cleanUrls: true,
  outDir: '../1',
  head: [
    
    ['script', { src: `${getBaseRepository(baseTemp.base)}versions.js` }],
    ['script', { src: `${baseTemp.base}siteinfo.js` }],
    // DoodleBUGS widget
    ['link', { rel: 'stylesheet', href: 'https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/pr-previews/451/lib/doodlebugs.css' }],
    ['script', { type: 'module', src: 'https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/pr-previews/451/lib/doodlebugs.js' }],
    ['script', { src: `${baseTemp.base}sync_theme.js` }],
  ],

  markdown: {
    codeTransformers: [juliaReplTransformer()],
    config(md) {
      md.use(tabsMarkdownPlugin);
      md.use(footnote);
      mathjax.markdownConfig(md);
    },
    theme: {
      light: "github-light",
      dark: "github-dark"
    },
  },
  vite: {
    plugins: [mathjax.vitePlugin],
    define: {
      __DEPLOY_ABSPATH__: JSON.stringify('/JuliaBUGS.jl'),
    },
    resolve: {
      alias: { '@': path.resolve(__dirname, '../components') }
    },
    optimizeDeps: {
      exclude: [
        '@nolebase/vitepress-plugin-enhanced-readabilities/client',
        'vitepress',
        '@nolebase/ui',
      ],
    },
    ssr: {
      noExternal: [
        '@nolebase/vitepress-plugin-enhanced-readabilities',
        '@nolebase/ui',
      ],
    },
  },
  themeConfig: {
    outline: 'deep',
    
    search: {
      provider: 'local',
      options: { detailedView: true }
    },
    nav,
    sidebar: [
{ text: 'Home', link: '/index' },
{ text: 'Examples', collapsed: false, items: [
{ text: 'Pumps', link: '/generated/pumps' },
{ text: 'Rats', link: '/generated/rats' }]
 },
{ text: 'API Reference', link: '/api' }
]
,
    sidebarDrawer: false,
    editLink: { pattern: "https://github.com/TuringLang/JuliaBUGS.jl/edit/main/docs/src/:path" },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/TuringLang/JuliaBUGS.jl' }
    ],
    footer: {
      message: 'Made with <a href="https://luxdl.github.io/DocumenterVitepress.jl/dev/" target="_blank"><strong>DocumenterVitepress.jl</strong></a><br>',
      copyright: `© Copyright ${new Date().getUTCFullYear()}.`
    }
  }
})
