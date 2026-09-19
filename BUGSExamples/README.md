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

## Adding an example

Create the folder under its volume and fill in the files above. Nothing registers it: JuliaBUGS reads the directory when it loads, and `JuliaBUGS.BUGSExamples.list()` shows what it found.

## How JuliaBUGS finds the files

In a checkout of this repository JuliaBUGS reads this directory directly, so an edit here is visible on the next load.
An installed JuliaBUGS has no checkout and reads a snapshot of this directory instead, declared as an artifact in `JuliaBUGS/Artifacts.toml` and attached to a GitHub release named after the content hash.
The `BUGSExamples snapshot` workflow publishes the current directory that way: it runs on every merge to main that changes an example, creates the release, and opens a pull request that points `Artifacts.toml` at it. It can also be run from the Actions tab.
`snapshot.jl` is the script behind it and can be run locally to produce the same tarball and hashes.
