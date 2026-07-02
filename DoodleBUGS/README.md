# DoodleBUGS: Browser-Based Graphical Interface for JuliaBUGS

A web-based graphical editor for creating Bayesian models, inspired by DoodleBUGS and designed to work with JuliaBUGS. This project aims to provide a visual interface for building, understanding, and sharing probabilistic models.

Try DoodleBUGS at [`https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/`](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/).

# Project Status

This project is in active development. You can track the development progress and view active work in the [Issues with `DoodleBUGS` label](https://github.com/TuringLang/JuliaBUGS.jl/issues?q=is%3Aissue%20state%3Aopen%20label%3ADoodleBUGS).

> [!NOTE]
> This project supports touch screen devices (iPad/Tablets), however, we recommend using a Desktop environment for the best model building experience.

We welcome contributions! Feel free to explore the code, report [issues](https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md), or suggest new features. Your involvement is highly encouraged and valued.

## Architecture

The editor itself lives in the [`doodleppl`](https://www.npmjs.com/package/doodleppl) npm package (developed in the [mcmcjs](https://github.com/mcmcjs/mcmcjs) monorepo), with its graph-to-code generation in [`@mcmcjs/doodleppl`](https://www.npmjs.com/package/@mcmcjs/doodleppl).
This directory is the deployed site: a thin shell that mounts the editor full-page, plus the DoodleWidget demo article and the bundled example graphs.

## Project Setup

```sh
npm install
```

### Compile and Hot-Reload for Development

```sh
npm run dev
```

### Type-Check, Compile and Minify for Production

```sh
npm run build
```

### Preview Production Build

```sh
npm run preview
```

### Formatting and Validation

```sh
npm run format       # format with Prettier
npm run format:check # check formatting
npm run typecheck    # type checking
npm run validate     # typecheck + format check
```

For more information, questions, or to get involved, please contact [@shravanngoswamii](https://github.com/shravanngoswamii) (Ping me on [Julia Slack](https://julialang.slack.com/archives/CCYDC34A0)).

> [!TIP]
> You can generate a standalone Julia script for local run directly from the web app using the "Scripts" option in the right sidebar where you can configure parameters, copy, or download it.

## Stan Code Generation

DoodleBUGS can generate Stan code from your graphical model, enabling you to run Bayesian inference using the Stan ecosystem.

### Features

- **Stan Model Code**: Automatically translates BUGS model to Stan syntax (BUGS/Stan toggle in Code Preview panel)
- **Stan (Python) Script**: Generates a standalone Python script using CmdStanPy with embedded model, data, and initial values
- **Data & Inits JSON**: Generates `data.json` and `inits.json` files for use with CmdStan, CmdStanPy, or Stan Playground
- **Copy & Download**: All generated artifacts can be copied to clipboard or downloaded from the Script tab

### Running the Generated Stan Model

**With CmdStanPy (recommended)**:

```bash
pip install cmdstanpy
python3 -m cmdstanpy.install_cmdstan
python3 stan.py
```

**With [Stan Playground](https://stan-playground.flatironinstitute.org)** (browser-based, no install):

1. Copy the Stan model code from Code Preview (Stan tab)
2. Paste into the Stan editor (top-left) in Stan Playground
3. Copy `data.json` from the Script tab (Stan → data.json → copy button)
4. Paste into the Data editor (bottom-left) in Stan Playground
5. Click Compile, then Sample

> [!NOTE]
> Stan Playground does not support custom initial values — it only offers an `init_radius` parameter for random initialization. For models requiring specific inits, use CmdStanPy or CmdStanR.

### BUGS to Stan Translation

The generator handles key differences between BUGS and Stan:

- **Precision → Standard Deviation**: BUGS `dnorm(mu, tau)` → Stan `normal(mu, 1/sqrt(tau))`
- **Distribution mapping**: `dgamma` → `gamma`, `dbeta` → `beta`, `dunif` → `uniform`, etc.
- **Naming**: Dot-separated names (`alpha.c`) → underscores (`alpha_c`)
- **Deterministic nodes** → `transformed parameters` block
- **Logical structure**: Data, parameters, transformed parameters, and model blocks are automatically organized

## DoodleWidget: Embeddable Component

DoodleBUGS can be embedded as a standalone web component in any HTML page or web app. This allows you to integrate the DoodleBUGS into documentation, tutorials, or custom applications.

**Try DoodleWidget**: [`https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/DoodleWidget/`](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/DoodleWidget/)

### Usage

From a script tag, one self-contained file:

```html
<script src="https://unpkg.com/doodleppl/dist/doodleppl.global.js" defer></script>

<doodle-ppl width="100%" height="600px" model="rats"></doodle-ppl>
```

Or as an npm package with a typed mount class (lazy-loads the editor chunk):

```sh
npm install doodleppl
```

```js
import { DoodlePPL } from 'doodleppl'

const editor = new DoodlePPL({
  element: '#editor',
  example: 'rats',
  onBugsCode: (code) => console.log(code),
  onStanCode: (code) => console.log(code),
})
```

### Props

All props are optional:

| Prop            | Type   | Default   | Description                                                                 |
| --------------- | ------ | --------- | --------------------------------------------------------------------------- |
| `width`         | string | `"100%"`  | Widget width                                                                |
| `height`        | string | `"600px"` | Widget height                                                               |
| `model`         | string | -         | Built-in model (`"rats"`, `"pumps"`, `"seeds"`) or URL to JSON file         |
| `local-model`   | string | -         | Path to local JSON file                                                     |
| `initial-state` | string | -         | JSON string to restore saved work (get from `state-update` event)           |
| `storage-key`   | string | auto      | Custom key for localStorage (only needed for multiple widgets on same page) |

### Events

| Event              | Payload     | Description                                              |
| ------------------ | ----------- | -------------------------------------------------------- |
| `state-update`     | JSON string | Fires on any change. Contains complete state             |
| `bugs-code-update` | string      | Fires when the generated BUGS code changes               |
| `stan-code-update` | string      | Fires when the generated Stan code changes               |
| `ready`            | JSON string | Fires once after mount with the initial state            |
| `models-available` | JSON string | Fires once with the list of built-in example model names |

Both `bugs-code-update` and `stan-code-update` fire whenever the model changes, regardless of which language the user has visible in the code preview panel. Host applications that need one specific language should subscribe to the matching event.

### Saving to Backend

```javascript
const widget = document.querySelector('doodle-ppl');

// Listen for changes
widget.addEventListener('state-update', (e) => {
  const state = e.detail;
  // Send 'state' to your server
});

// Load saved work
const savedState = /* get from your server */;
widget.setAttribute('initial-state', savedState);
```

## Acknowledgements & GSoC 2025

This project was initiated as part of the Google Summer of Code 2025 program.

- GSoC Project: [https://summerofcode.withgoogle.com/archive/2025/projects/4ecMbDwU](https://summerofcode.withgoogle.com/archive/2025/projects/4ecMbDwU)
- GSoC Report: [https://turinglang.org/GSoC-2025-Report-DoodleBUGS](https://turinglang.org/GSoC-2025-Report-DoodleBUGS)

**Contributor**: Shravan Goswami (Github: [@shravanngoswamii](https://github.com/shravanngoswamii))

**Mentors**: Xianda Sun (Github: [@sunxd3](https://github.com/sunxd3)) & Hong Ge (Github: [@yebai](https://github.com/yebai))

Special thanks to the [TuringLang](https://github.com/TuringLang) and [JuliaBUGS](https://github.com/TuringLang/JuliaBUGS.jl) community and contributors.
