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
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
}

// DocumenterVitepress's default replaces both `sidebar:` and `nav:` with
// the full `pages=` tree, which clutters the top navbar with every page.
// Hardcode a curated nav here — DV's string-replacer only fires if the
// literal `'REPLACE_ME_DOCUMENTER_VITEPRESS'` token is present, so this
// stays as-is. The sidebar still gets auto-populated from `pages=` below.
const nav = [
  { text: 'Home', link: '/' },
  { text: 'Get Started', link: '/example' },
  {
    text: 'Modeling',
    items: [
      { text: 'Two Macros: @bugs & @model', link: '/two_macros' },
      { text: '@model Macro', link: '/model_macro' },
      { text: 'of Type System', link: '/of_design_doc' },
    ],
  },
  { text: 'Examples', link: '/examples/rats' },
  {
    text: 'API',
    items: [
      { text: 'General', link: '/api/api' },
      { text: 'Functions', link: '/api/functions' },
      { text: 'Distributions', link: '/api/distributions' },
      { text: 'BUGSExamples', link: '/api/bugsexamples' },
    ],
  },
  { component: 'VersionPicker' },
]

export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  lastUpdated: true,
  cleanUrls: true,
  // Unresolved @ref links to Base/Core symbols are emitted as literal `./@ref`
  // anchors by Documenter; the legacy HTML writer tolerates them, Vitepress
  // hard-fails on them by default. Suppress the dead-link check.
  ignoreDeadLinks: true,
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  head: [
    ['link', { rel: 'icon', href: 'https://turinglang.org/assets/favicon.ico' }],
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
    build: {
      chunkSizeWarningLimit: 1500,
    },
    plugins: [mathjax.vitePlugin],
    define: {
      __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'),
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
    logo: { src: 'https://turinglang.org/assets/logo/turing-logo.svg', width: 24, height: 24 },
    search: {
      provider: 'local',
      options: { detailedView: true }
    },
    nav,
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    sidebarDrawer: 'REPLACE_ME_DOCUMENTER_VITEPRESS_SIDEBAR_DRAWER',
    editLink: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    socialLinks: [
      { icon: 'github', link: 'REPLACE_ME_DOCUMENTER_VITEPRESS' }
    ],
    footer: {
      message: 'Made with <a href="https://luxdl.github.io/DocumenterVitepress.jl/dev/" target="_blank"><strong>DocumenterVitepress.jl</strong></a><br>',
      copyright: `© Copyright ${new Date().getUTCFullYear()}.`
    }
  }
})
