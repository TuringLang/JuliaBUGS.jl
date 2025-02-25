---
title: "Appendix: Additional Investigations"
---

# Cutting Room Floor

This appendix contains additional investigations and experiments that were conducted but not included in the main chapters. These might be useful for future reference or alternative approaches.

## Manually written log density computation of `Rats`, not using `VarName`

```julia
using BangBang, Bijectors
using JuliaBUGS.BUGSPrimitives: dgamma, dnorm

function rats_logdensity_with_for_loops(evaluation_env, params)
    (; alpha, xbar, sigma, alpha0, x, mu, Y, beta) = evaluation_env

    gamma_bijector = Bijectors.bijector(dgamma(0.001, 0.001))
    gamma_bijector_inv = Bijectors.inverse(gamma_bijector)

    log_density = 0.0

    beta_tau, logjac_beta_tau = Bijectors.with_logabsdet_jacobian(
        gamma_bijector_inv, params[1]
    )
    log_density += logpdf(dgamma(0.001, 0.001), beta_tau) + logjac_beta_tau

    beta_c, logjac_beta_c = Bijectors.with_logabsdet_jacobian(identity, params[2])
    log_density += logpdf(dnorm(0.0, 1.0e-6), beta_c) + logjac_beta_c

    alpha_tau, logjac_alpha_tau = Bijectors.with_logabsdet_jacobian(
        gamma_bijector_inv, params[3]
    )
    log_density += logpdf(dgamma(0.001, 0.001), alpha_tau) + logjac_alpha_tau

    alpha_c, logjac_alpha_c = Bijectors.with_logabsdet_jacobian(identity, params[4])
    log_density += logpdf(dnorm(0.0, 1.0e-6), alpha_c) + logjac_alpha_c

    alpha0 = alpha_c - xbar * beta_c

    tau_c, logjac_tau_c = Bijectors.with_logabsdet_jacobian(gamma_bijector_inv, params[5])
    log_density += logpdf(dgamma(0.001, 0.001), tau_c) + logjac_tau_c

    sigma = 1 / sqrt(tau_c)

    counter = 6
    for i in 30:-1:1
        beta = BangBang.setindex!!(beta, params[counter], i)
        alpha = BangBang.setindex!!(alpha, params[counter + 1], i)
        counter += 2
    end

    # technically, for normal distributions, we don't need the logjac, but include
    # for consistency
    for i in 1:30
        alpha_i, logjac_alpha_i = Bijectors.with_logabsdet_jacobian(identity, alpha[i])
        log_density += logpdf(dnorm(alpha_c, alpha_tau), alpha_i) + logjac_alpha_i

        beta_i, logjac_beta_i = Bijectors.with_logabsdet_jacobian(identity, beta[i])
        log_density += logpdf(dnorm(beta_c, beta_tau), beta_i) + logjac_beta_i
    end

    for i in 1:30
        for j in 1:5
            mu = BangBang.setindex!!(mu, alpha[i] + beta[i] * (x[j] - xbar), i, j)
        end
    end

    for i in 1:30
        for j in 1:5
            log_density += logpdf(dnorm(mu[i, j], tau_c), Y[i, j])
        end
    end

    return log_density
end

evaluation_env = model.evaluation_env
rats_logdensity_with_for_loops(evaluation_env, param_values)
@benchmark rats_logdensity_with_for_loops($evaluation_env, $param_values)
```

```
BenchmarkTools.Trial: 10000 samples with 128 evaluations per sample.
 Range (min … max):  734.695 ns …  1.437 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     821.289 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   825.103 ns ± 47.710 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▄   ▂▁    ▃▁▁▁▁▂▁▁▁▁▂█▂▁▂▁▂▄▃▂▁▁  ▁▁▁ ▁  ▁                   ▁
  █▇▇▇██████████████████████████████████████████▇██▇▇▆▇▇▆▅▅▅▆▆ █
  735 ns        Histogram: log(frequency) by time       975 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```


---


