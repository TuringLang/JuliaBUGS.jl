# This server is designed to be a generic executor.
# It creates a temporary, sandboxed Julia environment for each request,

using HTTP
using JSON3
using Logging

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "Content-Type",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS",
]

function cors_handler(handler)
    return function(req::HTTP.Request)
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, CORS_HEADERS)
        else
            response = handler(req)
            append!(response.headers, CORS_HEADERS)
            return response
        end
    end
end

function health_check_handler(req::HTTP.Request)
    @info "Health check ping (backend reachable)"
    return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(Dict("status" => "ok")))
end


function run_model_handler(req::HTTP.Request)
    logs = String[]
    log!(logs, "Received /api/run request")
    log!(logs, "Backend processing started.")
    
    tmp_dir = mktempdir()
    log!(logs, "Created temporary working directory at: $(tmp_dir)")

    try
        body = JSON3.read(String(req.body))
        model_code = get(body, :model_code, "")
        data_json = haskey(body, :data) ? body[:data] : JSON3.Object()
        inits_json = haskey(body, :inits) ? body[:inits] : JSON3.Object()
        data_string = get(body, :data_string, "")
        inits_string = get(body, :inits_string, "")
        settings = get(body, :settings, JSON3.Object())

        log!(logs, "Request body parsed successfully.")

        model_path = joinpath(tmp_dir, "model.bugs")
        write(model_path, model_code)
        log!(logs, "Wrote BUGS model to: $(model_path)")

        model_literal = repr(String(model_code))

        results_path = joinpath(tmp_dir, "results.json")
        payload_path = joinpath(tmp_dir, "payload.json")
        payload_literal = repr(String(payload_path))
        results_literal = repr(String(results_path))

        payload_obj = Dict(
            "model_path" => model_path,
            "data" => data_json,
            "inits" => inits_json,
            "data_string" => data_string,
            "inits_string" => inits_string,
            "settings" => Dict(
                "n_samples" => get(settings, :n_samples, 1000),
                "n_adapts" => get(settings, :n_adapts, 1000),
                "n_chains" => get(settings, :n_chains, 1),
                "seed" => get(settings, :seed, nothing),
            ),
        )
        open(payload_path, "w") do f
            JSON3.write(f, payload_obj)
        end
        log!(logs, "Wrote payload to: $(payload_path)")

        buf = IOBuffer()
        JSON3.write(buf, payload_obj)
        payload_json_literal = repr(String(take!(buf)))
        script_path = joinpath(tmp_dir, "run_script.jl")
        run_script_content = """
        using JuliaBUGS
        using LogDensityProblemsAD
        using LogDensityProblems
        using AdvancedHMC
        using AbstractMCMC
        using MCMCChains
        using Random
        using JSON3
        using StatsBase
        using DataFrames
        using Statistics
        using ReverseDiff

        # Recursively convert JSON3 structures to Julia NamedTuples/Arrays
        to_julia(x) = x
        # Map JSON null-like values to Julia missing without depending on JSON3.Null type
        map_null(v) = (isdefined(JSON3, :Null) && v isa getproperty(JSON3, :Null)) ? missing : (v === nothing ? missing : v)
        function to_julia(x::JSON3.Object)
            ks = collect(keys(x))
            keys_sym = Symbol.(ks)
            vals = map(k -> to_julia(map_null(x[k])), ks)
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractDict)
            keys_sym = Symbol.(collect(keys(x)))
            vals = map(k -> to_julia(map_null(x[k])), collect(keys(x)))
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractVector)
            xs = map(y -> to_julia(map_null(y)), x)
            # If this is a rectangular vector-of-vectors of numbers, convert to a Matrix
            try
                if !isempty(xs) && all(y -> y isa AbstractVector, xs)
                    ncols = length(xs[1])
                    if all(y -> length(y) == ncols, xs) && all(y -> all(z -> z isa Real, y), xs)
                        has_float = any(y -> any(z -> z isa AbstractFloat, y), xs)
                        T = has_float ? Float64 : Int
                        m = Matrix{T}(undef, length(xs), ncols)
                        @inbounds for i in 1:length(xs), j in 1:ncols
                            m[i, j] = T(xs[i][j])
                        end
                        return m
                    end
                end
            catch
                # fall through to returning xs
            end
            return xs
        end

        try
            # Read payload
            payload = JSON3.read(read($(payload_literal), String))
            settings = payload.settings
            @info "Worker: payload read"

            # Build data/inits
            has_json_data = length(collect(keys(payload.data))) > 0
            has_json_inits = length(collect(keys(payload.inits))) > 0

            if has_json_data
                data_nt = to_julia(payload.data)
            else
                # Fallback: parse Julia tuple string
                data_nt = isempty(payload.data_string) ? (;) : eval(Meta.parse(payload.data_string))
            end
            if has_json_inits
                inits_nt = to_julia(payload.inits)
            else
                inits_nt = isempty(payload.inits_string) ? (;) : eval(Meta.parse(payload.inits_string))
            end
            @info "Worker: data and inits built"

            # Define and compile model
            model_def = JuliaBUGS.@bugs($(model_literal), true, false)
            model = JuliaBUGS.compile(model_def, data_nt, inits_nt)
            @info "Worker: model compiled"

            # Wrap for AD (ReverseDiff by default)
            ad_model = ADgradient(:ReverseDiff, model)
            @info "Worker: AD gradient wrapper created (ReverseDiff)"

            # Settings
            n_samples = Int(get(settings, :n_samples, 1000))
            n_adapts = Int(get(settings, :n_adapts, 1000))
            n_chains = Int(get(settings, :n_chains, 1))
            seed = get(settings, :seed, nothing)
            @info "Worker: settings parsed"

            # RNG (robust to various JSON null representations)
            seed_val = seed isa Integer ? Int(seed) : tryparse(Int, string(seed))
            rng = seed_val === nothing ? Random.MersenneTwister() : Random.MersenneTwister(seed_val)
            @info "Worker: RNG initialized"

            # Initial params
            D = LogDensityProblems.dimension(model)
            initial_theta = rand(rng, D)
            @info "Worker: initial parameters generated" D=D

            # Sample (use threading if available and n_chains > 1)
            if n_chains > 1 && Threads.nthreads() > 1
                @info "Worker: starting sampling with threads"
                samples = AbstractMCMC.sample(
                    rng,
                    ad_model,
                    NUTS(0.8),
                    AbstractMCMC.MCMCThreads(),
                    n_samples;
                    n_adapts=n_adapts,
                    n_chains=n_chains,
                    chain_type=Chains,
                    init_params=initial_theta,
                    discard_initial=n_adapts,
                    progress=false,
                )
            else
                @info "Worker: starting sampling (single-thread)"
                samples = AbstractMCMC.sample(
                    rng,
                    ad_model,
                    NUTS(0.8),
                    n_samples;
                    n_adapts=n_adapts,
                    n_chains=n_chains,
                    chain_type=Chains,
                    init_params=initial_theta,
                    discard_initial=n_adapts,
                    progress=false,
                )
            end
            @info "Worker: sampling finished"

            # Summarize (convert ChainDataFrame -> DataFrame for row iteration)
            summary_df = DataFrame(MCMCChains.summarystats(samples))
            results_json = [Dict(pairs(row)) for row in eachrow(summary_df)]
            @info "Worker: summarystats computed"

            open($(results_literal), "w") do f
                JSON3.write(f, Dict("success" => true, "results" => results_json))
            end
            @info "Worker: results written"
        catch e
            open($(results_literal), "w") do f
                JSON3.write(f, Dict("success" => false, "error" => sprint(showerror, e)))
            end
            @info "Worker: error captured and written to results"
        end
        """
        write(script_path, run_script_content)
        log!(logs, "Generated execution script: $(script_path)")

        standalone_script_content = """
        using JuliaBUGS
        using LogDensityProblemsAD
        using LogDensityProblems
        using AdvancedHMC
        using AbstractMCMC
        using MCMCChains
        using Random
        using JSON3
        using StatsBase
        using DataFrames
        using Statistics
        using ReverseDiff

        # Optional: uncomment to auto-install dependencies if missing
        # import Pkg; Pkg.activate(temp=true); Pkg.add([
        #     "JuliaBUGS","LogDensityProblemsAD","LogDensityProblems","AdvancedHMC","AbstractMCMC",
        #     "MCMCChains","JSON3","StatsBase","DataFrames","Statistics","ReverseDiff"
        # ])

        # Helpers to convert JSON payload to Julia types
        to_julia(x) = x
        map_null(v) = (isdefined(JSON3, :Null) && v isa getproperty(JSON3, :Null)) ? missing : (v === nothing ? missing : v)
        function to_julia(x::JSON3.Object)
            ks = collect(keys(x))
            keys_sym = Symbol.(ks)
            vals = map(k -> to_julia(map_null(x[k])), ks)
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractDict)
            keys_sym = Symbol.(collect(keys(x)))
            vals = map(k -> to_julia(map_null(x[k])), collect(keys(x)))
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractVector)
            xs = map(y -> to_julia(map_null(y)), x)
            try
                if !isempty(xs) && all(y -> y isa AbstractVector, xs)
                    ncols = length(xs[1])
                    if all(y -> length(y) == ncols, xs) && all(y -> all(z -> z isa Real, y), xs)
                        has_float = any(y -> any(z -> z isa AbstractFloat, y), xs)
                        T = has_float ? Float64 : Int
                        m = Matrix{T}(undef, length(xs), ncols)
                        @inbounds for i in 1:length(xs), j in 1:ncols
                            m[i, j] = T(xs[i][j])
                        end
                        return m
                    end
                end
            catch
            end
            return xs
        end

        # Embedded payload and model for standalone execution
        payload = JSON3.read($(payload_json_literal))
        model_def = JuliaBUGS.@bugs($(model_literal), true, false)

        # Build data/inits
        has_json_data = length(collect(keys(payload.data))) > 0
        has_json_inits = length(collect(keys(payload.inits))) > 0
        data_nt = has_json_data ? to_julia(payload.data) : (isempty(payload.data_string) ? (;) : eval(Meta.parse(payload.data_string)))
        inits_nt = has_json_inits ? to_julia(payload.inits) : (isempty(payload.inits_string) ? (;) : eval(Meta.parse(payload.inits_string)))
        settings = payload.settings

        # Compile and wrap
        model = JuliaBUGS.compile(model_def, data_nt, inits_nt)
        ad_model = ADgradient(:ReverseDiff, model)

        # Settings
        n_samples = Int(get(settings, :n_samples, 1000))
        n_adapts = Int(get(settings, :n_adapts, 1000))
        n_chains = Int(get(settings, :n_chains, 1))
        seed = get(settings, :seed, nothing)

        # RNG
        seed_val = seed isa Integer ? Int(seed) : tryparse(Int, string(seed))
        rng = seed_val === nothing ? Random.MersenneTwister() : Random.MersenneTwister(seed_val)

        # Initial params
        D = LogDensityProblems.dimension(model)
        initial_theta = rand(rng, D)

        # Sample
        sampler = NUTS(0.8)
        if n_chains > 1 && Threads.nthreads() > 1
            samples = AbstractMCMC.sample(rng, ad_model, sampler, AbstractMCMC.MCMCThreads(), n_samples;
                n_adapts=n_adapts, n_chains=n_chains, chain_type=Chains, init_params=initial_theta,
                discard_initial=n_adapts, progress=false)
        else
            samples = AbstractMCMC.sample(rng, ad_model, sampler, n_samples;
                n_adapts=n_adapts, n_chains=n_chains, chain_type=Chains, init_params=initial_theta,
                discard_initial=n_adapts, progress=false)
        end

        # Summarize and write results.json to current directory
        summary_df = DataFrame(MCMCChains.summarystats(samples))
        results_json = [Dict(pairs(row)) for row in eachrow(summary_df)]
        open("results.json", "w") do f
            JSON3.write(f, Dict("success" => true, "results" => results_json))
        end
        """

        julia_executable = joinpath(Sys.BINDIR, "julia")
        project_dir = abspath(@__DIR__)
        cmd = `$(julia_executable) --project=$(project_dir) --threads=auto $(script_path)`

        log!(logs, "Executing script in worker process...")
        run(cmd)
        log!(logs, "Script execution finished.")

        log!(logs, "Reading results from: $(results_path)")
        results_content = JSON3.read(read(results_path, String))

        log!(logs, "Preparing response...")

        if !results_content.success
            throw(ErrorException(results_content.error))
        end

        # Control whether to attach the standalone script; default is false to keep responses small
        attach_standalone = get(settings, :attach_standalone, false)
        max_attach_bytes = 2_000_000  # 2 MB

        files_arr = Any[
            Dict("name" => "model.bugs", "content" => model_code),
            Dict("name" => "run_script.jl", "content" => run_script_content),
            Dict("name" => "payload.json", "content" => read(payload_path, String)),
        ]
        if isfile(results_path)
            push!(files_arr, Dict("name" => "results.json", "content" => read(results_path, String)))
        end

        if attach_standalone
            if sizeof(standalone_script_content) <= max_attach_bytes
                push!(files_arr, Dict("name" => "standalone_run.jl", "content" => standalone_script_content))
            else
                log!(logs, "Skipping standalone_run.jl (size=$(sizeof(standalone_script_content)) bytes exceeds limit $(max_attach_bytes))")
            end
        end

        # Diagnostics: log attachment sizes
        sizes = String[]
        for f in files_arr
            push!(sizes, string(f["name"], "=", sizeof(f["content"])) )
        end
        log!(logs, "Attaching $(length(files_arr)) files; sizes(bytes): $(join(sizes, ", "))")

        response_body = Dict(
            "success" => true,
            "results" => results_content.results,
            "logs" => logs,
            "files" => files_arr,
        )

        log!(logs, "Serializing response...")
        buf = IOBuffer()
        JSON3.write(buf, response_body)
        resp_json = String(take!(buf))
        log!(logs, "Serialization complete. Response bytes=$(sizeof(resp_json))")
        log!(logs, "Completed backend execution.")
        return HTTP.Response(200, ["Content-Type" => "application/json"], resp_json)
    catch e
        log!(logs, "An error occurred: $(sprint(showerror, e))")
        @error "Error during model execution" exception=(e, catch_backtrace())

        files_arr = Any[]
        if @isdefined(model_code)
            push!(files_arr, Dict("name" => "model.bugs", "content" => model_code))
        end
        if @isdefined(run_script_content)
            push!(files_arr, Dict("name" => "run_script.jl", "content" => run_script_content))
        end
        if @isdefined(standalone_script_content)
            push!(files_arr, Dict("name" => "standalone_run.jl", "content" => standalone_script_content))
        end
        if @isdefined(payload_path) && isfile(payload_path)
            push!(files_arr, Dict("name" => "payload.json", "content" => read(payload_path, String)))
        end
        if @isdefined(results_path) && isfile(results_path)
            push!(files_arr, Dict("name" => "results.json", "content" => read(results_path, String)))
        end
        error_response = Dict(
            "success" => false,
            "error" => sprint(showerror, e),
            "logs" => logs,
            "files" => files_arr,
        )
        return HTTP.Response(500, ["Content-Type" => "application/json"], JSON3.write(error_response))
    finally
        # Clean up temp directory in background with retries to avoid EBUSY on Windows
        @async safe_rmdir(tmp_dir)
    end
