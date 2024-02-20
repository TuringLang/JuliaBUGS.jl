using StaticArrays: StaticArrays
using MacroTools: prewalk, postwalk, @q, @qq

abstract type Analysis end

const __RHS_UNION_TYPE__ = Union{Int,Float64,Symbol,Expr}
const __REAL_WITH_MISSING__ = Union{Int,Float64,Missing}
const __REAL__ = Union{Int,Float64}

include("utils.jl")
include("determine_array_sizes.jl")
include("check_multiple_assignments.jl")

function create_evaluate_env(
    all_vars::Tuple{Vararg{Symbol}},
    data::NamedTuple{data_vars,data_var_types},
    array_sizes::NamedTuple{array_vars},
) where {data_vars,data_var_types,array_vars}
    scalars_not_data = Tuple(setdiff(all_vars, array_vars, data_vars))
    array_vars_not_data = Tuple(setdiff(array_vars, data_vars))

    need_copy = [t <: Array && Missing <: eltype(t) for t in data_var_types.parameters]
    data_copy = NamedTuple{data_vars}(
        Tuple([
            if need_copy[i]
                copy(getfield(data, data_vars[i]))
            else
                getfield(data, data_vars[i])
            end for i in eachindex(data_vars)
        ])
    )

    init_scalars = Tuple([missing for i in 1:length(scalars_not_data)])
    init_arrays = Tuple([
        Array{__REAL_WITH_MISSING__}(missing, array_sizes[array_vars_not_data[i]]...) for
        i in eachindex(array_vars_not_data)
    ])

    return merge(
        data_copy,
        NamedTuple{scalars_not_data}(init_scalars),
        NamedTuple{array_vars_not_data}(init_arrays),
    )
end

include("compute_transformed.jl")

function check_conflicts(
    eval_env::NamedTuple{variable_names},
    conflicted_scalars::Tuple{Vararg{Symbol}},
    conflicted_arrays::NamedTuple{array_names,array_types},
) where {variable_names,array_names,array_types}
    for scalar in conflicted_scalars
        if eval_env[scalar] isa Missing
            error("$scalar is assigned by both logical and stochastic variables.")
        end
    end

    for (array_name, conflict_array) in pairs(conflicted_arrays)
        missing_values = ismissing.(eval_env[array_name])
        conflicts = conflict_array .& missing_values
        if any(conflicts)
            error(
                "$(array_name)[$(join(Tuple.(findall(conflicts)), ", "))] is assigned by both logical and stochastic variables.",
            )
        end
    end
end

function concretize_eval_env_value_types(
    eval_env::NamedTuple{variable_names,variable_types}
) where {variable_names,variable_types}
    return NamedTuple{variable_names}(
        Tuple([
            if type === Missing ||
                type <: Union{Int,Float64} ||
                eltype(type) === Missing ||
                eltype(type) <: Union{Int,Float64}
                value
            else # Missing <: eltype(type)
                map(identity, value)
            end for (value, type) in zip(values(eval_env), variable_types.parameters)
        ]),
    )
end

include("loop_iterations.jl")

function initialize_vertex_id_map(eval_env::NamedTuple{var_names}) where {var_names}
    vertex_id_map = Array{Union{Ref{Int},Array{Int}}}(undef, length(var_names))
    for (i, k) in enumerate(var_names)
        if eval_env[k] isa AbstractArray
            vertex_id_map[i] = zeros(Int, size(eval_env[k])...)
        else
            vertex_id_map[i] = Ref(0)
        end
    end
    return NamedTuple{var_names}(Tuple(vertex_id_map))
end

include("build_graph.jl")
