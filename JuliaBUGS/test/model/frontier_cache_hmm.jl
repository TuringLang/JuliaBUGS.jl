using Test
using JuliaBUGS
using JuliaBUGS: @bugs, compile, @varname
using JuliaBUGS.Model:
    _precompute_minimal_cache_keys, _marginalize_recursive, smart_copy_evaluation_env

@testset "Frontier cache for HMM under different orders" begin
    # Simple HMM with fixed emission parameters (no continuous params)
    hmm_def = @bugs begin
        mu[1] = 0.0
        mu[2] = 5.0
        sigma = 1.0

        trans[1, 1] = 0.7
        trans[1, 2] = 0.3
        trans[2, 1] = 0.4
        trans[2, 2] = 0.6

        pi[1] = 0.5
        pi[2] = 0.5

        z[1] ~ Categorical(pi[1:2])
        for t in 2:T
            p[t, 1] = trans[z[t - 1], 1]
            p[t, 2] = trans[z[t - 1], 2]
            z[t] ~ Categorical(p[t, :])
        end

        for t in 1:T
            y[t] ~ Normal(mu[z[t]], sigma)
        end
    end

    T = 3
    data = (T=T, y=[0.1, 4.9, 5.1])
    model = compile(hmm_def, data)

    gd = model.graph_evaluation_data
    n = length(gd.sorted_nodes)

    # Helper: index lookup for variables of interest
    vn = Dict(
        :z1 => @varname(z[1]),
        :z2 => @varname(z[2]),
        :z3 => @varname(z[3]),
        :y1 => @varname(y[1]),
        :y2 => @varname(y[2]),
        :y3 => @varname(y[3]),
    )
    idx = Dict{Symbol,Int}()
    for (k, v) in vn
        i = findfirst(==(v), gd.sorted_nodes)
        @test i !== nothing  # ensure nodes exist
        idx[k] = i
    end

    # Construct two evaluation orders as permutations of 1:n
    # Interleaved: z1, y1, z2, y2, z3, y3, then the rest
    priority_interleaved = [idx[:z1], idx[:y1], idx[:z2], idx[:y2], idx[:z3], idx[:y3]]
    rest_interleaved = [i for i in 1:n if i ∉ priority_interleaved]
    order_interleaved = vcat(priority_interleaved, rest_interleaved)

    # States-first: z1, z2, z3, y1, y2, y3, then the rest
    priority_states_first = [idx[:z1], idx[:z2], idx[:z3], idx[:y1], idx[:y2], idx[:y3]]
    rest_states_first = [i for i in 1:n if i ∉ priority_states_first]
    order_states_first = vcat(priority_states_first, rest_states_first)

    # Precompute minimal keys for both orders
    keys_interleaved = _precompute_minimal_cache_keys(model, order_interleaved)
    keys_states_first = _precompute_minimal_cache_keys(model, order_states_first)

    # Helper to map frontier indices back to a set of variable symbols we care about
    function frontier_syms(keys, key_idx)
        frontier = get(keys, key_idx, Int[])
        syms = Set{Symbol}()
        for (name, i) in idx
            if i in frontier
                push!(syms, name)
            end
        end
        return syms
    end

    # Interleaved expectations: frontier size stays 1; y[t] depends on z[t]
    @test frontier_syms(keys_interleaved, idx[:z1]) == Set{Symbol}()
    @test frontier_syms(keys_interleaved, idx[:y1]) == Set([:z1])
    @test frontier_syms(keys_interleaved, idx[:z2]) == Set([:z1])
    @test frontier_syms(keys_interleaved, idx[:y2]) == Set([:z2])
    @test frontier_syms(keys_interleaved, idx[:z3]) == Set([:z2])
    @test frontier_syms(keys_interleaved, idx[:y3]) == Set([:z3])

    # States-first expectations: frontier grows across z's, peaks at y1
    @test frontier_syms(keys_states_first, idx[:z1]) == Set{Symbol}()
    @test frontier_syms(keys_states_first, idx[:z2]) == Set([:z1])
    @test frontier_syms(keys_states_first, idx[:z3]) == Set([:z1, :z2])
    @test frontier_syms(keys_states_first, idx[:y1]) == Set([:z1, :z2, :z3])
    @test frontier_syms(keys_states_first, idx[:y2]) == Set([:z2, :z3])
    @test frontier_syms(keys_states_first, idx[:y3]) == Set([:z3])

    # Sanity: different orders should not change marginalized log-density
    env = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    params = Float64[]
    # New marginalization uses parameter offsets/lengths and 3-tuple memo keys
    param_offsets = Dict{VarName,Int}()
    var_lengths = Dict{VarName,Int}()
    memo1 = Dict{Tuple{Int,Tuple,Tuple},Any}()

    logp1 = Base.invokelatest(
        _marginalize_recursive,
        model,
        env,
        order_interleaved,
        params,
        param_offsets,
        var_lengths,
        memo1,
        keys_interleaved,
    )

    env2 = smart_copy_evaluation_env(model.evaluation_env, model.mutable_symbols)
    memo2 = Dict{Tuple{Int,Tuple,Tuple},Any}()

    logp2 = Base.invokelatest(
        _marginalize_recursive,
        model,
        env2,
        order_states_first,
        params,
        param_offsets,
        var_lengths,
        memo2,
        keys_states_first,
    )

    # Check both prior and likelihood
    @test isapprox(logp1[1], logp2[1]; atol=1e-10)
    @test isapprox(logp1[2], logp2[2]; atol=1e-10)

    # And states-first should lead to equal or larger memo usage (worse frontier)
    @test length(memo2) >= length(memo1)
end
