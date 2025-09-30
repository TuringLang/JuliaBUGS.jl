#!/usr/bin/env julia

import Pkg
try
    using CSV, DataFrames, Plots, LaTeXStrings, Statistics, Printf
catch e
    Pkg.activate(joinpath(@__DIR__, ".."))
    Pkg.instantiate()
    Pkg.add(["CSV","DataFrames","Plots","LaTeXStrings"])
    using CSV, DataFrames, Plots, LaTeXStrings, Statistics, Printf
end

# Ensure headless GR backend
ENV["GKSwstype"] = "100"

const ROOT = normpath(@__DIR__, "..")
const RES = joinpath(ROOT, "results")
const FIG = joinpath(ROOT, "figures")
isdir(FIG) || mkpath(FIG)

function read_hmm_norm()
    path = joinpath(RES, "hmm_scaling_sweep_norm.csv")
    @assert isfile(path) "Missing $(path). Run hmm_scaling_bench.jl first."
    header = [
        "seed","K","T","trials","min_time_sec","logp",
        "max_frontier","mean_frontier","sum_frontier","time_over_TK2"
    ]
    df = DataFrame(CSV.File(path; comment = "#", header = header))
    # Ensure numeric types
    df.K = Int.(df.K)
    df.T = Int.(df.T)
    return df
end

function plot_hmm_scaling()
    df = read_hmm_norm()
    # Figure 1: min_time vs T for each K
    ks = sort(unique(df.K))
    plt1 = plot(; xlabel = "T", ylabel = "min time (s)", title = "HMM scaling: time vs T (interleaved)", legend = :topleft)
    for k in ks
        d = sort(df[df.K .== k, :], :T)
        plot!(plt1, d.T, d.min_time_sec; lw = 2, marker = :circle, label = "K=$(k)")
    end
    savefig(plt1, joinpath(FIG, "hmm_scaling_time_vs_T.pdf"))

    # Figure 2: normalized time_over_TK2 vs T for each K
    plt2 = plot(; xlabel = "T", ylabel = L"time/(T K^2)", title = "HMM normalized time vs T", legend = :topright)
    for k in ks
        d = sort(df[df.K .== k, :], :T)
        plot!(plt2, d.T, d.time_over_TK2; lw = 2, marker = :rect, label = "K=$(k)")
    end
    savefig(plt2, joinpath(FIG, "hmm_scaling_norm_vs_T.pdf"))

    # Figure 3: normalized time_over_TK2 vs K for selected T
    Ts = intersect(sort(unique(df.T)), [50,100,200,400,800])
    plt3 = plot(; xlabel = "K", xscale = :log10, yscale = :log10, ylabel = L"time/(T K^2)", title = "HMM normalized vs K", legend = :bottomleft)
    for T in Ts
        d = sort(df[df.T .== T, :], :K)
        plot!(plt3, d.K, d.time_over_TK2; lw = 2, marker = :utriangle, label = "T=$(T)")
    end
    savefig(plt3, joinpath(FIG, "hmm_scaling_norm_vs_K.pdf"))
end

function parse_fhmm_frontier()
    path = joinpath(RES, "fhmm_orders_frontier.csv")
    @assert isfile(path) "Missing $(path). Run fhmm_order_comparison.jl first."
    rows = Vector{NamedTuple}()
    current_T = missing
    open(path, "r") do io
        for ln in eachline(io)
            if startswith(ln, "# FHMM order comparison")
                m = match(r"T=(\d+)", ln)
                current_T = isnothing(m) ? missing : parse(Int, m.captures[1])
            elseif isempty(strip(ln)) || startswith(ln, "#")
                continue
            else
                parts = split(ln, ",")
                order = parts[1]
                maxf = parse(Int, parts[2])
                meanf = parse(Float64, parts[3])
                sumf = parse(Int, parts[4])
                logproxy = parse(Float64, parts[5])
                tmin = lowercase(strip(parts[6])) == "na" ? missing : parse(Float64, parts[6])
                logp  = lowercase(strip(parts[7])) == "na" ? missing : parse(Float64, parts[7])
                push!(rows, (; T=current_T, order, max_frontier=maxf, mean_frontier=meanf, sum_frontier=sumf, logproxy, min_time=tmin, logp))
            end
        end
    end
    return DataFrame(rows)
end