end

"""
Log a message to both the in-memory logs (returned to the client) and the terminal.
UI logs are kept clean (no timestamps); terminal logging can include timestamps via the logger formatter.
"""
function log!(logs::Vector{String}, msg::AbstractString)
    push!(logs, msg)
    @info msg
end

"""
Remove directory tree with retries and backoff. Resilient to transient EBUSY on Windows.
Intended to be called in a background task.
"""
function safe_rmdir(path::AbstractString; retries::Int=6, sleep_s::Float64=0.25)
    for _ in 1:retries
        try
            GC.gc()
            rm(path; recursive=true, force=true)
            return
        catch e
            msg = sprint(showerror, e)
            if occursin("EBUSY", msg) || e isa IOError
                sleep(sleep_s)
                continue
            else
                @warn "Unexpected error removing temp dir" path error=e
                return
            end
        end
    end
    @warn "Failed to remove temp dir after retries; leaving it on disk" path
end

const ROUTER = HTTP.Router()
HTTP.register!(ROUTER, "GET", "/api/health", health_check_handler)
HTTP.register!(ROUTER, "POST", "/api/run", run_model_handler)
HTTP.register!(ROUTER, "POST", "/api/run_model", run_model_handler)

port = 8081
println("Starting JuliaBUGS backend server on http://localhost:$(port)...")
HTTP.serve(cors_handler(ROUTER), "0.0.0.0", port)