```julia
struct VariableComputationNoneRecursive{Sym, OpticT, LoopVarsNT, OT, IT}
    vn::JuliaBUGS.VarName{Sym,OpticT}
    loop_vars::LoopVarsNT
    values_indices::Tuple{Int,Int}
    is_observed::Bool
    node_function::FunctionWrappers.FunctionWrapper{OT,IT}
    next_idx::Union{Nothing,Int}
end

function make_computations_none_recursive(model)
    var_lengths = model.transformed ? model.transformed_var_lengths : model.untransformed_var_lengths
    N = length(model.flattened_graph_node_data.sorted_nodes)
    computations = Vector{VariableComputationNoneRecursive}(undef, N)

    current_idx = model.transformed ? model.transformed_param_length : model.untransformed_param_length

    for i in N:-1:1
        vn = model.flattened_graph_node_data.sorted_nodes[i]
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]

        next_idx = (i == N) ? nothing : i + 1

        values_range = (current_idx, current_idx)
        if is_stochastic && !is_observed
            slice_len = var_lengths[vn]
            start_idx = current_idx - slice_len + 1
            end_idx = current_idx
            current_idx = start_idx - 1
            values_range = (start_idx, end_idx)
        end

        computations[i] = VariableComputationNoneRecursive(
            vn,
            loop_vars,
            values_range,
            is_observed,
            nf_fw,
            next_idx,
        )
    end

    return computations
end

computations_none_recursive = make_computations_none_recursive(model);
```

```julia
function evaluate_chain!(
    computations::Vector{VariableComputationNoneRecursive},
    evaluation_env,
    flattened_values,
)
    logp = 0.0
    i = 1
    while i !== nothing
        c = computations[i]
        (start_idx, end_idx) = c.values_indices
        param_slice = flattened_values[start_idx:end_idx]
        _logp_local, evaluation_env = c.node_function(
            evaluation_env,
            c.loop_vars,
            c.vn,
            model.transformed,
            c.is_observed,
            param_slice,
        )
        logp += _logp_local
        i = c.next_idx
    end
    return evaluation_env, logp
end

evaluate_chain!(computations_none_recursive, model.evaluation_env, param_values)

@code_warntype evaluate_chain!(computations_none_recursive, model.evaluation_env, param_values)

@benchmark evaluate_chain!(computations_none_recursive, model.evaluation_env, param_values)
```

```julia
# some experiments
using FunctionWrappers

function foo(x::Float64)
    return x + 1.0
end

function bar(x::Float64)
    return x + 2.0
end

foo_wrapper = FunctionWrappers.FunctionWrapper{Float64, Tuple{Float64}}(foo)
bar_wrapper = FunctionWrappers.FunctionWrapper{Float64, Tuple{Float64}}(bar)

fs = [foo_wrapper, bar_wrapper]

function test(fs, x)
    for i in 1:2
        f = fs[i]
        x = f(x)
    end
    return x
end

function test_ref(x)
    x = x + 1.0
    x = x + 2.0
    return x
end

test_ref(1.0)
@benchmark test_ref(1.0) # median 1 ns

test(fs, 1.0)
@benchmark test(fs, 1.0) # median 60 ns

@code_warntype test(fs, 1.0) # there is actually no type instability here, the overhead dominated the computation
```

```julia
struct FF{S} end

function f(x::Float64, ::FF{S}) where S
    if S == :a
        return x + 1.0
    elseif S == :b
        return x + 2.0
    else
        return x + 3.0
    end
end

f1 = FunctionWrappers.FunctionWrapper{Float64, Tuple{Float64, FF}}(f)
f2 = FunctionWrappers.FunctionWrapper{Float64, Tuple{Float64, FF}}(f)

fs = [f1, f2]

f1(1.0, FF{:a}())

function test2(fs, x)
    syms = (:a, :b)
    for i in 1:2
        f = fs[i]
        x = f(x, FF{syms[i]}())
    end
    return x
end

test2(fs, 1.0)
@benchmark test2(fs, 1.0) # median 1 ns

@code_warntype test2(fs, 1.0) # some type instability, but the result type is concrete
```







