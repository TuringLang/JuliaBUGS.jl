## Design the node function interface

The next question would be how should we design the node function interface so that they have unified types for input and outputs.

Notice the three types of computations happen at nodes have type signatures:

```julia
# deterministic
(evaluation_env, loop_vars, vn) -> evaluation_env

# data
(evaluation_env, loop_vars, vn) -> logp

# model parameter
(evaluation_env, loop_vars, vn, star_index, eng_index, flattened_values) -> evaluation_env, logp
```

A desirable node function interface would have a unified signature for all the node functions.
The problematic arguments then are `vn` and `loop_vars`, because they would be different for each node, in general.
For instance, the `typeof(vn)` for `mu[30, 5]` is `VarName{:mu, IndexLens(30, 5)}`, and the `loop_vars` is `(i = 30, j = 5)`.
While the `typeof(vn)` for `beta.tau` is `VarName{Symbol("beta.tau"), typeof(identity)}`, and the `loop_vars` is `NamedTuple()`.

Luckily, I think there is a relatively easy way out.
All variables born from the same statements would share the same node function, `vn` type and `loop_vars` type.
So we could just push these all into the node function.

The plan is, then:

For a data node,

```julia
# before:
# model.g[@varname(Y[30, 5])].node_function_expr
:(function (__evaluation_env__::NamedTuple{__vars__}, __loop_vars__::NamedTuple{__loop_vars_names__}) where {__vars__, __loop_vars_names__}
    (; mu, var"tau.c") = __evaluation_env__
    (; j, i) = __loop_vars__
    return dnorm(mu[i, j], var"tau.c")
end)

# after:
function Y_30_5(evaluation_env, loop_vars::NTuple{2, Int}, vn_indices::NTuple{2, Int}, flattened_values::AbstractVector{Float64}, start_idx::Int, end_idx::Int)
    (; mu, var"tau.c") = evaluation_env
    i = loop_vars[1]
    j = loop_vars[2]
    dist = JuliaBUGS.dnorm(mu[i, j], var"tau.c")
    vn = VarName{:Y}(AbstractPPL.IndexLens(vn_indices))
    value = AbstractPPL.get(evaluation_env, vn)
    return evaluation_env, logpdf(dist, value)
end
```

```julia
loop_vars = (30, 5)
vn_indices = (30, 5)
flattened_values = rand_params

Y_30_5(evaluation_env, loop_vars, vn_indices, flattened_values, 0, 0)
@benchmark Y_30_5($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 0, 0)
```

For a model parameter node,

```julia
# before:
# model.g[@varname(var"beta.tau")].node_function_expr
:(function (__evaluation_env__::NamedTuple{__vars__}, __loop_vars__::NamedTuple{__loop_vars_names__}) where {__vars__, __loop_vars_names__}
    (;) = __evaluation_env__
    (;) = __loop_vars__
    return dgamma(0.001, 0.001)
end)

# after:
function beta_tau(evaluation_env, loop_vars::NTuple{2, Int}, vn_indices::NTuple{2, Int}, flattened_values::Vector{Float64}, start_idx::Int, end_idx::Int)
    (;) = evaluation_env
    dist = JuliaBUGS.dgamma(0.001, 0.001)
    b = Bijectors.bijector(dist)
    b_inv = Bijectors.inverse(b)
    reconstructed_value = JuliaBUGS.reconstruct(b_inv, dist, view(flattened_values, start_idx:end_idx))
    value, logjac = Bijectors.with_logabsdet_jacobian(b_inv, reconstructed_value)
    logprior = logpdf(dist, value) + logjac
    vn = VarName{Symbol("beta.tau")}(identity)
    evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
    return evaluation_env, logprior
end
```

For a deterministic node,

