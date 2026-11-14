# BUGSExamples

The classic BUGS examples as plain files, one folder per example.
They are the source behind `JuliaBUGS.BUGSExamples`, and they can be read by anything else that understands BUGS and JSON.
The write-ups are on the [MultiBUGS examples pages](https://www.multibugs.org/examples/latest/).

```
volume_1/rats/
  example.toml              name, and optionally `blocked` or `lazy`
  model.bugs                the program, in BUGS syntax
  data.json                 the data, absent when the example has none
  inits.json                one set of initial values, absent when the example has none
  inits_alternative.json    the second set, likewise
  reference.json            the posterior summaries published with the example, likewise
```

## Conventions

- Nested JSON arrays are rows, so `[[1, 2], [3, 4]]` is the matrix with first row `1 2`.
- `null` is a missing value.
- A number without a decimal point is an integer, so `22` and `22.0` load as different types.
- `reference.json` maps a parameter name to an object of summaries, such as `{"mean": 106.6, "std": 3.66}`.
- `blocked = "..."` in `example.toml` says why JuliaBUGS cannot compile the example yet. `lazy = true` keeps an example out of the eagerly loaded volumes because its data is large. Both kinds can still be read with `JuliaBUGS.BUGSExamples.load`.

## Running an example without Julia code

Each folder is a complete input for the mcmcjs command line, from 0.35.0: `mcmc run volume_1/rats` fits the example with its data and published initial values, and stores the parameters plus the quantities the example published summaries for.

## Adding an example

Create the folder under its volume and fill in the files above. Nothing registers it: JuliaBUGS reads the directory when it loads, and `JuliaBUGS.BUGSExamples.list()` shows what it found.

## How JuliaBUGS finds the files

This directory is part of the JuliaBUGS package and ships with every installed copy, so JuliaBUGS reads it directly and an edit here is visible on the next load.
