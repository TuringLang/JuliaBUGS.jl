###
### Array Interface
###

# Main idea behind implementation:
# 1. The target is to create a symbolic array (defined in Symbolics.jl) with the same name and size as the array in the model.
# 2. The size deduction is implemented as a side-effect of the `ref_to_symbolic!` function: it will treat the largest index seen as the size of the array.
# 3. Slice indexing is simply slice indexing with the symbolic array.

# Notes on correctness:
# - all indicies are need to appear on the LHS: this is implicitly checked by `gen_output` in `compiler.jl`

function exist_colon_indexing(expr)
    exist_colon = false
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_[is_])
            if any(x->x==:(:), is)
                exist_colon = true
            end
        end
    end
    return exist_colon
end

"""
    ref_to_symbolic(expr, compiler_state)

Return a symbolic variable for the referred array element. No side-effect.
"""
ref_to_symbolic(s::String) = ref_to_symbolic(Meta.parse(s))
function ref_to_symbolic(expr::Expr)
    name = expr.args[1]
    indices = map(eval, expr.args[2:end]) # deal with case like a[:(2-1):2]
    if any(x->!isa(x, Integer), indices)
        error("Only support integer indices.")
    end
    ret = create_symbolic_array(name, indices)
    return ret[indices...]
end

"""
    ref_to_symbolic!(expr, compiler_state)

Return a a symbolic variable or symbolic array for an `ref` expression.
"""
function ref_to_symbolic!(expr::Expr, compiler_state::CompilerState, skip_colon = true)
    numdims = length(expr.args) - 1
    @assert numdims > 0 "Indices can't be empty, for `p[1:end]`, use shorthand `p[:]` instead."
    name = expr.args[1]
    indices = expr.args[2:end]
    for (i, index) in enumerate(indices)
        if index isa Expr || (index isa Symbol && index != :(:))
            if Meta.isexpr(index, :call) && index.args[1] == :(:)
                lb = resolve(index.args[2], compiler_state.logicalrules) 
                ub = resolve(index.args[3], compiler_state.logicalrules)
                if lb isa Real && ub isa Real
                    indices[i].args[2] = lb
                    indices[i].args[3] = ub
                else
                    return __SKIP__
                end
            end

            resolved_index = resolve(tosymbolic(index), compiler_state.logicalrules)
            if !isa(resolved_index, Union{Real, UnitRange})
                return __SKIP__
            end 

            if isa(resolved_index, Real) 
                isinteger(resolved_index) || error("Index of $expr needs to be integers.")
                indices[i] = Integer(resolved_index)
            else
                indices[i] = resolved_index
            end
        end
    end

    if haskey(compiler_state.data_arrays, name)
        array = compiler_state.data_arrays[name]
        if ndims(array) == numdims
            for (i, index) in enumerate(indices)
                if index == :(:)
                    indices[i] = Colon()
                end
            end
            return array[indices...] # implicitly checking if indices are valid
        else
            error("Dimension mismatch.")
        end 
    end

    if !haskey(compiler_state.arrays, name)
        arraysize = deepcopy(indices)
        for (i, index) in enumerate(indices)
            if index isa UnitRange
                arraysize[i] = index[end]
            elseif index == :(:)
                if skip_colon
                    return __SKIP__
                end
                arraysize[i] = 1
                indices[i] = Colon()
            end
        end
        array = create_symbolic_array(name, arraysize)
        compiler_state.arrays[name] = array
        return array[indices...]
    end

    # if array exists
    array = compiler_state.arrays[name]
    if ndims(array) == numdims
        array_size = collect(size(array))
        for (i, index) in enumerate(indices)
            if index isa UnitRange
                array_size[i] = max(array_size[i], index[end]) # in case 'high' is Expr
            elseif index == :(:)
                if skip_colon
                    return __SKIP__
                end
                indices[i] = Colon()
            elseif index isa Integer
                array_size[i] = max(indices[i], array_size[i])
            else
                error("Indexing syntax is wrong.")
            end
        end

        if all(array_size .== size(array))
            return array[indices...]
        else
            compiler_state.arrays[name] = create_symbolic_array(name, array_size)
            return compiler_state.arrays[name][indices...]
        end
    end

    error("Dimension doesn't match!")
end

const __SKIP__ = tosymbolic("SKIP")