```julia
# before:
# model.g[@varname(mu[30, 5])].node_function_expr
:(function (__evaluation_env__::NamedTuple{__vars__}, __loop_vars__::NamedTuple{__loop_vars_names__}) where {__vars__, __loop_vars_names__}
    (; alpha, beta, xbar, x) = __evaluation_env__
    (; j, i) = __loop_vars__
    return alpha[i] + beta[i] * (x[j] - xbar)
end)

# after:
function mu_30_5(evaluation_env, loop_vars::NTuple{2, Int}, vn_indices::NTuple{2, Int}, flattened_values::AbstractVector{Float64}, start_idx::Int, end_idx::Int)
    (; alpha, beta, xbar, x) = evaluation_env
    i = loop_vars[1]
    j = loop_vars[2]
    value = alpha[i] + beta[i] * (x[j] - xbar)
    vn = VarName{:mu}(AbstractPPL.IndexLens(vn_indices[1:2]))
    evaluation_env = BangBang.setindex!!(evaluation_env, value, vn)
    return evaluation_env, 0.0
end
```

i.e., we can make all node functions have the same type signature,

```julia
ArgumentType = Tuple{
    typeof(evaluation_env),
    NTuple{2, Int},
    NTuple{2, Int},
    AbstractVector{Float64},
    Int,
    Int,
}

ReturnType = Tuple{
    typeof(evaluation_env),
    Float64,
}
```

There are two "magic numbers" `2` and `2` in the `ArgumentType`, which are the maximum length of `vn_indices` and `loop_vars` respectively.
These two are not necessarily the same (e.g., in a fully unrolled program, there is no `loop_vars`).
We need to find these, because we want to make the type fully concrete, so we need to know the `N` of `NTuple{N, Int}`.

Another thing to note is that, we also need to sort out the index symbols for `loop_vars`.
This is trivial, but allow us to not having to use NamedTuple for `loop_vars`.

## Implement the node function interface

### Find `N`

```julia
function find_max_lengths(model)
    # Find max length of indices across all variables
    max_indices_length = maximum(
        map(labels(model.g)) do var
            var.optic isa AbstractPPL.IndexLens ? length(var.optic.indices) : 0
        end
    )

    # Find max length of loop variables across all nodes
    max_loop_vars_length = maximum(
        length(values(model.g[vn].loop_vars)) for vn in labels(model.g)
    )
    
    return max_indices_length, max_loop_vars_length
end

max_indices_length, max_loop_vars_length = find_max_lengths(model)
```

### Modifying the node function

```julia
function _gen_loop_var_unpack_expr(expr)
    loop_vars_syms = expr.args[1].args[1].args
    loop_vars_syms_sorted = sort(loop_vars_syms)

    unpacking_exprs = Expr[]
    for i in 1:length(loop_vars_syms_sorted)
        push!(unpacking_exprs, :($(loop_vars_syms_sorted[i]) = __loop_vars__[$(i)]))
    end
    return unpacking_exprs
end
```

```julia
_gen_loop_var_unpack_expr(:((;i) = loop_vars))
```

```julia
function _capture_return_stmt(expr, is_stochastic)
    if is_stochastic
        return Expr(:(=), :__dist__, expr)
    else
        return Expr(:(=), :__value__, expr)
    end
end
```

```julia
_capture_return_stmt(:(dnorm(mu[i, j], var"tau.c")), true)
```

```julia
function _gen_varname_creation(vn)
    optic = AbstractPPL.getoptic(vn)
    
    optic_sym = if optic === identity
        :identity
    elseif optic isa AbstractPPL.IndexLens
        :(AbstractPPL.IndexLens(__vn_indices__[1:$(length(optic.indices))]))
    else
        throw(ArgumentError("Unsupported optic type: $(typeof(optic))"))
    end

    return Expr(:(=), :__vn__, Expr(
        :call, 
        Expr(:curly, :VarName, QuoteNode(AbstractPPL.getsym(vn))),
        optic_sym,
    ))
end

println(_gen_varname_creation(@varname(Y[30, 5])))
println(_gen_varname_creation(@varname(var"beta.tau")))
```


