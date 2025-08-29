# DoodleBUGS: Browser-Based Graphical Interface for JuliaBUGS

A web-based graphical editor for creating Bayesian models, inspired by DoodleBUGS and designed to work with JuliaBUGS. This project aims to provide a visual interface for building, understanding, and sharing probabilistic models.

Try DoodleBUGS at [`https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/`](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/).

# Project Status: Pre-Alpha

This project is currently in the pre-alpha phase of development as part of the Google Summer of Code 2025 program.

> [!NOTE]
> Please avoid using this project in WebKit browsers like Safari, as it may not function correctly. We recommend using Chromium-based browsers such as Google Chrome or Microsoft Edge for the best experience. It works fine in Firefox as well. Note that it does not work in any browser on iPadOS and iOS, as all browsers on these platforms are WebKit-based.

- Contributor: [Shravan Goswami @shravanngoswamii](https://github.com/shravanngoswamii)
- Mentor: [Xianda Sun @sunxd3](https://github.com/sunxd3)

As an early-stage project, it may contain bugs or incomplete features. We appreciate your understanding and feedback as we work to improve it.

We welcome contributions! Feel free to explore the code, report [issues](https://github.com/TuringLang/JuliaBUGS.jl/issues/new?template=doodlebugs.md), or suggest new features. Your involvement is highly encouraged and valued.

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

For more information, questions, or to get involved, please contact [@shravanngoswamii](https://github.com/shravanngoswamii) (Ping me on [Julia Slack](https://julialang.slack.com/archives/CCYDC34A0)).

> [!TIP]
> You can generate a standalone Julia script directly from the app: open the navbar → `Connection` → `Generate Standalone Julia Script`.
> The script opens in the right sidebar's Execution panel under the Files tab, where you can copy or download it.

## Backend (Julia) Quick Start

The DoodleBUGS app can connect to a local Julia backend for running models.

1. Clone this repository and open a terminal at the repo root.
2. Instantiate backend dependencies (first time only):

```bash
julia --project=DoodleBUGS/runtime -e "using Pkg; Pkg.instantiate()"
```

3. Start the backend server (defaults to http://localhost:8081):

```bash
julia --project=DoodleBUGS/runtime DoodleBUGS/runtime/server.jl
```

4. In the DoodleBUGS app, open the navbar → `Connection` → set URL to `http://localhost:8081` → `Connect`.

Notes:
- Keep the backend terminal open while using the app.
- If the port is in use or blocked by a firewall, change the port in `DoodleBUGS/runtime/server.jl` and reconnect (the port is currently set to 8081 at the end of the file).

#### Troubleshooting

- To verify connectivity, open your browser at `http://localhost:8081/api/health` (replace 8081 if you changed the port). A healthy server returns `{ "status": "ok" }`.
- If the health check fails, ensure the server is running, the URL/port are correct, and no firewall or VPN is blocking the port. Check the backend terminal output for errors.