```julia
# nf_fw is a FunctionWrapper
FunctionWrappers.FunctionWrapper{
    # this is output
    Tuple{
        Float64, # logp
        @NamedTuple{
            alpha::Vector{Float64}, 
            beta.c::Int64, 
            xbar::Int64, 
            sigma::Float64, 
            alpha0::Int64, 
            x::Vector{Float64}, 
            N::Int64, 
            alpha.c::Int64, 
            mu::Matrix{Float64}, 
            alpha.tau::Int64, 
            Y::Matrix{Int64}, 
            T::Int64, 
            beta::Vector{Float64}, 
            beta.tau::Int64, 
            tau.c::Int64
        } # evaluation_env
    }, 
    Tuple{
        @NamedTuple{
            alpha::Vector{Float64}, 
            beta.c::Int64, 
            xbar::Int64, 
            sigma::Float64, 
            alpha0::Int64, 
            x::Vector{Float64}, 
            N::Int64, 
            alpha.c::Int64, 
            mu::Matrix{Float64}, 
            alpha.tau::Int64, 
            Y::Matrix{Int64}, 
            T::Int64, 
            beta::Vector{Float64}, 
            beta.tau::Int64, 
            tau.c::Int64
        }, # evaluation_env
        @NamedTuple{}, # loop_vars
        AbstractPPL.VarName{Symbol("beta.tau"), typeof(identity)}, # vn
        Bool, # is_observed
        Bool, # is_stochastic
        Vector{Float64} # flattened_values
    }
}(
    Ptr{Nothing} @0x000000035566011c, 
    Ptr{Nothing} @0x000000010c211708, 
    Base.RefValue{JuliaBUGS.var"#192#193"}(JuliaBUGS.var"#192#193"()), 
    JuliaBUGS.var"#192#193"
)
```

```julia
(; model_def, data, inits) = JuliaBUGS.BUGSExamples.rats
model = JuliaBUGS.compile(model_def, data, inits)
param_values = JuliaBUGS.getparams(model)
@benchmark JuliaBUGS._new_eval_with_function_wrapper(model, param_values)
JuliaBUGS._new_eval_with_function_wrapper(model, param_values)[2]

@code_warntype JuliaBUGS._new_eval_with_function_wrapper(model, param_values)
```

the `code_warntype` revealed that the output type annotation doesn't fundementally get rid of the type instabilities.
The output of the node function call is still any, only added type assert makes the computation after the type assert type stable.
The benchmark shows that this is actually slower than the current master branch.
(This is curious to me, might worth digging into.)

But, before we try more advanced things, let's try to make sure that the node functions are type stable:

```julia
evaluation_env = deepcopy(model.evaluation_env)

i = 1 # beta.tau stochastic
i = 10 # mu[30, 5] deterministic
vn = model.flattened_graph_node_data.sorted_nodes[i]
is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
node_function_with_effect = model.flattened_graph_node_data.node_function_with_effect_vals[i]
nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
is_observed = model.flattened_graph_node_data.is_observed_vals[i]
loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]

(node_function_with_effect)(
    evaluation_env, loop_vars, vn, model.transformed, is_observed, zeros(eltype(param_values), 1)
)

@code_warntype (node_function_with_effect)(
    evaluation_env, loop_vars, vn, model.transformed, is_observed, zeros(Float64, 1)
)

@code_warntype (nf_fw)(evaluation_env, loop_vars, vn, model.transformed, is_observed, zeros(eltype(param_values), 1))
```

Both are type-stable if we tighten up the types (the types of the variables are all `Float64`, not `Int`).

At this point, it seems that the `eltype` of the vectors can not be concrete other than the trivial case, even we eliminate the issue in node functions, the type instability is still there caused by `varname` and `loop_vars`.

So it seems that we have to move away from the current `Vector` based design.
The idea I try here is to have a struct that store the next variable to execute.
So for each variable, the struct has concrete types, so the function can be type stable.
Ultimately, maybe we can even use generated function to have node-wise specilized eval function.
(Although in the first example this is not done yet.) 

