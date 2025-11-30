using Pkg
Pkg.develop(; path=joinpath(@__DIR__, ".."))

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
    return df
end

function _print_results_table(
    results::OrderedDict{Symbol,BenchmarkResult}; backend::Symbol=:text
)
    df = _create_results_dataframe(results)
    rename!(
        df, ["Model", "Parameters", "Density Time (µs)", "Density+Gradient Time (µs)"]
    )
    return pretty_table(df; backend=backend)
end
