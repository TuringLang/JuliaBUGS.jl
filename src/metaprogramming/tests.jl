using JuliaBUGS
using JuliaBUGS.BUGSExamples: rats, leuk
using JuliaBUGS: generate_analysis_function

using JuliaBUGS: DetermineArraySizes, CheckMultipleAssignments, ComputeTransformed, CountFreeVars

model_def = deepcopy(leuk.model_def)
data = leuk.data;
##

f_expr = generate_analysis_function(DetermineArraySizes(), model_def)
eval(f_expr)
all_vars, array_sizes = __determine_array_sizes(data)

f_expr = generate_analysis_function(CheckMultipleAssignments(), model_def)
eval(f_expr)
potential_conflict = __check_multiple_assignments(data, array_sizes)

eval_env = JuliaBUGS.create_evaluate_env(all_vars, data, array_sizes)

f_expr = JuliaBUGS.generate_analysis_function(ComputeTransformed(), model_def)
eval(f_expr)
eval_env = __compute_transformed!(eval_env)

JuliaBUGS.check_conflicts(eval_env, potential_conflict...)

eval_env = JuliaBUGS.concretize_eval_env_value_types(eval_env)

f_expr = generate_analysis_function(CountFreeVars(), model_def)
eval(f_expr)
num_deterministic_vars, num_stochastic_vars = __count_free_vars(eval_env)

###################

quote
    for i = 1:N
        for j = 1:T
            Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
            dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
        end
    end
    for j = 1:T
        for i = 1:N
            dN[i, j] ~ dpois(Idt[i, j])
            Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
        end
        dL0[j] ~ dgamma(mu[j], c)
        mu[j] = var"dL0.star"[j] * c
        var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
        var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
    end
    c = 0.001
    r = 0.1
    for j = 1:T
        var"dL0.star"[j] = r * (t[j + 1] - t[j])
    end
    beta ~ dnorm(0.0, 1.0e-6)
end

function __determine_array_sizes(var"##data#227"::NamedTuple{var"##KEYS#236", var"##VALUE_TYPES#237"}) where {var"##KEYS#236", var"##VALUE_TYPES#237"}
    map((:N, :T)) do x
        if x ∉ var"##KEYS#236"
            error("Variable `$(x)` is used in loop bounds or for indexing, but not provided by data.")
        end
    end
    (; N, T) = var"##data#227"
    var"##array_var_names#239" = (:Y, Symbol("obs.t"), :t, :dN, :fail, :Idt, :Z, :dL0, :mu, Symbol("dL0.star"), Symbol("S.treat"), Symbol("S.placebo"))
    var"##array_sizes#240" = let _MVec = JuliaBUGS.StaticArrays.MVector
            NamedTuple{var"##array_var_names#239"}((_MVec{2}([1, 1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{2}([1, 1]), _MVec{1}([1]), _MVec{2}([1, 1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1]), _MVec{1}([1])))
        end
    for v = intersect(var"##array_var_names#239", var"##KEYS#236")
        var"##array_sizes#240"[v] .= size(data[v])
    end
    for i = 1:N
        for j = 1:T
            JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :Y, i, j)
            JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :dN, i, j)
        end
    end
    for j = 1:T
        for i = 1:N
            JuliaBUGS.determine_array_sizes_stochastic!(data, var"##array_sizes#240", :dN, i, j)
            JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :Idt, i, j)
        end
        JuliaBUGS.determine_array_sizes_stochastic!(data, var"##array_sizes#240", :dL0, j)
        JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :mu, j)
        JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", Symbol("S.treat"), j)
        JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", Symbol("S.placebo"), j)
    end
    JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :c)
    JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", :r)
    for j = 1:T
        JuliaBUGS.determine_array_sizes_logical!(data, var"##array_sizes#240", Symbol("dL0.star"), j)
    end
    return ((:N, :T, :Y, Symbol("obs.t"), :eps, :t, :dN, :fail, :Idt, :Z, :beta, :dL0, :mu, :c, Symbol("dL0.star"), Symbol("S.treat"), Symbol("S.placebo"), :r), NamedTuple{keys(var"##array_sizes#240")}(Tuple.(values(var"##array_sizes#240"))))
end

function __compute_transformed!(var"##evaluate_env#236"::NamedTuple{var"##ALL_VARS#237"}) where var"##ALL_VARS#237"
    (; N, T, Y, var"obs.t", eps, t, dN, fail, Idt, Z, beta, dL0, mu, c, var"dL0.star", var"S.treat", var"S.placebo", r) = var"##evaluate_env#236"
    var"##added_new_val#238" = true
    while var"##added_new_val#238"
        var"##added_new_val#238" = false
        for i = 1:N
            for j = 1:T
                JuliaBUGS.@try_compute Y[i, j] = _step((var"obs.t"[i] - t[j]) + eps)
                JuliaBUGS.@try_compute dN[i, j] = Y[i, j] * _step((t[j + 1] - var"obs.t"[i]) - eps) * fail[i]
            end
        end
        for j = 1:T
            for i = 1:N
                JuliaBUGS.@try_compute Idt[i, j] = Y[i, j] * exp(beta * Z[i]) * dL0[j]
            end
            JuliaBUGS.@try_compute mu[j] = var"dL0.star"[j] * c
            JuliaBUGS.@try_compute var"S.treat"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * -0.5))
            JuliaBUGS.@try_compute var"S.placebo"[j] = pow(exp(-(sum(dL0[1:j]))), exp(beta * 0.5))
        end
        JuliaBUGS.@try_compute c = 0.001
        JuliaBUGS.@try_compute r = 0.1
        for j = 1:T
            JuliaBUGS.@try_compute var"dL0.star"[j] = r * (t[j + 1] - t[j])
        end
    end
    return NamedTuple{(:N, :T, :Y, Symbol("obs.t"), :eps, :t, :dN, :fail, :Idt, :Z, :beta, :dL0, :mu, :c, Symbol("dL0.star"), Symbol("S.treat"), Symbol("S.placebo"), :r)}((N, T, Y, var"obs.t", eps, t, dN, fail, Idt, Z, beta, dL0, mu, c, var"dL0.star", var"S.treat", var"S.placebo", r))
end

