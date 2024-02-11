using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using MacroTools
using JuliaBUGS:
    extract_variable_names,
    extract_array_ndims,
    extract_variables_used_in_bounds_and_indices,
    gen_func_body,
    gen_func,
    gen_main_body

model_def = deepcopy(leuk.model_def)
data = leuk.data;
## 

gen_func(model_def)

JuliaBUGS.if_partially_specified_as_data((; a=[1, 2, missing]), :a, 2:3)

JuliaBUGS.determine_array_sizes_logical(data, :a)

expr = @bugs begin
    a[1, N + 1] = 3
end

gen_func_body(model_def)

gen_main_body(model_def)
gen_main_body(expr)

function f(s::Symbol, t::Int)
    return println(s, t)
end

b = :a
eval(:(f(Meta.quot(b), 3)))
:(f($(Meta.quot(b)), 3))

macro _bugs(expr::Expr)
    # TODO: deal with linenum later: particularly for this function, the source locations are actually kind of important, beacause some of the indices may error
    expr = MacroTools.postwalk(MacroTools.rmlines, expr)
    # for now, assume expr is legal BUGS program
    return esc(gen_func(expr))
end

@macroexpand @_bugs begin
    # Set up data
    for i in 1:N
        for j in 1:T
            # risk set = 1 if obs.t >= t
            Y[i, j] = step(var"obs.t"[i] - t[j] + eps)
            # counting process jump = 1 if obs.t in [ t[j], t[j+1] )
            # i.e. if t[j] <= obs.t < t[j+1]
            dN[i, j] = Y[i, j] * step(t[j + 1] - var"obs.t"[i] - eps) * fail[i]
        end
    end
    # Model
    for j in 1:T
        for i in 1:N
            dN[i, j] ~ dpois(Idt[i, j]) # Likelihood
            Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]    # Intensity
        end
        dL0[j] ~ dgamma(mu[j], c)
        mu[j] = var"dL0.star"[j] * c # prior mean hazard

        # Survivor function = exp(-Integral{l0(u)du})^exp(beta*z)
        var"S.treat"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * -0.5))
        var"S.placebo"[j] = pow(exp(-sum(dL0[1:j])), exp(beta * 0.5))
    end
    c = 0.001
    r = 0.1
    for j in 1:T
        var"dL0.star"[j] = r * (t[j + 1] - t[j])
    end
    beta ~ dnorm(0.0, 0.000001)
end
@benchmark __determine_array_sizes(data)

function __determine_array_sizes(data::NamedTuple{names, types}) where {names, types}
    (; N, T) = data
    array_names = (:Y, Symbol("obs.t"), :t, :dN, :fail, :Idt, :Z, :dL0, :mu, Symbol("dL0.star"), Symbol("S.treat"), Symbol("S.placebo"))
    array_sizes = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{array_names}((_MVec{2}([1, 1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{2}([1, 1]), _MVec{1}([1]), _MVec{2}([1, 1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1])))
        end
    for v = intersect(array_names, names)
        array_sizes[v] .= size(data[v])
    end
    for i = 1:N
        for j = 1:T
            JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :Y, i, j)
            JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :dN, i, j)
        end
    end
    for j = 1:T
        for i = 1:N
            JuliaBUGS.determine_array_sizes_stochastic!(data, array_sizes, :dN, i, j)
            JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :Idt, i, j)
        end
        JuliaBUGS.determine_array_sizes_stochastic!(data, array_sizes, :dL0, j)
        JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :mu, j)
        JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, Symbol("S.treat"), j)
        JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, Symbol("S.placebo"), j)
    end
    JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :c)
    JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, :r)
    for j = 1:T
        JuliaBUGS.determine_array_sizes_logical!(data, array_sizes, Symbol("dL0.star"), j)
    end
    return array_sizes
end

@benchmark begin
    stmts = SemanticAnalysis.Statements(model_def, data)
    array_sizes = SemanticAnalysis.determine_array_sizes(stmts, data)
end
