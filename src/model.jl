# AbstractBUGSModel can't be a subtype of AbstractProbabilisticProgram (<: AbstractMCMC.AbstractModel)
# because it will then dispatched to https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/sample.jl#L81
# instead of https://github.com/TuringLang/AbstractMCMC.jl/blob/d7c549fe41a80c1f164423c7ac458425535f624b/src/logdensityproblems.jl#L90
abstract type AbstractBUGSModel end

"""
    BUGSModel

The `BUGSModel` object is used for inference and represents the output of compilation. It fully implements the
[`LogDensityProblems.jl`](https://github.com/tpapp/LogDensityProblems.jl) interface.

# Fields

- `param_length::Int`: The length of the parameters vector, defining the number of parameters in the model, store a tuple of integers,
    where the first integer is the length of the parameters vector in the original space, and the second integer is the length of the 
    parameters vector in the transformed space.
- `var_lengths::Dict{VarName,Tuple{Int,Int}}`: A dictionary that maps the names of the variables in the model to the corresponding
    lengths of the variables in the original space and the transformed space.
- `varinfo::SimpleVarInfo`: An instance of 
    [`DynamicPPL.SimpleVarInfo`](https://turinglang.org/DynamicPPL.jl/dev/api/#DynamicPPL.SimpleVarInfo), 
    specifically a dictionary that maps both data and value of variables in the model to the corresponding values.
- `parameters::Vector{VarName}`: A vector containing the names of the parameters in the model. These parameters are defined to be 
    stochastic variables that are not observed.
- `g::BUGSGraph`: An instance of [`BUGSGraph`](@ref), representing the dependency graph of the model.
- `sorted_nodes::Vector{VarName}`: A vector containing the names of all the variables in the model, sorted in topological order.

"""
struct BUGSModel <: AbstractBUGSModel
    transformed::Bool
    untransformed_param_length::Int
    transformed_param_length::Int
    # TODO: the following two dictionaries are likely to be very similar, optimize this
    untransformed_var_lengths::Dict{VarName,Int}
    transformed_var_lengths::Dict{VarName,Int}
    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    sorted_nodes::Vector{VarName}
end

"""
    param_names(m::BUGSModel)

Return the names of the parameters in the model.
"""
param_names(m::BUGSModel) = m.parameters

"""
    all_variables(m::BUGSModel)

Return the names of all the variables in the model.
"""
all_variables(m::BUGSModel) = labels(m.g)

"""
    generated_variables(m::BUGSModel)

Return the names of the generated variables in the model.
"""
generated_variables(m::BUGSModel) = find_generated_vars(m.g)

struct UninitializedVariableError <: Exception
    msg::String
end

function BUGSModel(
    g, sorted_nodes, vars, array_sizes, data, inits; is_transformed::Bool=true
)
    vs = initialize_var_store(data, vars, array_sizes)
    vi = SimpleVarInfo(vs)
    parameters = VarName[]
    untransformed_param_length = 0
    transformed_param_length = 0
    untransformed_var_lengths = Dict{VarName,Int}()
    transformed_var_lengths = Dict{VarName,Int}()
    for vn in sorted_nodes
        @assert !(g[vn] isa AuxiliaryNodeInfo) "Auxiliary nodes should not be in the graph, but $(g[vn]) is."

        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = try
                _eval(expr, args)
            catch _
                rethrow(
                    UninitializedVariableError(
                        "Encounter error when evaluating the RHS of $vn. Try to initialize variables $(join(collect(keys(args)), ", ")) directly first if not yet.",
                    ),
                )
            end
            @assert value isa Union{Real,Array{<:Real}} "$value is not a number or array"
            vi = setindex!!(vi, value, vn)
        else
            dist = try
                _eval(expr, args)
            catch _
                rethrow(
                    UninitializedVariableError(
                        "Encounter support error when evaluating the distribution of $vn. Try to initialize variables $(join(collect(keys(args)), ", ")) first if not yet.",
                    ),
                )
            end
            value = evaluate(vn, data) # `evaluate(::VarName, env)` is defined in `src/utils.jl`
            if value isa Nothing # not observed
                push!(parameters, vn)
                this_param_length = length(dist)
                untransformed_param_length += this_param_length

                @assert length(dist) == _length(vn) begin
                    "The dimensionality of distribution $dist: $(length(dist)) does not match length of variable $vn: $(_length(vn)), " *
                    "please note that if the distribution is a multivariate distribution, " *
                    "the left hand side variable should use explicit indexing, e.g. x[1:2] ~ dmnorm(...)."
                end
                if bijector(dist) == identity
                    this_param_transformed_length = this_param_length
                else
                    this_param_transformed_length = length(Bijectors.transformed(dist))
                end
                untransformed_var_lengths[vn] = this_param_length
                transformed_var_lengths[vn] = this_param_transformed_length
                transformed_param_length += this_param_transformed_length
                value = evaluate(vn, inits) # use inits to initialize the value if available
                if value isa Nothing # not initialized
                    vi = setindex!!(vi, rand(dist), vn)
                else
                    vi = setindex!!(vi, value, vn)
                end
            else
                vi = setindex!!(vi, value, vn)
            end
        end
    end
    @assert (isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) ==
        untransformed_param_length "$(isempty(parameters) ? 0 : sum(_length(x) for x in parameters)) $untransformed_param_length"
    return BUGSModel(
        is_transformed,
        untransformed_param_length,
        transformed_param_length,
        untransformed_var_lengths,
        transformed_var_lengths,
        vi,
        parameters,
        g,
        sorted_nodes,
    )