```julia
function _deterministic_stmt_type_specific_computation(vn)
    ret_exprs = Expr[]
    push!(ret_exprs, _gen_varname_creation(vn))
    push!(ret_exprs, :(__evaluation_env__ = BangBang.setindex!!(__evaluation_env__, __value__, __vn__)))
    push!(ret_exprs, :(return __evaluation_env__, 0.0))
    return ret_exprs
end

function _data_stmt_type_specific_computation(vn)
    ret_exprs = Expr[]
    push!(ret_exprs, _gen_varname_creation(vn))
    push!(ret_exprs, :(__value__ = AbstractPPL.get(__evaluation_env__, __vn__)))
    push!(ret_exprs, :(return __evaluation_env__, Distributions.logpdf(__dist__, __value__)))
    return ret_exprs
end

function _model_param_stmt_type_specific_computation(vn)
    ret_exprs = Expr[]
    push!(ret_exprs, _gen_varname_creation(vn))
    push!(ret_exprs, :(__b__ = Bijectors.bijector(__dist__)))
    push!(ret_exprs, :(__b_inv__ = Bijectors.inverse(__b__)))
    push!(ret_exprs, :(__reconstructed_value__ = JuliaBUGS.reconstruct(__b_inv__, __dist__, view(__flattened_values__, __start_idx__:__end_idx__))))
    push!(ret_exprs, :((__value__, __logjac__) = Bijectors.with_logabsdet_jacobian(__b_inv__, __reconstructed_value__)))
    push!(ret_exprs, :(__logprior__ = Distributions.logpdf(__dist__, __value__) + __logjac__))
    push!(ret_exprs, :(__evaluation_env__ = BangBang.setindex!!(__evaluation_env__, __value__, __vn__)))
    push!(ret_exprs, :(return __evaluation_env__, __logprior__))
    return ret_exprs
end

function _stmt_type_specific_computation(is_stochastic, is_observed, vn)
    if is_stochastic
        if is_observed
            return _data_stmt_type_specific_computation(vn)
        else
            return _model_param_stmt_type_specific_computation(vn)
        end
    else
        return _deterministic_stmt_type_specific_computation(vn)
    end
end
```

```julia
using MacroTools

function create_new_node_function(node_function_expr, max_indices_length, max_loop_vars_length, vn, loop_vars, is_stochastic, is_observed, cache, evaluation_env)
    # because node functions for variables from the same statement are the same, we just generate once
    if haskey(cache, node_function_expr)
        return cache[node_function_expr]
    end
    
    fn_body = node_function_expr.args[2]
    _value_unpack_expr = fn_body.args[1]
    _loop_var_unpack_expr = fn_body.args[2]
    _old_return_stmt = fn_body.args[end]
    _compute_expr = _old_return_stmt.args[1]
    
    # let's break it down what I need to do here
    # function arguments
    # there are six arguments, most are static, only the two NTuples need some attention

    eval_env_T = typeof(evaluation_env)
    fn_expr = MacroTools.@q function (
        __evaluation_env__::$(eval_env_T),
        __loop_vars__::NTuple{$(max_loop_vars_length), Int},
        __vn_indices__::NTuple{$(max_indices_length), Int},
        __flattened_values__::AbstractVector{Float64},
        __start_idx__::Int,
        __end_idx__::Int,
    )
        # unpack the evaluation_env
        $(_value_unpack_expr)

        # unpack loop_variables
        $(_gen_loop_var_unpack_expr(_loop_var_unpack_expr)...)
        
        # capture the original return statement
        $(_capture_return_stmt(_compute_expr, is_stochastic))

        # stmt type specific computation
        $(_stmt_type_specific_computation(is_stochastic, is_observed, vn)...)

    end
    
    cache[node_function_expr] = fn_expr
    return fn_expr
end
```

```julia
y_30_5_expr = create_new_node_function(model.g[@varname(Y[30, 5])].node_function_expr, max_indices_length, max_loop_vars_length, @varname(Y[30, 5]), (;i = 30, j = 5), true, true, Dict(), evaluation_env)
y_30_5_func = eval(y_30_5_expr)
loop_vars = (30, 5)
vn_indices = (30, 5)
flattened_values = rand_params
y_30_5_func(evaluation_env, loop_vars, vn_indices, flattened_values, 0, 0)
@benchmark $y_30_5_func($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 0, 0)
```