```julia
abstract type AbstractVariableComputation end

struct EndOfChain <: AbstractVariableComputation end

struct VariableComputationRecursive{sym,opticT,LoopVarsNT,OT,IT,Next} <: AbstractVariableComputation
    vn::JuliaBUGS.VarName{sym, opticT}
    loop_vars::LoopVarsNT
    values_indices::Tuple{Int,Int} # indicate where to find the values in the flattened_values
    is_observed::Bool
    node_function::FunctionWrappers.FunctionWrapper{OT,IT}
    next::Next
end

function make_computations_recursive(model)
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    N = length(model.flattened_graph_node_data.sorted_nodes)
    computations = Vector{Any}(undef, N)

    # Start from the total parameter length and move backwards
    current_idx = model.transformed ? model.transformed_param_length : model.untransformed_param_length

    for i in N:-1:1
        vn = model.flattened_graph_node_data.sorted_nodes[i]
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]

        # Next link
        next_var = (i == N) ? EndOfChain() : computations[i+1]

        # Determine the parameter slice for this node
        if is_stochastic && !is_observed
            slice_len = var_lengths[vn]
            start_idx = current_idx - slice_len + 1
            end_idx = current_idx
            current_idx = start_idx - 1
            values_range = (start_idx, end_idx)
        else
            # No parameters needed for deterministic nodes or observed stochastic nodes
            values_range = (current_idx, current_idx)
        end

        computations[i] = VariableComputationRecursive(
            vn,
            loop_vars,
            values_range,
            is_observed,
            nf_fw,
            next_var,
        )
    end

    return computations
end

computations_recursive = make_computations_recursive(model); # this can take a while, because the type parameters are nested, which means it can get very long

function _eval_recursive(
    evaluation_env::NT,
    start_var::VariableComputationRecursive{sym,IT,T,transformed,is_observed,Next},
    logp_acc::Float64,
    param_values::Vector{Float64}
) where {NT,sym,IT,T,transformed,is_observed,Next}
    _logp_local, evaluation_env = start_var.node_function(
        evaluation_env,
        start_var.loop_vars,
        start_var.vn,
        # model.transformed,
        true,
        start_var.is_observed,
        param_values[start_var.values_indices[1]:start_var.values_indices[2]],
    )::Tuple{Float64,NT}
    if start_var.next isa EndOfChain
        return evaluation_env, logp_acc + _logp_local
    end
    return _eval_recursive(evaluation_env, start_var.next, logp_acc + _logp_local, param_values)::Tuple{NT,Float64}
end
```

```julia
_eval_recursive(model.evaluation_env, computations_recursive[1], 0.0, param_values)

# the type is too much, because of the recursive type
io = IOBuffer()
code_warntype(io, 
    _eval_recursive, (typeof(model.evaluation_env), typeof(computations_recursive[1]), Float64, Vector{Float64})
)
write("computations_recursive.txt", String(take!(io)))

_eval_recursive(model.evaluation_env, computations_recursive[1], 0.0, param_values)
@benchmark _eval_recursive($(model.evaluation_env), $(computations_recursive[1]), 0.0, $(param_values))
```

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation per sample.
 Range (min … max):  29.917 μs …   7.840 ms  ┊ GC (min … max): 0.00% … 98.37%
 Time  (median):     33.458 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   37.595 μs ± 114.272 μs  ┊ GC (mean ± σ):  8.71% ±  3.90%

    ▂▄▆▇█▆▄▂▁    ▁▃▃▂▃                                          
  ▁▅█████████▅▄▅██████▇▇▅▄▄▃▃▃▃▃▃▂▂▃▂▂▂▂▂▂▂▁▁▁▁▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  29.9 μs         Histogram: frequency by time         47.5 μs <

 Memory estimate: 116.73 KiB, allocs estimate: 1551.`
```

This is actually really promising -- already beating the master branch version, 

But ultimately, the recursive type doesn't seem to be very scalable.

Try to avoid recursive type by making `next`'s type abstract:

