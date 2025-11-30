# DoodleBUGS: Browser-Based Graphical Interface for JuliaBUGS

A web-based graphical editor for creating Bayesian models, inspired by DoodleBUGS and designed to work with JuliaBUGS. This project aims to provide a visual interface for building, understanding, and sharing probabilistic models.

Try DoodleBUGS at [`https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/`](https://turinglang.org/JuliaBUGS.jl/DoodleBUGS/).

# Project Status

This project is in active development. You can track the development progress and view active work in the [Issues with `DoodleBUGS` label](https://github.com/TuringLang/JuliaBUGS.jl/issues?q=is%3Aissue%20state%3Aopen%20label%3ADoodleBUGS).

> [!NOTE]
> This project supports touch screen devices (iPad/Tablets), however, we recommend using a Desktop environment for the best model building experience.

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

### Linting and Formatting

````sh
# Run ESLint check
npm run lint
``

```sh
# Run ESLint with auto-fix
npm run lint:fix
````

```sh
# Format all files with Prettier
npm run format
```

```sh
# Check formatting (without modifying)
npm run format:check
```

```sh
# Run type checking
npm run type-check
```

For more information, questions, or to get involved, please contact [@shravanngoswamii](https://github.com/shravanngoswamii) (Ping me on [Julia Slack](https://julialang.slack.com/archives/CCYDC34A0)).

> [!TIP]
> You can generate a standalone Julia script for local run directly from the web app using the "Scripts" option in the right sidebar where you can configure parameters, copy, or download it.

## Acknowledgements & GSoC 2025

This project was initiated as part of the Google Summer of Code 2025 program.

- GSoC Project: [https://summerofcode.withgoogle.com/archive/2025/projects/4ecMbDwU](https://summerofcode.withgoogle.com/archive/2025/projects/4ecMbDwU)
- GSoC Report: [https://turinglang.org/GSoC-2025-Report-DoodleBUGS](https://turinglang.org/GSoC-2025-Report-DoodleBUGS)

**Contributor**: Shravan Goswami (Github: [@shravanngoswamii](https://github.com/shravanngoswamii))

**Mentors**: Xianda Sun (Github: [@sunxd3](https://github.com/sunxd3)) & Hong Ge (Github: [@yebai](https://github.com/yebai))

Special thanks to the [TuringLang](https://github.com/TuringLang) and [JuliaBUGS](https://github.com/TuringLang/JuliaBUGS.jl) community and contributors.
