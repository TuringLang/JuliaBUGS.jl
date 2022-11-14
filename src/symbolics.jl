# https://github.com/JuliaSymbolics/SymbolicUtils.jl/blob/a42082ac90f951f677ce1e2a91cd1a0ddd4306c6/src/substitute.jl#L1
# modified so that when the substitution result is `missing`, return the original expression
function SymbolicUtils.substitute(expr, dict; fold=true)
    haskey(dict, expr) && return ismissing(dict[expr]) ? expr : dict[expr]

    if istree(expr)
        op = substitute(operation(expr), dict; fold=fold)
        if fold
            canfold = !(op isa SymbolicUtils.Symbolic)
            args = map(SymbolicUtils.unsorted_arguments(expr)) do x
                x′ = substitute(x, dict; fold=fold)
                canfold = canfold && !(x′ isa SymbolicUtils.Symbolic)
                x′
            end
            canfold && return ismissing(op(args...)) ? expr : op(args...)
            args
        else
            args = map(x->substitute(x, dict, fold=fold), SymbolicUtils.unsorted_arguments(expr))
        end

        SymbolicUtils.similarterm(expr,
                    op,
                    args,
                    SymbolicUtils.symtype(expr);
                    metadata=SymbolicUtils.metadata(expr))
    else
        expr
    end
end

# Bugs in SymbolicUtils.jl
# Fixed at: https://github.com/JuliaSymbolics/SymbolicUtils.jl/pull/471
# Not in the latest release yet.
function SymbolicUtils.toterm(t::SymbolicUtils.Add{T}) where T
    args = Any[t.coeff, ]
    for (k, coeff) in t.dict
        push!(args, coeff == 1 ? k : SymbolicUtils.Term{T}(*, [coeff, k]))
    end
    SymbolicUtils.Term{T}(+, args)
end

"""
    tosymbolic(variable)

Return symbolic variable for multiple types of `variable`s. 
"""
tosymbolic(variable::Union{Int, AbstractFloat}) = Num(variable)
tosymbolic(variable::String) = tosymbolic(Symbol(variable))
function tosymbolic(variable::Symbol)
    if Meta.isexpr(Meta.parse(string(variable)), :ref)
        return ref_to_symbolic(string(variable))
    end

    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.Sym{Real}(variable),
        Symbolics.VariableSource,
        (:variables, variable),
    )
    return Symbolics.wrap(variable_with_metadata)
end
function tosymbolic(expr::Expr)
    if MacroTools.isexpr(expr, :ref)  
        return ref_to_symbolic(expr)
    else
        variables = find_all_variables(expr)
        expr = replace_variables(expr, variables)
        return eval(expr)
    end
end
tosymbolic(variable) = variable

function create_symbolic_array(array_name::Symbol, array_size::Vector)
    array_ranges = Tuple([(1:i) for i in array_size])
    variable_with_metadata = SymbolicUtils.setmetadata(
        SymbolicUtils.setmetadata(
            SymbolicUtils.Sym{Array{Real, (length)(array_ranges)}}(array_name), Symbolics.ArrayShapeCtx, array_ranges), 
            Symbolics.VariableSource, 
            (:variables, array_name))
    return Symbolics.wrap(variable_with_metadata)
end

function tosymbol(x)
    ex = Symbolics.toexpr(x)
    ex isa Symbol && return ex
    return "$(ex.args[2])" * "[" * join([string(i) for i in ex.args[3:end]], ", ") * "]" |> Symbol
end
