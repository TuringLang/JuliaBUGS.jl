struct MarkovBlanketBUGSModel <: AbstractBUGSModel
    varinfo # parent_model.varinfo serves as prototype instead of concrete state, we'll save the varinfo in gibbs state, and this is to be passed to LogDensityProblems 
    target_vars::Vector{VarName}
    members::Vector{VarName}
    sorted_nodes::Vector{VarName}
    parent_model::BUGSModel
end

function MarkovBlanketBUGSModel(
    m::BUGSModel, var_group::Union{VarName,Vector{VarName}}, varinfo=m.varinfo
)
    var_group = var_group isa VarName ? [var_group] : var_group

    # check inputs
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
    for vn in m.sorted_nodes # keep the order of the original model
        if vn in blanket_with_vars
            push!(sorted_blanket_with_vars, vn)
        end
    end
    return MarkovBlanketBUGSModel(varinfo, var_group, blanket, sorted_blanket_with_vars, m)
end

function AbstractPPL.evaluate!!(
    model::MarkovBlanketBUGSModel, ::LogDensityContext, flattened_values::AbstractVector
)
    transformed = model.parent_model.transformed
    var_lengths = if transformed
        model.parent_model.transformed_var_lengths
    else
        model.parent_model.untransformed_var_lengths
    end
    param_length = sum(var_lengths[v] for v in model.target_vars)
    sorted_nodes = model.sorted_nodes
    @assert length(flattened_values) == param_length
    g = model.parent_model.g
    vi = deepcopy(model.varinfo)
    current_idx = 1
    logp = 0.0
    for vn in sorted_nodes
        ni = g[vn]
        @unpack node_type, node_function_expr, node_args = ni
        args = (; map(arg -> getsym(arg) => vi[arg], node_args)...)
        expr = node_function_expr.args[2]
        if node_type == JuliaBUGS.Logical
            value = _eval(expr, args)
            vi = setindex!!(vi, value, vn)
        else
            dist = _eval(expr, args)
            if vn in model.target_vars
                l = var_lengths[vn]
                if transformed
                    value, logjac = DynamicPPL.with_logabsdet_jacobian_and_reconstruct(
                        Bijectors.inverse(bijector(dist)),
                        dist,
                        flattened_values[current_idx:(current_idx + l - 1)],
                    )
                else
                    value = DynamicPPL.reconstruct(
                        dist, flattened_values[current_idx:(current_idx + l - 1)]
                    )
                    logjac = 0.0
                end
                current_idx += l
                logp += logpdf(dist, value) + logjac
                vi = setindex!!(vi, value, vn)
            else
                logp += logpdf(dist, vi[vn])
            end
        end
    end
    return vi, logp
end

function LogDensityProblems.dimension(model::MarkovBlanketBUGSModel)
    length_dict = if model.parent_model.transformed
        model.parent_model.transformed_var_lengths
    else
        model.parent_model.untransformed_var_lengths
    end
    return sum(length_dict[v] for v in model.target_vars)
end