```julia
beta_tau_expr = create_new_node_function(model.g[@varname(var"beta.tau")].node_function_expr, max_indices_length, max_loop_vars_length, @varname(var"beta.tau"), (), true, false, Dict(), evaluation_env)
```

this is where the issue arise -- we need to make evaluation_env scalar to be a Ref

```julia
loop_vars = (0, 0)
vn_indices = (0, 0)
flattened_values = rand_params
beta_tau_func = eval(beta_tau_expr)
beta_tau_func(evaluation_env, loop_vars, vn_indices, flattened_values, 1, 1)
@benchmark $beta_tau_func($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 1, 1)
```

```julia
mu_30_5_expr = create_new_node_function(model.g[@varname(mu[30, 5])].node_function_expr, max_indices_length, max_loop_vars_length, @varname(mu[30, 5]), (;i = 30, j = 5), false, false, Dict(), evaluation_env)
mu_30_5_func = eval(mu_30_5_expr)
loop_vars = (30, 5)
vn_indices = (30, 5)
flattened_values = rand_params
mu_30_5_func(evaluation_env, loop_vars, vn_indices, flattened_values, 0, 0)
@benchmark $mu_30_5_func($(evaluation_env), $(loop_vars), $(vn_indices), $(flattened_values), 0, 0)
```

### Produce vectors for evaluation

First `loop_vars`,

```julia
N = length(labels(model.g))
eval_loop_var_vals = Vector{NTuple{max_loop_vars_length, Int}}(undef, N)
for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
    loop_vars = model.g[vn].loop_vars
    ks = collect(keys(loop_vars))
    sorted_ks = sort(ks)
    loop_var_val = Int[loop_vars[k] for k in sorted_ks]
    # fill in the rest with 0
    for j in length(loop_var_val) + 1:max_loop_vars_length
        push!(loop_var_val, 0)
    end
    eval_loop_var_vals[i] = Tuple(loop_var_val)
end

eval_loop_var_vals

```

Next `vn_indices`,

```julia
eval_vn_indices_vals = Vector{NTuple{max_indices_length, Int}}(undef, N)
for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
    optic = AbstractPPL.getoptic(vn)
    vn_indices = if optic isa AbstractPPL.IndexLens
        Int[optic.indices...]
    else
        Int[]
    end
    # fill in the rest with 0
    for j in length(vn_indices) + 1:max_indices_length
        push!(vn_indices, 0)
    end
    eval_vn_indices_vals[i] = Tuple(vn_indices)
end

eval_vn_indices_vals
```

Then `start_idx` and `end_idx`,

```julia
eval_start_idx_vals = Vector{Int}(undef, N)
eval_end_idx_vals = Vector{Int}(undef, N)
l = 0
var_lengths = model.transformed_var_lengths
for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
    is_stochastic = model.g[vn].is_stochastic
    is_observed = model.g[vn].is_observed
    if is_stochastic
        if is_observed
            eval_start_idx_vals[i] = 0
            eval_end_idx_vals[i] = 0
        else 
            eval_start_idx_vals[i] = l + 1
            eval_end_idx_vals[i] = l + var_lengths[vn]
            l += var_lengths[vn]
        end
    else
        eval_start_idx_vals[i] = 0
        eval_end_idx_vals[i] = 0
    end
end

eval_start_idx_vals
eval_end_idx_vals
```

last, the new node functions