function plot_fhmm()
    df = parse_fhmm_frontier()
    # Frontier vs T
    orders = ["interleaved", "states_then_y"]
    plt1 = plot(; xlabel = "T", ylabel = "max frontier", title = "FHMM: frontier vs T", legend = :topleft)
    for o in orders
        d = sort(df[df.order .== o, :], :T)
        plot!(plt1, d.T, d.max_frontier; lw = 2, marker = :circle, label = o)
    end
    savefig(plt1, joinpath(FIG, "fhmm_frontier_vs_T.pdf"))

    # Interleaved time vs T
    di = dropmissing(df[df.order .== "interleaved", :], :min_time)
    plt2 = plot(di.T, di.min_time; lw = 2, marker = :square, xlabel = "T", ylabel = "min time (s)", title = "FHMM: interleaved time vs T")
    savefig(plt2, joinpath(FIG, "fhmm_time_interleaved_vs_T.pdf"))

    # Proxy vs T (log scale)
    plt3 = plot(; xlabel = "T", ylabel = "log proxy", title = "FHMM: log Σ K^{width} vs T", legend = :topleft)
    for o in orders
        d = sort(df[df.order .== o, :], :T)
        plot!(plt3, d.T, d.logproxy; lw = 2, marker = :diamond, label = o)
    end
    savefig(plt3, joinpath(FIG, "fhmm_logproxy_vs_T.pdf"))
end

function parse_fhmm_c_sweep()
    path = joinpath(RES, "fhmm_c_sweep.csv")
    @assert isfile(path) "Missing $(path). Run FHMM C sweep first."
    rows = Vector{NamedTuple}()
    current = Dict{String,Int}()
    open(path, "r") do io
        for ln in eachline(io)
            if startswith(ln, "# FHMM order comparison")
                # parse C,K,T
                for kv in ("C","K","T")
                    m = match(Regex(kv * "=(\\d+)"), ln)
                    if m !== nothing
                        current[kv] = parse(Int, m.captures[1])
                    end
                end
            elseif isempty(strip(ln)) || startswith(ln, "#")
                continue
            else
                parts = split(ln, ",")
                order = parts[1]
                maxf = parse(Int, parts[2])
                meanf = parse(Float64, parts[3])
                sumf = parse(Int, parts[4])
                logproxy = parse(Float64, parts[5])
                tmin = lowercase(strip(parts[6])) == "na" ? missing : parse(Float64, parts[6])
                logp  = lowercase(strip(parts[7])) == "na" ? missing : parse(Float64, parts[7])
                push!(rows, (; C=current["C"], K=current["K"], T=current["T"], order, max_frontier=maxf, mean_frontier=meanf, sum_frontier=sumf, logproxy, min_time=tmin, logp))
            end
        end
    end
    return DataFrame(rows)
end

function plot_fhmm_c_sweep()
    df = parse_fhmm_c_sweep()
    di = dropmissing(df[df.order .== "interleaved", :], :min_time)
    plt1 = plot(di.C, di.min_time; lw=2, marker=:circle, xlabel="chains C", ylabel="min time (s)", title="FHMM interleaved: time vs C (K=4, T=100)")
    savefig(plt1, joinpath(FIG, "fhmm_c_time_vs_C.pdf"))
    plt2 = plot(di.C, di.logproxy; lw=2, marker=:diamond, xlabel="chains C", ylabel="log proxy", title="FHMM interleaved: log Σ K^{width} vs C")
    savefig(plt2, joinpath(FIG, "fhmm_c_logproxy_vs_C.pdf"))
end

function parse_hmt()
    f1 = joinpath(RES, "hmt_order_frontier.csv")
    f2 = joinpath(RES, "hmt_order_dfs_timed.csv")
    @assert isfile(f1) "Missing $(f1). Run hmt_order_comparison.jl first."
    header = ["order","B","K","depth","N","max_frontier","mean_frontier","sum_frontier","log_cost_proxy","min_time_sec","logp"]
    df_front = DataFrame(CSV.File(f1; comment = "#", missingstring = "NA", header = header))
    df_time  = DataFrame(CSV.File(f2; comment = "#", missingstring = "NA", header = header))
    # Ensure types
    for df in (df_front, df_time)
        df.max_frontier = Int.(df.max_frontier)
    end
    return df_front, df_time
end

