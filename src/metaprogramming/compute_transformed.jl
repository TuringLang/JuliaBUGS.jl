function gen_compute_transformed_func(expr::Expr)
    all_vars = Tuple(keys(extract_array_ndims(expr)))
    scalars = Tuple(keys(filter(x -> last(x) == 0, pairs(extract_array_ndims(expr)))))
    array_vars = setdiff(all_vars, scalars)
    vars_in_bounds_and_indices = extract_variables_used_in_bounds_and_indices(expr)
    vars_in_program = setdiff(all_vars, vars_in_bounds_and_indices)

    return @q function __compute_transformed(
        data::NamedTuple{data_keys,data_value_types},
        array_sizes::NamedTuple{array_vars,array_var_types},
    ) where {data_keys,data_value_types,array_vars,array_var_types}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, vars_in_bounds_and_indices...)), :data))

        _T = Union{Int,Float,Missing}
        env = Dict{Symbol,Union{Array{_T},_T}}()

        for (n, t) in zip(data_keys, data_value_types)
            if n in vars_in_bounds_and_indices
                continue
            elseif t isa Union{Int,Float64}
                env[n] = getfield(data, n)
            else
                if eltype(t) <: Union{Int,Float64}
                    env[n] = getfield(data, n)
                else
                    env[n] = copy(getfield(data, n))
                end
            end
        end

        for n in array_vars
            env[n] = Array{_T}(missing, array_sizes[n]...)
        end

        for s in setdiff($vars_in_program, array_vars)
            env[s] = missing
        end

        added_new_val = true
        while added_new_val
            added_new_val = false
            $(gen_compute_transformed_func_body!(expr, Any[])...)
        end
        for (k, v) in env
            if env[k] isa Array
                env[k] = map(identity, v)
            end
        end
  
        return env
    end
end

function gen_compute_transformed_func_body!(expr::Expr, args::Vector{Any})
    for stmt in expr.args
        if @capture(stmt, lhs_ = rhs_)
            push!(args, @q(JuliaBUGS.@try_compute($stmt)))
        elseif @capture(stmt, lhs_ ~ rhs_)
            nothing
        elseif @capture(
            stmt,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(args, @q(
                for $loop_var in ($lower):($upper)
                    $(gen_compute_transformed_func_body!(body, Any[])...)
                end
            ))
        else
            push!(args, stmt)
        end
    end
    return args
end

macro try_compute(expr::Expr)
    return esc(_try_compute(expr))
end

function _try_compute(expr::Expr)
    @assert Meta.isexpr(expr, :(=))
    lhs, rhs = expr.args

    lhs_var = if lhs isa Symbol
        @q(env[$(Meta.quot(lhs))])
    else
        var = lhs.args[1]
        @q(env[$(Meta.quot(var))])
    end

    lhs = if lhs isa Symbol
        @q(env[$(Meta.quot(lhs))])
    else
        @capture(lhs, v_[indices__])
        @q(env[$(Meta.quot(v))][$(indices...)])
    end

    rhs = MacroTools.postwalk(rhs) do sub_expr
        if @capture(sub_expr, f_(args__))
            f = if f in JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS
                @q(JuliaBUGS.BUGSPrimitives.$f)
            else
                f
            end

            for (i, arg) in enumerate(args)
                if arg isa Symbol
                    args[i] = @q(env[$(Meta.quot(arg))])
                end
            end
            return @q($f($(args...)))
        elseif @capture(sub_expr, v_[indices__])
            for (i, index) in enumerate(indices)
                if index isa Symbol
                    indices[i] = @q(env[$(Meta.quot(index))])
                end
            end
            @q(env[$(Meta.quot(v))][$(indices...)])
        else
            return sub_expr
        end
    end

    return @q begin
        lhs_val = $lhs
        if lhs_val isa Union{Int,Float64}
            nothing
        elseif lhs_val isa Array && all(!ismissing, lhs_val)
            nothing
        else
            value = try
                $rhs
            catch
                missing
            end
            if !(value isa Missing)
                $lhs = value
                added_new_val = true
                $lhs_var = env[$(Meta.quot(lhs_var))]
            end
        end
    end
end

function check_potential_conflict(
    env::Dict{Symbol,Union{Array{<:Union{Int,Float64,Missing}},Missing,Int,Float64}},
    potential_conflicted_scalars::Vector{Symbol},
    potential_conflicted_arrays::NamedTuple{names,types},
) where {names,types}
    for s in potential_conflicted_scalars
        if env[s] isa Missing
            error("$s is assigned to by both logical and stochastic variables.")
        end
    end

    for (s, a) in pairs(potential_conflicted_arrays)
        is = findall(a)
        for i in is
            if env[s][i] isa Missing
                error("$s is assigned to by both logical and stochastic variables.")
            end
        end
    end
end
