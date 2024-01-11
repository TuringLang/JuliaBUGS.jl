# loop fission makes performance not obvious to programmers: 
# if we do source to source transformation for logp computation, we can add argument so that loops are not touched in the transformed code

function separate_statements(@nospecialize(expr))
    assignments = filter(!Base.Fix2(Meta.isexpr, :for), expr.args)
    fissioned_loops = loop_fission_helper(expr.args)
    return assignments, fissioned_loops
end

function loop_fission_helper(exprs::Vector{Expr})
    loops = []
    for sub_expr in exprs
        if MacroTools.@capture(
            sub_expr,
            for loop_var_ in l_:h_
                body__
            end
        )
            for ex in body
                if Meta.isexpr(ex, :for)
                    inner_loops = loop_fission_helper([ex])
                else
                    inner_loops = [ex]
                end
                for inner_l in inner_loops
                    push!(loops, MacroTools.@q(
                        for $loop_var in ($l):($h)
                            $inner_l
                        end
                    ))
                end
            end
        end
    end
    return loops
end

# E is either = or ~
mutable struct Statement{E}
    lhs
    rhs
end

# check if there is function call or indexing in the LHS indices
# ! the original BUGS will error if there is function call in the LHS indices
function analyze_lhs(@nospecialize(lhs_expr))
    if lhs_expr isa Symbol
        return false
    else
        @capture(lhs_expr, var_[idxs__])
        contain_function_call = false
        contain_indexing = false
        for idx in idxs
            MacroTools.postwalk(idx) do ex
                if @capture(ex, f_(args__))
                    if f ∉ (:+, :-, :*, :/, :^)
                        contain_function_call = true
                    end
                elseif @capture(ex, var_[idxs__])
                    # if the index doesn't not involve a loop var, then it's fine
                    contain_indexing = true
                end
                return ex
            end
            if contain_function_call || contain_indexing
                return true
            end
        end
        return false
    end
end

# the point is, LHS if no function call and no indexing, then the size is easy to determine: can we decide if the index is monotone wrt the loop var?
# this may not be the case: say i - j where i and j are loop vars, still the function can be figure out -- these are linear functions

function Statement(@nospecialize(expr))
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    return Statement{sign}(lhs, rhs)
end

mutable struct ForStatement{E}
    nested_levels::Int
    loop_var::Vector{Symbol}
    bounds
    lhs
    rhs
end

function ForStatement(@nospecialize(expr))
    nested_levels = 0
    loop_vars = []
    bounds = []
    while Meta.isexpr(expr, :for)
        @capture(
            expr,
            for loop_var_ in l_:h_
                body__
            end
        )
        push!(loop_vars, loop_var)
        # want to evaluate the bounds now, can do later
        push!(bounds, :(($l):($h)))
        nested_levels += 1
        expr = body[1]
    end
    sign = :(=)
    @capture(expr, lhs_ = rhs_) || @capture(expr, lhs_ ~ rhs_) && (sign = :(~))
    return ForStatement{sign}(nested_levels, loop_vars, bounds, lhs, rhs)
end

mutable struct Program
    statements::Vector
    tensor_sizes
end

function Program(@nospecialize(expr))
    assignments, fissioned_loops = separate_statements(expr)
    # deciding the tensor size is simple: only look at the LHS
    # because we don't allow function application, the only source of issue is the array indexing
    # if lhs idx doesn't contain array indexing, then we are good to do this in time linear in num of statements
    decide_tensor_size([assignments..., fissioned_loops...])

    # then transformed variables
    # the crux can be: "do we have a chance to evaluate this?"
    # again, due to the indirect jump provided by array indexing, we can't be absolute certain
    # but if all the variables on the RHS is part of data, then it's worth a shot
    # regarding functions, if the functions are not in indices, then we can also eval it
    # * even if solver, it's fine as long as it's really transformed variable

    # we can build dependency graph now if the program is regular
    # Definition: the program is regular/simple if all indices expressions do not contain
    # indexing and function application, otherwise, in bounds checking is either done at run time
    # and fine_grain dependencies can only be determined with unrolling
