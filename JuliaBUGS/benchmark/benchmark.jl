using Pkg
redirect_stdout(devnull) do
    Pkg.develop(; path=joinpath(@__DIR__, ".."))
end

using JuliaBUGS

using DifferentiationInterface
using Mooncake: Mooncake

using MetaGraphsNext
using BridgeStan
using StanLogDensityProblems
using LogDensityProblems
using LogDensityProblemsAD
using Chairmarks
using DataFrames
using OrderedCollections
using PrettyTables
using Printf

struct BenchmarkResult{T1,T2}
    backend::Symbol
    dim::Int
    density_time::T1
    density_and_gradient_time::T2
end

function Base.show(io::IO, x::BenchmarkResult{T1,T2}) where {T1,T2}
    median_density = Chairmarks.median(x.density_time).time
    median_grad = Chairmarks.median(x.density_and_gradient_time).time

    # Each is in seconds, so multiply by 1e6 for microseconds if desired:
    density_microseconds = median_density * 1e6
    grad_microseconds = median_grad * 1e6

    return print(
        io,
        "BenchmarkResult for a model of dimension ",
        x.dim,
        " using ",
        x.backend,
        ". The median density evaluation time is ",
        Printf.@sprintf("%.2f", density_microseconds),
        " microseconds. The median density+gradient evaluation time is ",
        Printf.@sprintf("%.2f", grad_microseconds),
        " microseconds.",
    )
end

function extract_median_time(result::BenchmarkResult)
    return (
        Chairmarks.median(result.density_time).time * 1e6,
        Chairmarks.median(result.density_and_gradient_time).time * 1e6,
    )
end

function extract_median_time(results::OrderedDict{Symbol,BenchmarkResult})
    result_dict = OrderedDict{Symbol,Tuple{Float64,Float64}}()
    for (model_name, result) in results
        result_dict[model_name] = extract_median_time(result)
    end
    return result_dict
end

include("stan.jl")
include("juliabugs.jl")

function _create_results_dataframe(results::OrderedDict{Symbol,BenchmarkResult})
    df = DataFrame(;
        Model=Symbol[],
        Parameters=Int[],
        Density_Time=Float64[],
        Density_Gradient_Time=Float64[],
    )
    for (model_name, result) in results
        (density_time, density_gradient_time) = extract_median_time(result)
        push!(
            df,
            (
                model_name,
                Int(result.dim),
                Float64(density_time),
                Float64(density_gradient_time),
            ),
        )
    end
    DataFrames.rename!(
        df,
        :Density_Time => "Density Time (µs)",
        :Density_Gradient_Time => "Density+Gradient Time (µs)",
    )
    return df
end

function _print_results_table(
    results::OrderedDict{Symbol,BenchmarkResult}; backend::Symbol=:text
)
    df = _create_results_dataframe(results)
    rename!(df, ["Model", "Parameters", "Density Time (µs)", "Density+Gradient Time (µs)"])
    return pretty_table(df; backend=backend)
end

function _print_comparison_table(
    stan_results::OrderedDict{Symbol,BenchmarkResult},
    juliabugs_results::OrderedDict{Symbol,BenchmarkResult};
    backend::Symbol=:text,
)
    df = DataFrame(;
        Model=Symbol[],
        Params=Int[],
        Stan_LD=String[],
        JuliaBUGS_LD=String[],
        Ratio_LD=String[],
        Stan_Grad=String[],
        JuliaBUGS_Grad=String[],
        Ratio_Grad=String[],
    )

    for model_name in keys(stan_results)
        stan = stan_results[model_name]
        jbugs = juliabugs_results[model_name]

        stan_ld, stan_grad = extract_median_time(stan)
        jbugs_ld, jbugs_grad = extract_median_time(jbugs)

        ratio_ld = jbugs_ld / stan_ld
        ratio_grad = jbugs_grad / stan_grad

        push!(
            df,
            (
                model_name,
                Int(stan.dim),
                @sprintf("%.1f", stan_ld),
                @sprintf("%.1f", jbugs_ld),
                @sprintf("%.2fx", ratio_ld),
                @sprintf("%.1f", stan_grad),
                @sprintf("%.1f", jbugs_grad),
                @sprintf("%.2fx", ratio_grad),
            ),
        )
    end

    rename!(
        df,
        ["Model", "Params", "Stan LD", "JBUGS LD", "Ratio", "Stan ∇", "JBUGS ∇", "Ratio"],
    )
    return pretty_table(df; backend=backend, alignment=[:l, :r, :r, :r, :r, :r, :r, :r])
end

function _output_results_csv(
    stan_results::OrderedDict{Symbol,BenchmarkResult},
    juliabugs_results::OrderedDict{Symbol,BenchmarkResult},
)
    println("model,params,stan_ld,jbugs_ld,stan_grad,jbugs_grad")
    for model_name in keys(stan_results)
        stan = stan_results[model_name]
        jbugs = juliabugs_results[model_name]
        stan_ld, stan_grad = extract_median_time(stan)
        jbugs_ld, jbugs_grad = extract_median_time(jbugs)
        println("$model_name,$(stan.dim),$stan_ld,$jbugs_ld,$stan_grad,$jbugs_grad")
    end
end
