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
                "timeout_s" => get(settings, :timeout_s, nothing),
            ),
        )
        open(payload_path, "w") do f
            JSON3.write(f, payload_obj)
        end
        log!(logs, "Wrote payload to: $(payload_path)")

        script_path = joinpath(tmp_dir, "run_script.jl")
        run_script_content = """
        using JuliaBUGS, AbstractMCMC, AdvancedHMC, LogDensityProblems, LogDensityProblemsAD, MCMCChains, ReverseDiff, Random, JSON3, DataFrames, StatsBase, Statistics

        try
            # Read payload
            payload = JSON3.read(read($(repr(String(payload_path))), String))
            settings = payload.settings

            # Robust integer parsing for settings that may arrive as numbers or strings
            to_int(x, default) = begin
                xv = x
                if xv isa Integer
                    return Int(xv)
                else
                    p = tryparse(Int, string(xv))
                    return p === nothing ? default : p
                end
            end

            # Build data/inits as NamedTuples; prefer strings when valid, else JSON fallback that supports keys like "alpha.c"
            to_nt(obj) = (; (Symbol(String(k)) => v for (k, v) in pairs(obj))...)
            data_nt = begin
                if !isempty(payload.data_string)
                    try
                        eval(Meta.parse(payload.data_string))
                    catch
                        to_nt(payload.data)
                    end
                else
                    to_nt(payload.data)
                end
            end
            inits_nt = begin
                if !isempty(payload.inits_string)
                    try
                        eval(Meta.parse(payload.inits_string))
                    catch
                        to_nt(payload.inits)
                    end
                else
                    to_nt(payload.inits)
                end
            end

            # Define and compile model
            model_def = JuliaBUGS.@bugs($(model_literal), true, false)
            model = JuliaBUGS.compile(model_def, data_nt, inits_nt)

            # Wrap for AD (ReverseDiff by default)
            ad_model = ADgradient(:ReverseDiff, model)
            ld_model = AbstractMCMC.LogDensityModel(ad_model)

            # Settings
            n_samples = to_int(get(settings, :n_samples, 1000), 1000)
            n_adapts = to_int(get(settings, :n_adapts, 1000), 1000)
            n_chains = to_int(get(settings, :n_chains, 1), 1)
            seed = get(settings, :seed, nothing)

            # RNG
            seed_val = seed isa Integer ? Int(seed) : tryparse(Int, string(seed))
            rng = seed_val === nothing ? Random.MersenneTwister() : Random.MersenneTwister(seed_val)

            # Initial params
            D = LogDensityProblems.dimension(ad_model)
            initial_theta = rand(rng, D)

            # Sample
            if n_chains > 1 && Threads.nthreads() > 1
                samples = AbstractMCMC.sample(
                    rng,
                    ld_model,
                    NUTS(0.8),
                    AbstractMCMC.MCMCThreads(),
                    n_samples,
                    n_chains;
                    n_adapts=n_adapts,
                    chain_type=Chains,
                    init_params=initial_theta,
                    discard_initial=n_adapts,
                    progress=false,
                )
            else
                if n_chains > 1
                    samples = AbstractMCMC.sample(
                        rng,
                        ld_model,
                        NUTS(0.8),
                        AbstractMCMC.MCMCSerial(),
                        n_samples,
                        n_chains;
                        n_adapts=n_adapts,
                        chain_type=Chains,
                        init_params=initial_theta,
                        discard_initial=n_adapts,
                        progress=false,
                    )
                else
                    samples = AbstractMCMC.sample(
                        rng,
                        ld_model,
                        NUTS(0.8),
                        n_samples;
                        n_adapts=n_adapts,
                        chain_type=Chains,
                        init_params=initial_theta,
                        discard_initial=n_adapts,
                        progress=false,
                    )
                end
            end

            # Summaries
            summary_df = DataFrame(MCMCChains.summarystats(samples))
            summary_json = [Dict(pairs(row)) for row in eachrow(summary_df)]

            q = [0.025, 0.25, 0.5, 0.75, 0.975]
            quant_df = DataFrame(MCMCChains.quantile(samples; q=q))
            quant_json = [Dict(pairs(row)) for row in eachrow(quant_df)]

            open($(repr(String(results_path))), "w") do f
                JSON3.write(f, Dict(
                    "success" => true,
                    "summary" => summary_json,
                    "quantiles" => quant_json,
                ))
            end
        catch e
            open($(repr(String(results_path))), "w") do f
                JSON3.write(f, Dict("success" => false, "error" => sprint(showerror, e)))
            end
        end
        """
        write(script_path, run_script_content)
        log!(logs, "Generated execution script: $(script_path)")

        julia_executable = joinpath(Sys.BINDIR, "julia")
        project_dir = abspath(@__DIR__)
        cmd = `$(julia_executable) --project=$(project_dir) --threads=auto $(script_path)`

        log!(logs, "Executing script in worker process...")
        timeout_s = try Int(get(settings, :timeout_s, 0)) catch; 0 end
        if timeout_s <= 0
            run(cmd)
            log!(logs, "Script execution finished.")
        else
            proc = run(cmd; wait=false)
            log!(logs, "Worker process started; enforcing timeout of $(timeout_s)s")
            deadline = time() + timeout_s
            while process_running(proc) && time() < deadline
                sleep(0.1)
            end
            if process_running(proc)
                log!(logs, "Timeout reached; killing worker process...")
                try
                    kill(proc)
                    log!(logs, "Worker process killed due to timeout.")
                catch e
                    log!(logs, "Failed to kill worker process: $(sprint(showerror, e)))")
                end
                throw(ErrorException("Execution timed out after $(timeout_s) seconds"))
            else
                wait(proc)
                log!(logs, "Script execution finished within timeout.")
            end
        end

        log!(logs, "Reading results from: $(results_path)")
        results_content = JSON3.read(read(results_path, String))

        log!(logs, "Preparing response...")

        if !results_content.success
            throw(ErrorException(results_content.error))
        end

        files_arr = Any[
            Dict("name" => "model.bugs", "content" => model_code),
            Dict("name" => "run_script.jl", "content" => run_script_content),
            Dict("name" => "payload.json", "content" => read(payload_path, String)),
        ]
        if isfile(results_path)
            push!(files_arr, Dict("name" => "results.json", "content" => read(results_path, String)))
        end

        # Diagnostics: log attachment sizes
        sizes = String[]
        for f in files_arr
            push!(sizes, string(f["name"], "=", sizeof(f["content"])) )
        end
        log!(logs, "Attaching $(length(files_arr)) files; sizes(bytes): $(join(sizes, ", "))")

        response_body = Dict(
            "success" => true,
            "results" => (haskey(results_content, :summary) ? results_content[:summary] : (haskey(results_content, :results) ? results_content[:results] : Any[])),
            "summary" => (haskey(results_content, :summary) ? results_content[:summary] : Any[]),
            "quantiles" => (haskey(results_content, :quantiles) ? results_content[:quantiles] : Any[]),
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