end

function decide_tensor_size(m, stmts)
    stmt_ids = Dict()
    for (i, stmt) in enumerate(stmts)
        stmt_ids[stmt.lhs] = i
    end # reverse look up

    tensor_size = Dict{Symbol, Any}()
    for stmt in stmts
        var = if stmt.lhs isa Expr 
            stmt.lhs.args[1] # (:ref, var, idxs...)
        else
            stmt.lhs
        end
        
        if var isa Symbol # scalar
            tensor_size[var] = 1
        else # array
            idxs = stmt.lhs.args[2:end]

            # expression of indices can be arbitrary in the sense that
            # it can be quadratic or even exponential in the loop vars
            
            # easy case: `i`, `i + j`, `i + 1` etc
            # harder: `i - j`, ` 10 - i + j` : polyhedron
            # even harder: `i(j - 1)`
            # impossible: `i^2 - j^2` ...
            # worst case still need to brute force
            # but most program is in the easy case

            evaled_args = [Base.eval(m, idx) for idx in idxs]
            # maybe use my `eval` function
            if stmt.lhs isa Expr
                tensor_size[var] = size(stmt.lhs.args[2])
            else
                tensor_size[var] = 1
            end
        end
    end
end

# graph building: the difficulty is in the find-grain dependencies, i.e., the element-wise dependencies. Because we allow function in indices, etc, this requires evaluation; can we relax it?
# the missing values are another source of uncertainty, particularly if they are used as indices, akin to pointers

# maybe we can just use `eval`

# Worst case is the "jump" using array contents, these creates irregular patterns

# create a new module with the given bindings
function create_module_with_bindings(bindings::NamedTuple)
    mod = Module()
    Base.eval(mod, :(using Base: eval))
    Base.eval(mod, :(using JuliaBUGS.BUGSPrimitives))
    for (name, value) in pairs(bindings)
        Base.eval(mod, :($name = $value))
    end
    return mod
end

# I am trying to design a high performance evaluation environment
# it needs to provide the following features:
# 1. allow scheme style layering of the environment: lookup value from the outer environment if not found in the inner environment
# 2. work well with Julia's module system: environment doesn't need to store function, just values, but can be arrays
# 3. some of the values should be immutable, because they are data given as constants, 
# 4. because user can give arrays with missing values, the missing values are values can be mutated, but it should not mutate the original data
# 5. it should be type stable
struct Environment
    outer::Union{Environment, Nothing}
    bindings::Dict{Symbol, Any}
end

using SparseArrays
import Base: deepcopy

struct PartiallyMutableArray{T, N, NON_MISSING_INDICES} <: AbstractArray{T, N}
    immutable_part::AbstractArray{T, N}
    mutable_part::Union{Nothing, SparseArrays.SparseMatrixCSC{T, N}}
    mutability_mask::BitArray{N}
end

deepcopy(A::PartiallyMutableArray) = PartiallyMutableArray(A.immutable_part, deepcopy(A.mutable_part), A.mutability_mask)

# deepcopy the data once before the compile might be very desirable: we want to guarantee that the data is not mutated
# we can deepcopy by default, but allow user to say no deepcopy

function PartiallyMutableArray(data_array::Array{Union{Missing, T}, N}) where {T, N}
    mutability_mask = BitArray{N}(map(x -> x isa Missing, data_array))
    # include the missing indices in the type parameter
    # make a sparse array with the missing indices,
    mutable_part = sparse(convert(Array{T, N}, mutability_mask))
    NON_MISSING_INDICES = Tuple(Tuple.(collect(eachindex(mutable_part))))
    return PartiallyMutableArray{T, N, NON_MISSING_INDICES}(data_array, mutable_part, mutability_mask)
end

function PartiallyMutableArray(data_array::Array{T, N}) where {T, N} # the array doesn't contain missing values
    mutability_mask = BitArray{N}(false, size(data_array))
    return PartiallyMutableArray(data_array, nothing, mutability_mask)
end
