function ref_to_getindex(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            return Expr(:call, :getindex, sub_expr.args...)
        else
            return sub_expr
        end
    end
end

function print_to_file(x::Dict, filename="output.jl")
    file_path = "/home/sunxd/JuliaBUGS.jl/notebooks/" * filename
    open(file_path, "w+") do f
        for (k, v) in trace
            println(f, k, " = ", v)
        end
    end
end

function test_BUGS_model_with_default_hmc(model_def, data, init)
    p = compile(model_def, data, init)
    initial_θ = JuliaBUGS.gen_init_params(p)

    D = LogDensityProblems.dimension(p)
    n_samples, n_adapts = 2000, 1000

    metric = AdvancedHMC.DiagEuclideanMetric(D)
    hamiltonian = AdvancedHMC.Hamiltonian(metric, p, :ReverseDiff)

    initial_ϵ = find_good_stepsize(hamiltonian, initial_θ)
    integrator = Leapfrog(initial_ϵ)
    proposal = NUTS{MultinomialTS, GeneralisedNoUTurn}(integrator)
    adaptor = StanHMCAdaptor(MassMatrixAdaptor(metric), StepSizeAdaptor(0.8, integrator))

    samples, stats = sample(hamiltonian, proposal, initial_θ, n_samples, adaptor, n_adapts; drop_warmup=true, progress=true);
    traces = [JuliaBUGS.transform_samples(p, sample) for sample in samples]
    open("/home/sunxd/JuliaBUGS.jl/notebooks/output.jl", "w+") do f
        for k in p.parameters
            k_samples = [trace[k] for trace in traces]
            m = mean(k_samples)
            s = std(k_samples)
            println(f, k, " = ", m, " ± ", s)
        end
    end
end

function test_BUGS_model_with_default_mh(model_def, data, init)    
    p = compile(model_def, data, init)
    initial_θ = JuliaBUGS.gen_init_params(p)

    D = LogDensityProblems.dimension(p)
    spl = RWMH(MvNormal(zeros(D), I))
    samples = sample(p, spl, 100000);

    traces = [JuliaBUGS.transform_samples(p, sample.params) for sample in samples]
    open("/home/sunxd/JuliaBUGS.jl/notebooks/output.jl", "w+") do f
        for k in p.parameters
            k_samples = [trace[k] for trace in traces]
            m = mean(k_samples)
            s = std(k_samples)
            println(f, k, " = ", m, " ± ", s)
        end
    end
end