function plot_hmt()
    df_front, df_time = parse_hmt()
    # Max frontier bars
    orders = ["dfs", "random_dfs", "bfs"]
    d = DataFrame(order = String[], maxf = Int[])
    for o in orders
        r = first(df_front[df_front.order .== o, :])
        push!(d, (order=o, maxf=r.max_frontier))
    end
    plt1 = bar(d.order, d.maxf; xlabel = "order", ylabel = "max frontier", title = "HMT: max frontier by order")
    savefig(plt1, joinpath(FIG, "hmt_frontier_bars.pdf"))

    # DFS timing (single bar)
    rdfs = first(dropmissing(df_time[df_time.order .== "dfs", :], :min_time_sec))
    plt2 = bar(["dfs"], [rdfs.min_time_sec]; xlabel = "order", ylabel = "min time (s)", title = "HMT: DFS timing")
    savefig(plt2, joinpath(FIG, "hmt_dfs_time.pdf"))
end

function parse_hmt_depth()
    f1 = joinpath(RES, "hmt_depth_frontier.csv")
    f2 = joinpath(RES, "hmt_depth_dfs.csv")
    @assert isfile(f1) && isfile(f2)
    # reuse generic readers
    header = ["order","B","K","depth","N","max_frontier","mean_frontier","sum_frontier","log_cost_proxy","min_time_sec","logp"]
    df_front = DataFrame(CSV.File(f1; comment="#", header=header, missingstring="NA"))
    df_time  = DataFrame(CSV.File(f2; comment="#", header=header, missingstring="NA"))
    return df_front, df_time
end

function plot_hmt_depth()
    df_front, df_time = parse_hmt_depth()
    # DFS timing vs depth
    ddfs = dropmissing(df_time[df_time.order .== "dfs", :], :min_time_sec)
    plt1 = plot(ddfs.depth, ddfs.min_time_sec; lw=2, marker=:square, xlabel="depth", ylabel="min time (s)", title="HMT DFS: time vs depth (B=2, K=4)")
    savefig(plt1, joinpath(FIG, "hmt_dfs_time_vs_depth.pdf"))
    # BFS frontier vs depth
    dbfs = df_front[df_front.order .== "bfs", :]
    plt2 = plot(dbfs.depth, dbfs.max_frontier; lw=2, marker=:utriangle, xlabel="depth", ylabel="max frontier", title="HMT BFS: max frontier vs depth")
    savefig(plt2, joinpath(FIG, "hmt_bfs_frontier_vs_depth.pdf"))
end

function plot_proxy_vs_time()
    # Collect (logproxy, time) across FHMM interleaved and HMT DFS
    df_f = parse_fhmm_frontier()
    df_hf = dropmissing(df_f[df_f.order .== "interleaved", :], :min_time)
    df_front, df_time = parse_hmt()
    df_hd = dropmissing(df_time[df_time.order .== "dfs", :], :min_time_sec)
    xs = Float64[]; ys = Float64[]; labs = String[]
    for r in eachrow(df_hd)
        push!(xs, r.log_cost_proxy)
        push!(ys, r.min_time_sec)
        push!(labs, "HMT-DFS")
    end
    for r in eachrow(df_hf)
        push!(xs, r.logproxy)
        push!(ys, r.min_time)
        push!(labs, "FHMM-interleaved")
    end
    # Fit linear relation on logs: log(time) ~ a + b * logproxy
    logx = xs
    logy = log.(ys)
    μx = mean(logx); μy = mean(logy)
    b = sum((logx .- μx) .* (logy .- μy)) / sum((logx .- μx).^2)
    a = μy - b*μx
    ŷ = a .+ b .* logx
    r2 = 1 - sum((logy .- ŷ).^2) / sum((logy .- μy).^2)
    # Scatter plot
    plt = plot(; xlabel = "log proxy", ylabel = "min time (s)", yscale = :log10,
        title = @sprintf("Runtime vs proxy (log R^2=%.3f)", r2), legend = :topleft)
    scatter!(plt, xs, ys; group = labs, markershape = [:circle :diamond], label = [:"HMT-DFS" :"FHMM-interleaved"])
    # Add fitted line across x-range
    xr = range(minimum(xs), maximum(xs); length=100)
    yr = exp.(a .+ b .* xr)
    plot!(plt, xr, yr; lw = 2, color = :black, label = "fit (log-log)")
    savefig(plt, joinpath(FIG, "runtime_vs_proxy.pdf"))
end

function main()
    plot_hmm_scaling()
    plot_fhmm()
    plot_fhmm_c_sweep()
    plot_hmt()
    plot_hmt_depth()
    plot_proxy_vs_time()
    println("Figures written to: ", FIG)
end

main()
