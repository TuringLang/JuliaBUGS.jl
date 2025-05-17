# Running Tests

To run the tests for this package from the command line, navigate to the root directory of the package and use the following command:

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

This command will execute all tests defined in `test/runtests.jl`.

## Running Specific Test Groups

The tests are organized into groups. You can run a specific test group by setting the `TEST_GROUP` environment variable. For example, to run the "elementary" test group:

```bash
julia --project -e 'ENV["TEST_GROUP"] = "elementary"; using Pkg; Pkg.test()'
```

Available test groups are:
- `elementary`
- `compilation`
- `log_density`
- `gibbs`
- `mcmchains`
- `experimental`
- `source_gen`
- `all` (default)