end

function initialize_var_store(data, vars, array_sizes)
    var_store = Dict{VarName,Any}()
    array_vn(k::Symbol) = AbstractPPL.VarName{Symbol(k)}(AbstractPPL.IdentityLens())
    for k in keys(data)
        v = data[k]
        vn = array_vn(k)
        var_store[vn] = v
    end
    for k in keys(array_sizes)
        v = array_sizes[k]
        vn = array_vn(k)
        if !haskey(var_store, vn)
            # var_store[vn] = zeros(v...)
            var_store[vn] = Array{Float64}(undef, v...)
        end
    end
    for v in keys(vars)
        if v isa Scalar
            vn = to_varname(v)
            var_store[vn] = 0.0
        end
    end
    return var_store
end

function get_params_varinfo(m::BUGSModel)
    return get_params_varinfo(m, m.varinfo)
end
function get_params_varinfo(m::BUGSModel, vi::SimpleVarInfo)
    d = Dict{VarName,Any}()
    for param in m.parameters
        d[param] = vi[param]
    end
    return SimpleVarInfo(d, vi.logp, vi.transformation)
end

"""
    MarkovBlanketCoveredBUGSModel

The model object for a BUGS model with Markov blanket covered.
"""
struct MarkovBlanketCoveredBUGSModel <: AbstractBUGSModel
    # `sorted_nodes` is used for iterating over the nodes in the model
    # `param_length` is used for specifying the length of the parameters vector 
    transformed::Bool
    untransformed_param_length::Int
    transformed_param_length::Int
    sorted_nodes::Vector{VarName}

    # these are fields of the original `BUGSModel`
    base_untransformed_param_length::Int
    base_transformed_param_length::Int
    untransformed_var_lengths::Dict{VarName,Int}
    transformed_var_lengths::Dict{VarName,Int}
    varinfo::SimpleVarInfo
    parameters::Vector{VarName}
    g::BUGSGraph
    base_sorted_nodes::Vector{VarName}
end

function MarkovBlanketCoveredBUGSModel(
    m::BUGSModel,
    var_group::Union{VarName,Vector{VarName}};
    is_transformed::Bool=m.transformed,
)
    var_group = var_group isa VarName ? [var_group] : var_group
    non_vars = VarName[]
    logical_vars = VarName[]
    for var in var_group
        if var ∉ labels(m.g)
            push!(non_vars, var)
        elseif m.g[var].node_type == Logical
            push!(logical_vars, var)
        end
    end
    isempty(non_vars) || error("Variables $(non_vars) are not in the model")
    isempty(logical_vars) ||
        warn("Variables $(logical_vars) are not stochastic variables, they will be ignored")
    blanket = markov_blanket(m.g, var_group)
    blanket_with_vars = union(blanket, var_group)
    sorted_blanket_with_vars = VarName[]
    for vn in m.sorted_nodes
        if vn in blanket_with_vars
            push!(sorted_blanket_with_vars, vn)
        end
    end
    untransformed_param_length = 0
    transformed_param_length = 0
    for vn in m.sorted_nodes
        if vn in sorted_blanket_with_vars &&
            !(m.g[vn].node_type == JuliaBUGS.Logical) &&
            vn ∈ m.parameters
            @unpack node_function_expr, node_args = m.g[vn]
            dist = _eval(
                node_function_expr.args[2],
                Dict(getsym(arg) => m.varinfo[arg] for arg in node_args),
            )
            untransformed_param_length += length(dist)
            if bijector(dist) == identity
                transformed_param_length += length(dist)
            else
                transformed_param_length += length(Bijectors.transformed(dist))
            end
        end
    end
    return MarkovBlanketCoveredBUGSModel(
        is_transformed,
        untransformed_param_length,
        transformed_param_length,
        sorted_blanket_with_vars,
        m.untransformed_param_length,
        m.transformed_param_length,
        m.untransformed_var_lengths,
        m.transformed_var_lengths,
        m.varinfo,
        m.parameters,
        m.g,
        m.sorted_nodes,
    )
