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
{ text: 'Getting Started', link: '/example' },
{ text: 'Modeling', collapsed: false, items: [
{ text: 'Two Macros: `@bugs` & `@model`', link: '/two_macros' },
{ text: '`@model` Macro', link: '/model_macro' },
{ text: '`of` Type System', link: '/of_design_doc' }]
 },
{ text: 'Inference', collapsed: false, items: [
{ text: 'Automatic Differentiation', link: '/inference/ad' },
{ text: 'Evaluation Modes', link: '/inference/evaluation_modes' },
{ text: 'Auto-Marginalization', link: '/inference/auto_marginalization' },
{ text: 'Parallel & Distributed Sampling', link: '/inference/parallel' }]
 },
{ text: 'Examples', collapsed: false, items: [
{ text: 'Volume 1', collapsed: false, items: [
{ text: 'Rats: a normal hierarchical model', link: '/examples/rats' },
{ text: 'Pumps: conjugate gamma-Poisson hierarchical model', link: '/examples/pumps' },
{ text: 'Dogs: loglinear model for binary data', link: '/examples/dogs' },
{ text: 'Seeds: random-effect logistic regression', link: '/examples/seeds' },
{ text: 'Surgical (simple): institutional ranking with independent rates', link: '/examples/surgical_simple' },
{ text: 'Surgical (realistic): random-effects logistic regression for hospital rates', link: '/examples/surgical_realistic' }]
 }]
 },
{ text: 'API Reference', collapsed: false, items: [
{ text: 'General', link: '/api/api' },
{ text: 'Functions', link: '/api/functions' },
{ text: 'Distributions', link: '/api/distributions' }]
 },
{ text: 'Guides', collapsed: false, items: [
{ text: 'Differences from Other BUGS', link: '/guides/differences' },
{ text: 'Pitfalls', link: '/guides/pitfalls' },
{ text: 'Implementation Tricks', link: '/guides/tricks' }]
 },
{ text: 'Plotting', link: '/graph_plotting' },
{ text: 'R Interface', link: '/R_interface' },
{ text: 'For Developers', collapsed: false, items: [
{ text: 'Parser', link: '/developers/parser' },
{ text: 'Source Code Generation', link: '/developers/source_gen' },
{ text: 'Notes on BUGS Implementations', link: '/developers/BUGS_notes' }]
 },
{ text: 'Bibliography', link: '/bibliography' }
]
,
}

const nav = [
  ...navTemp.nav,
  { component: 'VersionPicker' }
]

export default defineConfig({
  base: '/JuliaBUGS.jl/',
  title: 'JuliaBUGS.jl',
  description: 'Documentation for JuliaBUGS.jl',
  lastUpdated: true,
  cleanUrls: true,
  // Unresolved @ref links to Base/Core symbols are emitted as literal `./@ref`
  // anchors by Documenter; the legacy HTML writer tolerates them, Vitepress
  // hard-fails on them by default. Suppress the dead-link check.
  ignoreDeadLinks: true,
  outDir: '../1',
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
    logo: { src: 'https://turinglang.org/assets/logo/turing-logo.svg', width: 24, height: 24 },
    search: {
      provider: 'local',
      options: { detailedView: true }
    },
    nav,
    sidebar: [
{ text: 'Home', link: '/index' },
{ text: 'Getting Started', link: '/example' },
{ text: 'Modeling', collapsed: false, items: [
{ text: 'Two Macros: `@bugs` & `@model`', link: '/two_macros' },
{ text: '`@model` Macro', link: '/model_macro' },
{ text: '`of` Type System', link: '/of_design_doc' }]
 },
{ text: 'Inference', collapsed: false, items: [
{ text: 'Automatic Differentiation', link: '/inference/ad' },
{ text: 'Evaluation Modes', link: '/inference/evaluation_modes' },
{ text: 'Auto-Marginalization', link: '/inference/auto_marginalization' },
{ text: 'Parallel & Distributed Sampling', link: '/inference/parallel' }]
 },
{ text: 'Examples', collapsed: false, items: [
{ text: 'Volume 1', collapsed: false, items: [
{ text: 'Rats: a normal hierarchical model', link: '/examples/rats' },
{ text: 'Pumps: conjugate gamma-Poisson hierarchical model', link: '/examples/pumps' },
{ text: 'Dogs: loglinear model for binary data', link: '/examples/dogs' },
{ text: 'Seeds: random-effect logistic regression', link: '/examples/seeds' },
{ text: 'Surgical (simple): institutional ranking with independent rates', link: '/examples/surgical_simple' },
{ text: 'Surgical (realistic): random-effects logistic regression for hospital rates', link: '/examples/surgical_realistic' }]
 }]
 },
{ text: 'API Reference', collapsed: false, items: [
{ text: 'General', link: '/api/api' },
{ text: 'Functions', link: '/api/functions' },
{ text: 'Distributions', link: '/api/distributions' }]
 },
{ text: 'Guides', collapsed: false, items: [
{ text: 'Differences from Other BUGS', link: '/guides/differences' },
{ text: 'Pitfalls', link: '/guides/pitfalls' },
{ text: 'Implementation Tricks', link: '/guides/tricks' }]
 },
{ text: 'Plotting', link: '/graph_plotting' },
{ text: 'R Interface', link: '/R_interface' },
{ text: 'For Developers', collapsed: false, items: [
{ text: 'Parser', link: '/developers/parser' },
{ text: 'Source Code Generation', link: '/developers/source_gen' },
{ text: 'Notes on BUGS Implementations', link: '/developers/BUGS_notes' }]
 },
{ text: 'Bibliography', link: '/bibliography' }
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
