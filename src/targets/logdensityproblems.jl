struct BUGSLogDensityProblem
    """ map variables to their ids """
    vars::Bijection{Var,Int}
    """ identity array variables as logical or stochastic """
    var_types
    dep_graph::SimpleDiGraph
    sorted_nodes
    """ map variables to their transformation to unconstrained space """
    bijectors
    """ map variables to type of their prior distribution """
    prior_types
    logical_node_args
    logical_node_f_exprs
    stochastic_node_args
    stochastic_node_f_exprs
    logical_node_functions
    stochastic_node_functions
    link_functions
    array_variables
    init_trace
    variable_store
    """ list of stochastic variables that can't be resolved from data """
    parameters
    compiled_tape
    gradient_cfg
    all_results
end

function BUGSLogDensityProblem(
    vars,
    var_types,
    dep_graph,
    logical_node_args,
    logical_node_f_exprs,
    stochastic_node_args,
    stochastic_node_f_exprs,
    link_functions,
    array_variables,
    data,
    inits,
)
    logical_node_functions, stochastic_node_functions = Dict(), Dict()
    for (k, v) in logical_node_f_exprs
        if v isa Number
            logical_node_functions[k] = () -> v
        elseif v == :identity
            logical_node_functions[k] = identity
        elseif v == :missing
            logical_node_functions[k] = () -> missing
        else
            if isempty(MacroTools.splitdef(v)[:args])
                evaled_v = Base.invokelatest(eval(v))
                # @assert evaled_v isa Distributions.Distribution
                logical_node_functions[k] = () -> evaled_v
            else
                logical_node_functions[k] = @RuntimeGeneratedFunction(v)
            end
        end
    end

    for (k, v) in stochastic_node_f_exprs
        if isempty(MacroTools.splitdef(v)[:args])
            # @assert evaled_v isa Distributions.Distribution
            evaled_v = Base.invokelatest(eval(v))
            stochastic_node_functions[k] = () -> evaled_v
        else
            stochastic_node_functions[k] = @RuntimeGeneratedFunction(v)
        end
    end

    init_trace = Dict()
    parameters = []
    for var in keys(vars)
        if !haskey(var_types, var) # data array
            continue
        end
        var_types[var] != :stochastic && continue # this stage only deal with stochastic nodes

        value = JuliaBUGS.eval(var, data)
        if !isnothing(value)
            init_trace[var] = value
            continue
        end

        push!(parameters, var)
        value = JuliaBUGS.eval(var, inits)
        if isnothing(value)
            value = rand(size(var)...)
            # println(
            #     "No initial value provided for $var, initialized to $value by random sampling.",
            # )
        end
        @assert !haskey(init_trace, var)
        init_trace[var] = value
    end

    sorted_nodes = map(vars, topological_sort_by_dfs(dep_graph))
    bijectors, prior_types = Dict(), Dict()
    for var in sorted_nodes
        if var isa ArrayVariable && haskey(data, var.name)
            init_trace[var] = data[var.name]
        end
    end
    for var in sorted_nodes
        if var isa ArrayVariable && haskey(data, var.name)
            continue
        end
        if var_types[var] == :logical
            arguments = [init_trace[arg] for arg in logical_node_args[var]]
            if var in array_variables
                init_trace[var] = (logical_node_functions[var])(arguments)
            else
                init_trace[var] = (logical_node_functions[var])(arguments...)
            end
            # init_trace[var] = (logical_node_functions[var])(arguments...)
        elseif var_types[var] == :both
            arguments = [init_trace[arg] for arg in logical_node_args[var]]
            if var in array_variables
                init_trace[var] = (logical_node_functions[var])(arguments)
            else
                init_trace[var] = (logical_node_functions[var])(arguments...)
            end
            # init_trace[var] = (logical_node_functions[var])(arguments...)
            arguments = [init_trace[arg] for arg in stochastic_node_args[var]]
            bijectors[var] = Bijectors.bijector(
                (stochastic_node_functions[var])(arguments...)
            )
            prior_types[var] = typeof((stochastic_node_functions[var])(arguments...))
        else
            # assume that: if a node function can return different types of Distributions, they would have the same support
            arguments = [init_trace[arg] for arg in stochastic_node_args[var]]
            bijectors[var] = Bijectors.bijector(
                (stochastic_node_functions[var])(arguments...)
            )
            prior_types[var] = typeof((stochastic_node_functions[var])(arguments...))
        end
    end

    return BUGSLogDensityProblem(
        vars,
        var_types,
        dep_graph,
        sorted_nodes,
        bijectors,
        prior_types,
        logical_node_args,
        logical_node_f_exprs,
        stochastic_node_args,
        stochastic_node_f_exprs,
        logical_node_functions,
        stochastic_node_functions,
        link_functions,
        array_variables,
        init_trace,
        data,
        parameters,
        nothing,
        nothing,
        nothing,
    )
