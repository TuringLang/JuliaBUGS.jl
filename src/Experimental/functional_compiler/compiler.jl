using MacroTools
using SymbolicUtils
using Metatheory
using SymbolicPPL: @bugsast, transform_expr
using SymbolicPPL: BUGSExamples
##

m = BUGSExamples.EXAMPLES[:dogs]
expr = transform_expr(m[:model_def])
## 

"""
    rename_loopvars(expr)

Return an expression with all loop variables renamed to unique names.
"""
function rename_loopsvars(ex)
    bounds = Dict{Symbol,Any}()
    expr = deepcopy(ex)
    rec_rename_loopvars!(expr, bounds)
    return expr, bounds
end

function rec_rename_loopvars!(ex, bounds)
    for arg in ex.args
        if Meta.isexpr(arg, :for)
            loopvar = arg.args[1].args[1]
            body = arg.args[2]
            new_loopvar = gensym(loopvar)
            bounds[new_loopvar] = (arg.args[1].args[2].args[1], arg.args[1].args[2].args[2])
            arg.args[1].args[1] = new_loopvar
            arg.args[2] = MacroTools.postwalk(body) do sub_expr
                if sub_expr == loopvar
                    sub_expr = new_loopvar
                end
                return sub_expr
            end
            rec_rename_loopvars!(arg.args[2], bounds)
        end
    end
end

# separate every expressions in a loop to its own loop
function separate_loops(expr)
    new_args = []
    for (i, arg) in enumerate(expr.args)
        if Meta.isexpr(arg, :for)
            push!(
                new_args,
                map(x -> Expr(:for, arg.args[1], x), separate_loops(arg.args[2]))...,
            )
        else
            push!(new_args, arg)
        end
    end
    return new_args
end

function squash_loops(ex)
    expr = deepcopy(ex)
    for (i, arg) in enumerate(expr.args)
        if Meta.isexpr(arg, :for)
            splice!(expr.args, i, arg.args[2].args)
        end
    end
    return expr
end

""" 
    find_indices(expr)

Return the mapping from array variable to a list of Sets, and each Set contains all the 
possible index expressions for the dimension. 
"""
function find_indices(expr)
    I = Dict{Symbol,Vector{Set{Any}}}()

    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_[is__])
            if !haskey(I, a)
                I[a] = Vector{Vector{Any}}(undef, length(is))
                for i in 1:length(is)
                    I[a][i] = Set{Any}()
                end
            end
            for (i, index) in enumerate(is)
                if index isa Real
                    isinteger(index) ||
                        error("Index $index of $sub_expr needs to be integers.")
                    push!(I[a][i], index)
                elseif Meta.isexpr(index, :call) && index.args[1] == :(:)
                    push!(I[a][i], index.args[2:end]...)
                elseif index isa Union{Symbol,Expr} && index != :(:)
                    push!(I[a][i], index)
                end
            end
        end
        return sub_expr
    end

    return I
    # # collect all the sets in lists
    # II = Dict{Symbol, Vector{Vector{Any}}}()
    # for a in keys(I)
    #     II[a] = Vector{Vector{Any}}(undef, length(I[a]))
    #     for i in 1:length(I[a])
    #         II[a][i] = collect(I[a][i])
    #     end
    # end
    # return II
end

function find_variables(expr)
    vars = Set{Symbol}()
    MacroTools.postwalk(expr) do sub_expr
        if sub_expr isa Symbol
            push!(vars, sub_expr)
        end
        return sub_expr
    end
    return vars
end

function find_func(expr)
    funcs = Set{Symbol}()
    MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :call)
            push!(funcs, sub_expr.args[1])
        end
        return sub_expr
    end
    return funcs
end

function find_arrays(expr)
    arrays = Set{Symbol}()
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_[is__])
            push!(arrays, a)
        end
        return sub_expr
    end
    return arrays
end

function quote_other_vars(expr, vv)
    MacroTools.postwalk(expr) do sub_expr
        if sub_expr isa Symbol && sub_expr ∈ vv
            sub_expr = QuoteNode(sub_expr)
        end
        return sub_expr
    end
end

function ref_to_getindex(expr)
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_[is__])
            sub_expr = Expr(:call, :getindex, a, is...)
        end
        return sub_expr
    end
end

function getindex_to_ref(expr)
    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, getindex(a_, is__))
            sub_expr = Expr(:ref, a, is...)
        end
        return sub_expr
    end
end

function parse_logical_assignments(expr)
    L = Dict{Any,Any}()

    MacroTools.postwalk(expr) do sub_expr
        if MacroTools.@capture(sub_expr, a_ = b_) && !Meta.isexpr(b, :(:))
            L[a] = b
        end
        return sub_expr
    end

    return L
end

function parse_stochastic_assignments(expr)
    S = Dict{Any,Any}()

    MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :(~))
            S[sub_expr.args[1]] = sub_expr.args[2]
        end
        return sub_expr
    end

    return S
end

function create_rw(expr)
    e, bounds = rename_loopsvars(expr)
    e = squash_loops(e)
    I = find_indices(e)

    loopvars = collect(keys(bounds))

    v = find_variables(e)
    f = find_func(e)
    a = find_arrays(e)
    is = keys(bounds)
    vv = setdiff(v, f ∪ is)

    L = parse_logical_assignments(e)

    LL = Dict()
    Ll = Dict() # logical assignments lhs is a symbol
    for l in keys(L)
        if !isa(l, Symbol)
            LL[l] = L[l]
        else
            Ll[l] = L[l]
        end
    end
    NL = Dict()
    replace_e(expr, s, t) = MacroTools.prewalk(e -> e == s ? t : e, expr)
    for (l, r) in LL
        for (ll, rr) in Ll
            l = ref_to_getindex(quote_other_vars(replace_e(l, ll, rr), vv))
            r = ref_to_getindex(quote_other_vars(replace_e(r, ll, rr), vv))
        end
        NL[l] = r
    end
    ##

    P = []
    slots = loopvars
    for (l, r) in NL
        push!(
            P,
            Metatheory.RewriteRule(
                Expr(:(-->), l, r),
                eval(Metatheory.Syntax.makepattern(l, [], loopvars, @__MODULE__)),
                eval(Metatheory.Syntax.makepattern(r, [], loopvars, @__MODULE__)),
            ),
        )
    end
    sort!(P; by=x -> string(x))

    rw = Metatheory.PassThrough(
        Metatheory.Fixpoint(Metatheory.Postwalk(Metatheory.Chain(P)))
    )
    return rw, P
end

function ceval(e, data)
    for (k, v) in data
        @eval $k = $v
    end

    @show eval(e)
end
