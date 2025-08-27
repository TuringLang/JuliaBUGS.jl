# File: server.jl
# This server is designed to be a generic executor.
# It creates a temporary, sandboxed Julia environment for each request,
# installs specified dependencies, and runs the BUGS model.

using HTTP
using JSON3

# Define CORS headers to allow cross-origin requests from the web app.
const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "Content-Type",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS",
]

# A simple middleware to handle CORS preflight (OPTIONS) requests and add headers to all responses.
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

# A simple handler for the health check endpoint.
function health_check_handler(req::HTTP.Request)
    return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(Dict("status" => "ok")))
end


# The main handler for processing model execution requests.
function run_model_handler(req::HTTP.Request)
    logs = String[]
    push!(logs, "Backend processing started.")
    
    # Create a temporary working directory for this run (no env activation)
    tmp_dir = mktempdir()
    push!(logs, "Created temporary working directory at: $(tmp_dir)")

    try
        # Parse the JSON body from the request
        body = JSON3.read(String(req.body))
        model_code = get(body, :model_code, "")
        data_json = haskey(body, :data) ? body[:data] : JSON3.Object()
        inits_json = haskey(body, :inits) ? body[:inits] : JSON3.Object()
        data_string = get(body, :data_string, "")
        inits_string = get(body, :inits_string, "")
        settings = get(body, :settings, JSON3.Object())

        push!(logs, "Request body parsed successfully.")

        # Write the BUGS model code to a file for the worker script to read
        model_path = joinpath(tmp_dir, "model.bugs")
        write(model_path, model_code)
        
        # Add a Julia-literal representation of the model code for embedding into the worker script
        model_literal = repr(String(model_code))

        # Compute absolute paths and their Julia-literal forms for safe embedding in worker script
        results_path = joinpath(tmp_dir, "results.json")
        payload_path = joinpath(tmp_dir, "payload.json")
        payload_literal = repr(String(payload_path))
        results_literal = repr(String(results_path))

        # Prepare payload for the worker script (prefer JSON data/inits if provided)
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

        # Generate worker script content
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

        # Recursively convert JSON3 structures to Julia NamedTuples/Arrays
        to_julia(x) = x
        function to_julia(x::JSON3.Object)
            ks = collect(keys(x))
            keys_sym = Symbol.(ks)
            vals = map(k -> to_julia(x[k]), ks)
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractDict)
            keys_sym = Symbol.(collect(keys(x)))
            vals = map(k -> to_julia(x[k]), collect(keys(x)))
            return NamedTuple{Tuple(keys_sym)}(vals)
        end
        function to_julia(x::AbstractVector)
            xs = map(to_julia, x)
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

            # Define and compile model
            model_def = JuliaBUGS.@bugs($(model_literal), true, false)
            model = JuliaBUGS.compile(model_def, data_nt, inits_nt)

            # Wrap for AD (ReverseDiff by default)
            ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

            # Settings
            n_samples = Int(get(settings, :n_samples, 1000))
            n_adapts = Int(get(settings, :n_adapts, 1000))
            n_chains = Int(get(settings, :n_chains, 1))
            seed = get(settings, :seed, nothing)

            # RNG
            has_seed = !(seed === nothing || seed === JSON3.Null() || seed === missing)
            rng = has_seed ? Random.MersenneTwister(Int(seed)) : Random.MersenneTwister()

            # Initial params
            D = LogDensityProblems.dimension(model)
            initial_theta = rand(rng, D)

            # Sample (use threading if available and n_chains > 1)
            if n_chains > 1 && Threads.nthreads() > 1
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

            # Summarize
            summary_df = MCMCChains.summarystats(samples)
            results_json = [Dict(pairs(row)) for row in eachrow(summary_df)]

            open($(results_literal), "w") do f
                JSON3.write(f, Dict("success" => true, "results" => results_json))
            end
        catch e
            open($(results_literal), "w") do f
                JSON3.write(f, Dict("success" => false, "error" => sprint(showerror, e)))
            end
        end
        """
        write(script_path, run_script_content)
        push!(logs, "Generated execution script in working directory.")

        # Execute the script using the fixed DoodleBUGS runtime project
        julia_executable = joinpath(Sys.BINDIR, "julia")
        project_dir = abspath(@__DIR__) # runtime directory contains Project.toml
        cmd = `$(julia_executable) --project=$(project_dir) --threads=auto $(script_path)`

        push!(logs, "Executing script in worker process...")
        run(cmd)
        push!(logs, "Script execution finished.")

        # Read results
        results_content = JSON3.read(read(results_path, String))

        if !results_content.success
            throw(ErrorException(results_content.error))
        end

        # Prepare response
        response_body = Dict(
            "success" => true,
            "results" => results_content.results,
            "logs" => logs,
            "files" => [
                Dict("name" => "model.bugs", "content" => model_code),
                Dict("name" => "run_script.jl", "content" => run_script_content),
            ],
        )
        return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(response_body))

    catch e
        push!(logs, "An error occurred: $(sprint(showerror, e))")
        @error "Error during model execution" exception=(e, catch_backtrace())

        error_response = Dict(
            "success" => false,
            "error" => sprint(showerror, e),
            "logs" => logs,
        )
        return HTTP.Response(500, ["Content-Type" => "application/json"], JSON3.write(error_response))
    finally
        # Clean up
        rm(tmp_dir, recursive=true)
    end
end

# Define the router and register the endpoints
const ROUTER = HTTP.Router()
HTTP.register!(ROUTER, "GET", "/api/health", health_check_handler)
HTTP.register!(ROUTER, "POST", "/api/run", run_model_handler)
HTTP.register!(ROUTER, "POST", "/api/run_model", run_model_handler) # backward compatibility

# Start the server with the CORS handler
port = 8081
println("Starting JuliaBUGS backend server on http://localhost:$(port)...")
HTTP.serve(cors_handler(ROUTER), "0.0.0.0", port)
