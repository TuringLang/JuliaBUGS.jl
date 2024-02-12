function gen_compute_transformed_func(expr::Expr)
    _all_vars = extract_array_ndims(expr)
    all_vars = Tuple(keys(_all_vars))
    scalars = keys(filter(x -> last(x) == 0, pairs(_all_vars)))
    array_vars = setdiff(keys(_all_vars), scalars)

    return @q function __compute_transformed(
        data::NamedTuple{data_keys,data_value_types},
        array_sizes::NamedTuple{array_vars,array_var_types},
    ) where {data_keys,data_value_types,array_vars,array_var_types}
        env = Dict{
            Symbol,
            Union{Array{<:Union{Int,Float64,Missing}},Missing,Int,Float64},
        }()
        for var in $all_vars
            if var in data_keys
                # TODO: use `data_value_types`
                if getfield(data, var) isa Union{Int,Float64} || eltype(getfield(data, var)) <: Union{Int,Float64}
                    env[var] = getfield(data, var)
                else
                    env[var] = copy(getfield(data, var))
                end
            elseif var in $scalars
                env[var] = missing
            else
                env[var] = Array{Union{Int,Float64,Missing}}(
                    missing, getfield(array_sizes, var)...
                )
            end
        end
        $(gen_unpack_expr(all_vars)...)
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

@inline function gen_unpack_expr(all_vars)
    return [@q($v = env[$(Meta.quot(v))]) for v in all_vars]
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
            push!(args, stmt) # TODO: return the original statement for debugging
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
        lhs
    else
        lhs.args[1]
    end

    lhs = if lhs isa Symbol
        @q(env[$(Meta.quot(lhs))])
    else
        @capture(lhs, v_[indices__])
        @q(env[$(Meta.quot(v))][$(indices...)])
    end 

    rhs = MacroTools.postwalk(rhs) do sub_expr
        if @capture(sub_expr, f_(a__))
            if f in JuliaBUGS.BUGSPrimitives.BUGS_FUNCTIONS
                return @q(JuliaBUGS.BUGSPrimitives.$f($(a...)))
            end
        end
        return sub_expr
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