```julia
struct VariableComputationAbstract{sym,opticT,LoopVarsNT,OT,IT} <: AbstractVariableComputation
    vn::JuliaBUGS.VarName{sym, opticT}
    loop_vars::LoopVarsNT
    values_indices::Tuple{Int,Int} # indicate where to find the values in the flattened_values
    is_observed::Bool
    node_function::FunctionWrappers.FunctionWrapper{OT,IT}
    next::AbstractVariableComputation
end

function make_computations_abstract(model)
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    N = length(model.flattened_graph_node_data.sorted_nodes)
    computations = Vector{Any}(undef, N)

    # Start from the total parameter length and move backwards
    current_idx = model.transformed ? model.transformed_param_length : model.untransformed_param_length

    for i in N:-1:1
        vn = model.flattened_graph_node_data.sorted_nodes[i]
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]

        # Next link
        next_var = (i == N) ? EndOfChain() : computations[i+1]

        # Determine the parameter slice for this node
        if is_stochastic && !is_observed
            slice_len = var_lengths[vn]
            start_idx = current_idx - slice_len + 1
            end_idx = current_idx
            current_idx = start_idx - 1
            values_range = (start_idx, end_idx)
        else
            # No parameters needed for deterministic nodes or observed stochastic nodes
            values_range = (current_idx, current_idx)
        end

        computations[i] = VariableComputationAbstract(
            vn,
            loop_vars,
            values_range,
            is_observed,
            nf_fw,
            next_var,
        )
    end

    return computations
end

computations_abstract = make_computations_abstract(model);

function _eval(
    evaluation_env::NT,
    start_var::VariableComputationAbstract{sym,IT,T,transformed,is_observed},
    logp_acc::Float64,
    param_values::Vector{Float64}
) where {NT,sym,IT,T,transformed,is_observed}
    _logp_local, evaluation_env = start_var.node_function(
        evaluation_env,
        start_var.loop_vars,
        start_var.vn,
        # model.transformed,
        true,
        start_var.is_observed,
        param_values[start_var.values_indices[1]:start_var.values_indices[2]],
    )::Tuple{Float64,NT}
    if start_var.next === EndOfChain()
        return evaluation_env, logp_acc + _logp_local
    end
    return _eval(evaluation_env, start_var.next, logp_acc + _logp_local, param_values)::Tuple{NT,Float64}
end

@generated function _eval_gen(
    evaluation_env::NT,
    start_var::VariableComputationAbstract{sym,IT,T,transformed,is_observed},
    logp_acc::Float64,
    param_values::Vector{Float64}
) where {NT,sym,IT,T,transformed,is_observed}
    _logp_compute_expr = quote
        _logp_local, evaluation_env = start_var.node_function(
            evaluation_env,
            start_var.loop_vars,
            start_var.vn,
            true,
            start_var.is_observed,
            param_values[start_var.values_indices[1]:start_var.values_indices[2]],
        )
    end
    return quote
        $(_logp_compute_expr)
        if start_var.next isa EndOfChain
            return evaluation_env, logp_acc + _logp_local
        end
        return _eval_gen(evaluation_env, start_var.next, logp_acc + _logp_local, param_values)
    end
end
```

```julia
@code_warntype _eval(model.evaluation_env, computations_abstract[1], 0.0, param_values)
_eval(model.evaluation_env, computations_abstract[1], 0.0, param_values)
@benchmark _eval(model.evaluation_env, computations_abstract[1], 0.0, param_values)
```

```julia
BenchmarkTools.Trial: 10000 samples with 1 evaluation per sample.
 Range (min … max):  28.666 μs …   7.046 ms  ┊ GC (min … max):  0.00% … 99.23%
 Time  (median):     34.708 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   40.724 μs ± 116.377 μs  ┊ GC (mean ± σ):  12.16% ±  6.43%

        ▂  ▂▂▃▁▇█▆▃▂▄                                           
  ▁▂▂▆█████▇▆▅████▆▅▄▄▅▆███▇▅▄▅▅▄▅▄▄▃▃▃▃▃▂▂▂▂▂▂▁▂▂▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  28.7 μs         Histogram: frequency by time         52.2 μs <

 Memory estimate: 220.17 KiB, allocs estimate: 2652.
```

