#!/usr/bin/env julia
import Pkg
try
    using CSV, DataFrames, Printf
catch
    Pkg.activate(joinpath(@__DIR__, ".."))
    Pkg.instantiate()
    Pkg.add(["CSV","DataFrames"])
    using CSV, DataFrames, Printf
end

const ROOT = normpath(@__DIR__, "..")
const RES  = joinpath(ROOT, "results")
const TAB  = joinpath(ROOT, "tables")
isdir(TAB) || mkpath(TAB)

function read_csv(path::String, header::Vector{String})
    @assert isfile(path) "Missing $(path)"
    return DataFrame(CSV.File(path; comment = "#", header = header))
end

function fmt(x; p::Int=12)
    if x == 0.0
        return @sprintf("%.0e", x)
    else
        return @sprintf("%.3e", x)
    end
end

function write_table_rows(path::String, rows::Vector{Vector{String}})
    open(path, "w") do io
        for r in rows
            println(io, join(r, " & "), " \\\")
        end
    end
end

# HMM correctness rows
begin
    df = read_csv(joinpath(RES, "hmm_correctness_sweep.csv"), ["seed","K","T","logp_autmarg","logp_forward","diff"]) 
    sort!(df, [:K, :T])
    rows = Vector{Vector{String}}()
    for r in eachrow(df)
        push!(rows, [string(r.seed), string(r.K), string(r.T), @sprintf("%.12f", r.logp_autmarg), @sprintf("%.12f", r.logp_forward), @sprintf("%.3e", r.diff)])
    end
    write_table_rows(joinpath(TAB, "hmm_correctness_rows.tex"), rows)
end

# GMM correctness rows
begin
    df = read_csv(joinpath(RES, "gmm_correctness_sweep.csv"), ["seed","K","N","logp_autmarg","logp_closed_form","diff"]) 
    sort!(df, [:K, :N])
    rows = Vector{Vector{String}}()
    for r in eachrow(df)
        push!(rows, [string(r.seed), string(r.K), string(r.N), @sprintf("%.12f", r.logp_autmarg), @sprintf("%.12f", r.logp_closed_form), @sprintf("%.3e", r.diff)])
    end
    write_table_rows(joinpath(TAB, "gmm_correctness_rows.tex"), rows)
end

# HDP-HMM correctness rows
begin
    df = read_csv(joinpath(RES, "hdphmm_correctness_fixed.csv"), ["seed","K","T","alpha","gamma","logp_autmarg","logp_forward","diff"]) 
    sort!(df, [:K, :T])
    rows = Vector{Vector{String}}()
    for r in eachrow(df)
        push!(rows, [string(r.seed), string(r.K), string(r.T), @sprintf("%.3f", r.alpha), @sprintf("%.3f", r.gamma), @sprintf("%.12f", r.logp_autmarg), @sprintf("%.12f", r.logp_forward), @sprintf("%.3e", r.diff)])
    end
    write_table_rows(joinpath(TAB, "hdphmm_correctness_rows.tex"), rows)
end

# Gradient table rows (merge key stats from sweeps)
begin
    rows = Vector{Vector{String}}()
    # HMM gradient sweep
    dfh = read_csv(joinpath(RES, "hmm_gradient_sweep.csv"), ["seed","K","T","max_abs_diff","max_rel_diff","logp"]) 
    # choose representative entries (all of them, but compact configs)
    sort!(dfh, [:K, :T])
    for r in eachrow(dfh)
        push!(rows, ["HMM", @sprintf("K=%d,T=%d", r.K, r.T), @sprintf("%.3e", r.max_abs_diff), @sprintf("%.3e", r.max_rel_diff)])
    end
    # GMM gradient sweep
    dfg = read_csv(joinpath(RES, "gmm_gradient_sweep.csv"), ["seed","K","N","max_abs_diff","max_rel_diff","logp"]) 
    sort!(dfg, [:K, :N])
    for r in eachrow(dfg)
        push!(rows, ["GMM", @sprintf("K=%d,N=%d", r.K, r.N), @sprintf("%.3e", r.max_abs_diff), @sprintf("%.3e", r.max_rel_diff)])
    end
    # HDP-HMM gradient sweep (kappa=0)
    df0 = read_csv(joinpath(RES, "hdphmm_gradient_sweep_kappa0.csv"), ["seed","K","T","max_abs_diff","max_rel_diff","logp"]) 
    sort!(df0, [:K, :T])
    for r in eachrow(df0)
        push!(rows, ["HDP-HMM (κ=0)", @sprintf("K=%d,T=%d", r.K, r.T), @sprintf("%.3e", r.max_abs_diff), @sprintf("%.3e", r.max_rel_diff)])
    end
    # HDP-HMM gradient sweep (kappa=5)
    df5 = read_csv(joinpath(RES, "hdphmm_gradient_sweep_kappa5.csv"), ["seed","K","T","max_abs_diff","max_rel_diff","logp"]) 
    sort!(df5, [:K, :T])
    for r in eachrow(df5)
        push!(rows, ["HDP-HMM (κ=5)", @sprintf("K=%d,T=%d", r.K, r.T), @sprintf("%.3e", r.max_abs_diff), @sprintf("%.3e", r.max_rel_diff)])
    end
    write_table_rows(joinpath(TAB, "gradient_rows.tex"), rows)
end

println("Tables written to ", TAB)
