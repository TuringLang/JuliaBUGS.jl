### Running Tests for JuliaBUGS

To run all tests,
```bash
julia --project=./ -e 'using TestEnv; TestEnv.activate(); include("test/runtests.jl")'
```

to run one or more test groups,
```bash
julia --project=./ -e 'ENV["TEST_GROUP"] = "_test_group_1_[, _test_group_2_]"; using TestEnv; TestEnv.activate(); include("test/runtests.jl")'
```

see `runtests.jl` for all the test groups.

### Check Julia Package Source

Julia packages are usually available as Julia source code, under `<homedir>/.julia/packages`.