```julia
using Profile, PProf
Profile.clear()
@profile for i in 1:1000
    _eval(model.evaluation_env, computations_abstract[1], 0.0, param_values)
end
pprof()
```

```julia
_eval_gen(model.evaluation_env, computations_abstract[1], 0.0, param_values)
@benchmark _eval_gen($(model.evaluation_env), $(computations_abstract[1]), 0.0, $(param_values))
```

```julia
BenchmarkTools.Trial: 10000 samples with 1 evaluation per sample.
 Range (min … max):  25.125 μs …   8.615 ms  ┊ GC (min … max):  0.00% … 99.17%
 Time  (median):     30.167 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   36.433 μs ± 153.965 μs  ┊ GC (mean ± σ):  14.16% ±  4.73%

      ▄▇▇▆▃   ▂▆█▃        ▁                                     
  ▁▂▂▆█████▇▆▅████▆▅▄▄▅▆███▇▅▄▅▅▄▅▄▄▃▃▃▃▃▂▂▂▂▂▂▁▂▂▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  25.1 μs         Histogram: frequency by time         45.8 μs <

 Memory estimate: 168.34 KiB, allocs estimate: 2284.
```

On second thought, maybe the recursive type definition is worth another try.

```julia
eval_env_type = typeof(model.evaluation_env)
const OT = Tuple{Float64, eval_env_type}
IT = Tuple{
    eval_env_type,
    # NT loop variables,
    # vn
    Bool, # is_observed
    Bool, # is_stochastic
    Vector{Float64} # flattened_values
}

struct VariableComputationRecursiveDedup2{sym,opticT,LoopVarsNT,Next} <: AbstractVariableComputation
    vn::JuliaBUGS.VarName{sym, opticT}
    loop_vars::LoopVarsNT
    values_indices::Tuple{Int,Int} # indicate where to find the values in the flattened_values
    is_observed::Bool
    node_function::FunctionWrappers.FunctionWrapper{OT,Tuple{eval_env_type, LoopVarsNT, JuliaBUGS.VarName{sym, opticT}, Bool, Bool, Vector{Float64}}}
    next::Next
end

function make_computations_recursive_dedup(model, depth=length(model.flattened_graph_node_data.sorted_nodes))
    var_lengths = if model.transformed
        model.transformed_var_lengths
    else
        model.untransformed_var_lengths
    end

    computations = Vector{Any}(undef, depth)

    # Start from the total parameter length and move backwards
    current_idx = model.transformed ? model.transformed_param_length : model.untransformed_param_length

    for i in depth:-1:1
        vn = model.flattened_graph_node_data.sorted_nodes[i]
        is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[i]
        nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[i]
        is_observed = model.flattened_graph_node_data.is_observed_vals[i]
        loop_vars = model.flattened_graph_node_data.loop_vars_vals[i]

        # Next link
        next_var = (i == depth) ? EndOfChain() : computations[i+1]

        # Determine the parameter slice for this node
        if is_stochastic && !is_observed
            slice_len = var_lengths[vn]
            start_idx = current_idx - slice_len + 1
            end_idx = current_idx
            current_idx = start_idx - 1
            values_range = (start_idx, end_idx)
        else
            # No parameters needed for deterministic nodes or observed stochastic nodes
            values_range = (current_idx, current_idx)
        end

        computations[i] = VariableComputationRecursiveDedup2(
            vn,
            loop_vars,
            values_range,
            is_observed,
            nf_fw,
            next_var,
        )
    end

    return computations
end

computations_recursive_dedup = make_computations_recursive_dedup(model, 5);

function evaluate_recursive_dedup_non_gen(
    eval_env::EvalEnvType,
    comp::VariableComputationRecursiveDedup2{sym, opticT, LoopVarsNT, Next},
    logp_acc::Float64,
    param_values::Vector{Float64},
) where {EvalEnvType, sym, opticT, LoopVarsNT, Next}
    _logp_local, evaluation_env = comp.node_function(
        eval_env,
        comp.loop_vars,
        comp.vn,
        # model.transformed,
        true,
        comp.is_observed,
        param_values[comp.values_indices[1]:comp.values_indices[2]],
    )::Tuple{Float64,EvalEnvType}
    if comp.next === EndOfChain()
        return evaluation_env, logp_acc + _logp_local
    end
    return evaluate_recursive_dedup_non_gen(evaluation_env, comp.next, logp_acc + _logp_local, param_values)::Tuple{EvalEnvType,Float64}
end

@generated function evaluate_recursive_dedup(
    eval_env::EvalEnvType,
    comp::VariableComputationRecursiveDedup2{sym, opticT, LoopVarsNT, Next},
    logp_acc::Float64,
    param_values::Vector{Float64},
) where {EvalEnvType, sym, opticT, LoopVarsNT, Next}

    # If the next field is EndOfChain, return a one-step code block.
    if Next <: EndOfChain
        return quote
            # Slice out local parameter values
            start_idx, end_idx = comp.values_indices
            local_values = start_idx <= end_idx ?
                @inbounds(param_values[start_idx:end_idx]) : Float64[]

            local_logp, new_env = comp.node_function(
                eval_env,
                comp.loop_vars,
                comp.vn,
                true, # is_transformed
                comp.is_observed,
                local_values
            )::Tuple{Float64,EvalEnvType}
            return new_env, logp_acc + local_logp
        end
    else
        # Otherwise, we recurse: call node_function, then move on to comp.next
        return quote
            start_idx, end_idx = comp.values_indices
            local_values = start_idx <= end_idx ?
                @inbounds(param_values[start_idx:end_idx]) : Float64[]

            local_logp, new_env = comp.node_function(
                eval_env,
                comp.loop_vars,
                comp.vn,
                comp.is_observed,
                false,
                local_values
            )::Tuple{Float64,EvalEnvType}
            new_logp = logp_acc + local_logp
            return evaluate_recursive_dedup(new_env, comp.next, new_logp, param_values)
        end
    end
end

evaluate_recursive_dedup_non_gen(model.evaluation_env, computations_recursive_dedup[1], 0.0, param_values)
@benchmark evaluate_recursive_dedup_non_gen($(model.evaluation_env), $(computations_recursive_dedup[1]), 0.0, $(param_values))
@code_warntype evaluate_recursive_dedup_non_gen(model.evaluation_env, computations_recursive_dedup[1], 0.0, param_values)

evaluate_recursive_dedup(model.evaluation_env, computations_recursive_dedup[1], 0.0, param_values)
@benchmark evaluate_recursive_dedup($(model.evaluation_env), $(computations_recursive_dedup[1]), 0.0, $(param_values)) # this consistently slower than the non-gen version, when the depth is bigger than ~7, the recursive type is just not good
@code_warntype evaluate_recursive_dedup(model.evaluation_env, computations_recursive_dedup[1], 0.0, param_values)
```

```julia
Profile.clear()
using PProf
@profile for i in 1:1000
    evaluate_recursive_dedup(model.evaluation_env, computations_recursive_dedup[1], 0.0, param_values)
end
pprof()
```

Next idea is to use a `meta-generated` function, because I know the combination of the function and all the argument types.

---
Let's take a step back, are the new node functions fast? And how bad is the overhead of `FunctionWrappers` on type stable functions
are `cfunction` function pointers?

```julia
idx = 1
vn = model.flattened_graph_node_data.sorted_nodes[idx]
# is_stochastic = model.flattened_graph_node_data.is_stochastic_vals[idx]
node_function_with_effect = model.flattened_graph_node_data.node_function_with_effect_vals[idx]
nf_fw = model.flattened_graph_node_data.node_function_with_effect_function_wrapper_vals[idx]
# is_observed = model.flattened_graph_node_data.is_observed_vals[idx]
# loop_vars = model.flattened_graph_node_data.loop_vars_vals[idx]
```