end

function gen_init_params(p::BUGSLogDensityProblem, transform=true)
    if transform
        return transform_and_flatten(p.init_trace, p.parameters, p.bijectors)
    else
        return flatten(p.init_trace, p.parameters)
    end
end

function flatten(trace, parameters)
    return vcat([deepcopy(trace[var]) for var in parameters]...)
end

function unflatten(trace, parameters, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = value
    end
    return trace
end

function transform_and_flatten(trace, parameters, bijectors)
    return vcat([bijectors[var](deepcopy(trace[var])) for var in parameters]...)
end

function unflatten_and_untransform(trace, parameters, bijectors, flattened_vales)
    trace = deepcopy(trace)
    for (var, value) in zip(parameters, flattened_vales)
        trace[var] = inv(bijectors[var])(value)
    end
    return trace
end

function (p::BUGSLogDensityProblem)(x, transform=true)
    if transform
        trace = unflatten_and_untransform(p.init_trace, p.parameters, p.bijectors, x)
    else
        trace = unflatten(p.init_trace, p.parameters, x)
    end
    return logjoint(p, trace)
end

function logjoint(p::BUGSLogDensityProblem, trace)
    var_types = p.var_types
    sorted_nodes = p.sorted_nodes
    logical_node_args = p.logical_node_args
    logical_node_functions = p.logical_node_functions
    stochastic_node_args = p.stochastic_node_args
    stochastic_node_functions = p.stochastic_node_functions
    link_functions = p.link_functions
    init_trace = p.init_trace
    array_variables = p.array_variables

    logjoint = 0.0
    for var in sorted_nodes
        if !haskey(var_types, var) # data array
            continue
        end
        if var_types[var] == :logical
            arguments = [trace[arg] for arg in logical_node_args[var]]
            # trace[var] = logical_node_functions[var](arguments...)
            if var in array_variables
                init_trace[var] = (logical_node_functions[var])(arguments)
            else
                init_trace[var] = (logical_node_functions[var])(arguments...)
            end
        elseif var_types[var] == :both
            arguments = [trace[arg] for arg in logical_node_args[var]]
            if var in array_variables
                init_trace[var] = (logical_node_functions[var])(arguments)
            else
                init_trace[var] = (logical_node_functions[var])(arguments...)
            end
            # trace[var] = logical_node_functions[var](arguments...)
            arguments = [trace[arg] for arg in stochastic_node_args[var]]
            if haskey(link_functions, var)
                logjoint += logpdf(
                    (stochastic_node_functions[var])(arguments...),
                    eval(link_functions[var])(trace[var]),
                )
            else
                logjoint += logpdf(
                    (stochastic_node_functions[var])(arguments...), trace[var]
                )
            end
        else
            arguments = [trace[arg] for arg in stochastic_node_args[var]]
            if haskey(link_functions, var)
                logjoint += logpdf(
                    (stochastic_node_functions[var])(arguments...),
                    eval(link_functions[var])(trace[var]),
                )
            else
                logjoint += logpdf(
                    (stochastic_node_functions[var])(arguments...), trace[var]
                )
            end
        end
    end
    return logjoint
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, x)
    return p(x)
end

function LogDensityProblems.dimension(p::BUGSLogDensityProblem)
    return length(gen_init_params(p))
end

# TODO: check https://github.com/tpapp/LogDensityProblemsAD.jl/blob/master/ext/LogDensityProblemsADReverseDiffExt.jl
function LogDensityProblems.logdensity_and_gradient(p::BUGSLogDensityProblem, x)
    ReverseDiff.gradient!(p.all_results, p.compiled_tape, x)
    return ReverseDiff.DiffResults.value(p.all_results),
    ReverseDiff.DiffResults.gradient(p.all_results)
end

function LogDensityProblems.capabilities(p::BUGSLogDensityProblem)
    if all((x) -> x <: ContinuousDistribution, values(p.prior_types))
        return LogDensityProblems.LogDensityOrder{1}()
    else
        return LogDensityProblems.LogDensityOrder{0}()
    end
end

function transform_samples(p::BUGSLogDensityProblem, flattened_vales::Vector)
    trace = deepcopy(p.init_trace)
    for (var, value) in zip(p.parameters, flattened_vales)
        trace[var] = inv(p.bijectors[var])(value)
    end
    for var in p.sorted_nodes
        arguments = [trace[arg] for arg in p.node_args[var]]
        if p.var_types[var] == :logical
            trace[var] = (p.logical_node_functions[var])(arguments...)
        else
            continue
        end
    end
    return trace
end