end

function BUGSModel(m::MarkovBlanketCoveredBUGSModel; is_transformed=m.transformed)
    return BUGSModel(
        is_transformed,
        m.base_untransformed_param_length,
        m.base_transformed_param_length,
        m.untransformed_var_lengths,
        m.transformed_var_lengths,
        m.varinfo,
        m.parameters,
        m.g,
        m.sorted_nodes,
    )
end

function settrans(model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel}, bool::Bool)
    return @set model.transformed = bool
end

"""
    DefaultContext

Use values in varinfo to compute the log joint density.
"""
struct DefaultContext <: AbstractPPL.AbstractContext end

"""
    SamplingContext

Do an ancestral sampling of the model parameters. Also accumulate log joint density.
"""
struct SamplingContext <: AbstractPPL.AbstractContext
    rng::Random.AbstractRNG
end
SamplingContext() = SamplingContext(Random.default_rng())

"""
    LogDensityContext

Use the given values to compute the log joint density.
"""
struct LogDensityContext <: AbstractPPL.AbstractContext end

function AbstractPPL.evaluate!!(model::BUGSModel, rng::Random.AbstractRNG)
    return evaluate!!(model, SamplingContext(rng))
end
function AbstractPPL.evaluate!!(model::BUGSModel, ctx::SamplingContext)
    @unpack varinfo, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            # under `SamplingContext`, `transformation` is ignored
            # we sample and score both in the original variable space
            value = rand(ctx.rng, dist)
            logp += logpdf(dist, value)
            vi = setindex!!(vi, value, vn)
        end
    end
    return @set vi.logp = logp
end

function AbstractPPL.evaluate!!(model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel})
    return AbstractPPL.evaluate!!(model, DefaultContext())
end
function AbstractPPL.evaluate!!(
    model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel}, ::DefaultContext
)
    @unpack varinfo, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            value = vi[vn]
            if model.transformed
                # although the values stored in `vi` are in their original space, 
                # when `DynamicTransformation`, we behave as accepting a vector of 
                # parameters in the transformed space
                value_transformed = transform(bijector(dist), value)
                logp +=
                    logpdf(dist, value) +
                    logabsdetjac(Bijectors.inverse(bijector(dist)), value_transformed)
            else
                logp += logpdf(dist, value)
            end
        end
    end
    return vi, logp
end

function AbstractPPL.evaluate!!(
    model::Union{BUGSModel,MarkovBlanketCoveredBUGSModel},
    ::LogDensityContext,
    flattened_values::AbstractVector,
)
    is_transformed = model.transformed
    param_length =
        is_transformed ? model.transformed_param_length : model.untransformed_param_length
    var_lengths =
        is_transformed ? model.transformed_var_lengths : model.untransformed_var_lengths
    @assert length(flattened_values) == param_length
    @unpack varinfo, parameters, g, sorted_nodes = model
    vi = deepcopy(varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = Dict(getsym(arg) => vi[arg] for arg in node_args)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if vn in parameters
                if is_transformed
                    l = var_lengths[vn]
                    value_transformed = flattened_values[current_idx:(current_idx + l - 1)]
                    current_idx += l
                    # TODO: this use `DynamicPPL.reconstruct`, which needs attention when decoupling from DynamicPPL
                    value, logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                        Bijectors.inverse(bijector(dist)), dist, value_transformed
                    )
                    logp += logpdf(dist, value) + logjac
                    vi = setindex!!(vi, value, vn)
                else
                    l = var_lengths[vn]
                    value = DynamicPPL.reconstruct(
                        dist, flattened_values[current_idx:(current_idx + l - 1)]
                    )
                    current_idx += l
                    logp += logpdf(dist, value)
                    vi = setindex!!(vi, value, vn)
                end
            else
                logp += logpdf(dist, vi[vn])
            end
        end
    end
    return vi, logp
end