```julia
fw_type = FunctionWrappers.FunctionWrapper{Tuple{typeof(evaluation_env), Float64}, Tuple{typeof(evaluation_env), NTuple{max_loop_vars_length, Int}, NTuple{max_indices_length, Int}, AbstractVector{Float64}, Int, Int}}
new_node_function_exprs = Vector{Expr}(undef, N)
new_node_functions_fws = Vector{fw_type}(undef, N)
new_node_functions = Vector{Any}(undef, N)
expr_cache = Dict()
evaled_func_cache = Dict()
evaled_func_fw_cache = Dict()
for (i, vn) in enumerate(model.flattened_graph_node_data.sorted_nodes)
    new_node_function_exprs[i] = create_new_node_function(model.g[vn].node_function_expr, max_indices_length, max_loop_vars_length, vn, model.g[vn].loop_vars, model.g[vn].is_stochastic, model.g[vn].is_observed, expr_cache, evaluation_env)
    if haskey(evaled_func_cache, new_node_function_exprs[i])
        new_node_functions[i] = evaled_func_cache[new_node_function_exprs[i]]
        new_node_functions_fws[i] = evaled_func_fw_cache[new_node_function_exprs[i]]
    else
        new_node_functions[i] = eval(new_node_function_exprs[i])
        evaled_func_cache[new_node_function_exprs[i]] = new_node_functions[i]
        new_node_functions_fws[i] = fw_type(new_node_functions[i])
        evaled_func_fw_cache[new_node_function_exprs[i]] = new_node_functions_fws[i]
    end
end
```

```julia
i = 2
vn = model.flattened_graph_node_data.sorted_nodes[i]
f = new_node_functions[i]
f_expr = new_node_function_exprs[i]
f(evaluation_env, eval_loop_var_vals[i], eval_vn_indices_vals[i], flattened_values, eval_start_idx_vals[i], eval_end_idx_vals[i])
f_fw = new_node_functions_fws[i]
f_fw(evaluation_env, eval_loop_var_vals[i], eval_vn_indices_vals[i], flattened_values, eval_start_idx_vals[i], eval_end_idx_vals[i])
@benchmark $f_fw($(evaluation_env), $(eval_loop_var_vals[i]), $(eval_vn_indices_vals[i]), $(flattened_values), $(eval_start_idx_vals[i]), $(eval_end_idx_vals[i]))
```

```julia
function _new_eval(evaluation_env, new_node_functions_fws, eval_loop_var_vals, eval_vn_indices_vals, flattened_values, eval_start_idx_vals, eval_end_idx_vals)
    logp = 0.0
    @inbounds for i in eachindex(new_node_functions_fws)
        vn = model.flattened_graph_node_data.sorted_nodes[i]
        evaluation_env, logp_i = new_node_functions_fws[i](evaluation_env, eval_loop_var_vals[i], eval_vn_indices_vals[i], flattened_values, eval_start_idx_vals[i], eval_end_idx_vals[i])
        logp += logp_i
    end
    return logp
end

_new_eval(evaluation_env, new_node_functions_fws, eval_loop_var_vals, eval_vn_indices_vals, inits_params, eval_start_idx_vals, eval_end_idx_vals)
```

The result is wrong, fix it!

```julia
@code_warntype _new_eval(evaluation_env, new_node_functions_fws, eval_loop_var_vals, eval_vn_indices_vals, inits_params, eval_start_idx_vals, eval_end_idx_vals)
```

```julia
@benchmark _new_eval($(evaluation_env), $(new_node_functions_fws), $(eval_loop_var_vals), $(eval_vn_indices_vals), $(inits_params), $(eval_start_idx_vals), $(eval_end_idx_vals))
```

the benchmark result is

```
BenchmarkTools.Trial: 10000 samples with 1 evaluation per sample.
 Range (min … max):  15.625 μs …   8.908 ms  ┊ GC (min … max):  0.00% … 99.57%
 Time  (median):     19.625 μs               ┊ GC (median):     0.00%
 Time  (mean ± σ):   23.368 μs ± 156.094 μs  ┊ GC (mean ± σ):  17.38% ±  3.12%

     ▂█▃             ▂                                          
  ▁▂▆███▇▄▂▂▂▂▃▃▃▂▃▅▇██▇▇▅▄▃▃▃▂▃▂▂▂▂▂▂▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▂
  15.6 μs         Histogram: frequency by time         29.1 μs <

 Memory estimate: 120.42 KiB, allocs estimate: 1468.
```

## TODOs
* Verify that the types are indeed stable for the wrapped functions
* investigate why benchmarking a FunctionWrapper directly is slower than benchmarking the wrapped function (overheads)
