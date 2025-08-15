# File: server.jl
# This server is designed to be a generic executor.
# It creates a temporary, sandboxed Julia environment for each request,
# installs specified dependencies, and runs the BUGS model.

using HTTP
using JSON3
using Pkg

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
    
    # Create a temporary, sandboxed environment for this run
    tmp_dir = mktempdir()
    push!(logs, "Created temporary sandbox environment at: $(tmp_dir)")

    try
        # Activate the sandbox project environment
        Pkg.activate(tmp_dir)
        
        # Parse the JSON body from the request
        body = JSON3.read(String(req.body))
        model_code = body.model_code
        data_string = body.data_string
        inits_string = body.inits_string
        dependencies = body.dependencies
        settings = get(body, :settings, JSON3.Object())

        push!(logs, "Request body parsed successfully.")

        # Add specified dependencies to the sandbox environment
        push!(logs, "Adding $(length(dependencies)) dependencies to sandbox...")
        for dep in dependencies
            if isempty(dep.version)
                Pkg.add(dep.name)
            else
                Pkg.add(name=dep.name, version=dep.version)
            end
        end
        push!(logs, "All dependencies installed in sandbox.")

        # Write the user's BUGS model code to a file in the sandbox
        model_path = joinpath(tmp_dir, "model.bugs")
        write(model_path, model_code)
        
        # The core logic will be executed in a separate, sandboxed Julia process
        # to ensure isolation and use the correct project environment.
        script_path = joinpath(tmp_dir, "run_script.jl")
        
        # This script contains the actual model compilation and sampling logic.
        # It will be executed by the sandboxed Julia process.
        run_script_content = """
        using JuliaBUGS
        using LogDensityProblemsAD
        using AdvancedHMC
        using MCMCChains
        using Random
        using JSON3

        try
            # Define the model from the string
            model_def = JuliaBUGS.@bugs_str(\"\"\"
            $(model_code)
            \"\"\", true, false)

            # Parse data and inits from strings into NamedTuples
            data_nt = eval(Meta.parse(\"\"\"
            $(data_string)
            \"\"\"))
            inits_nt = eval(Meta.parse(\"\"\"
            $(inits_string)
            \"\"\"))

            # Compile the model
            model = JuliaBUGS.compile(model_def, data_nt, inits_nt)

            # Wrap for AD
            ad_model = ADgradient(:ReverseDiff, model; compile=Val(true))

            # Sampler settings
            n_samples = $(get(settings, :n_samples, 1000))
            n_adapts = $(get(settings, :n_adapts, 1000))
            
            # Run sampler
            D = LogDensityProblems.dimension(model)
            initial_Î¸ = rand(D)
            samples = AbstractMCMC.sample(
                ad_model,
                NUTS(0.8),
                n_samples;
                n_adapts=n_adapts,
                chain_type=Chains,
                init_params=initial_Î¸,
                discard_initial=n_adapts
            )

            # Format results
            summary_stats = summary(samples)
            results_json = [Dict(pairs(row)) for row in eachrow(summary_stats)]
            
            # Write results to a file
            open("results.json", "w") do f
                JSON3.write(f, Dict("success" => true, "results" => results_json))
            end

        catch e
            open("results.json", "w") do f
                JSON3.write(f, Dict("success" => false, "error" => sprint(showerror, e)))
            end
        end
        """
        write(script_path, run_script_content)
        push!(logs, "Generated execution script in sandbox.")

        # Execute the script in the sandboxed environment
        # --project points to the sandbox, ensuring it uses the correct dependencies.
        julia_executable = joinpath(Sys.BINDIR, "julia")
        cmd = `$(julia_executable) --project=$(tmp_dir) $(script_path)`
        
        push!(logs, "Executing script in sandboxed process...")
        run(cmd)
        push!(logs, "Script execution finished.")

        # Read the results generated by the script
        results_path = joinpath(tmp_dir, "results.json")
        results_content = JSON3.read(read(results_path, String))

        # Check if the script execution was successful
        if !results_content.success
            throw(ErrorException(results_content.error))
        end

        # Read generated project files to send back to the user
        project_toml_content = read(joinpath(tmp_dir, "Project.toml"), String)
        manifest_toml_content = read(joinpath(tmp_dir, "Manifest.toml"), String)
        push!(logs, "Successfully retrieved results and project files.")

        # Prepare the final successful response
        response_body = Dict(
            "success" => true,
            "results" => results_content.results,
            "logs" => logs,
            "files" => [
                Dict("name" => "model.bugs", "content" => model_code),
                Dict("name" => "run_script.jl", "content" => run_script_content),
                Dict("name" => "Project.toml", "content" => project_toml_content),
                Dict("name" => "Manifest.toml", "content" => manifest_toml_content)
            ]
        )
        return HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(response_body))

    catch e
        # If any error occurs during the process, capture and return it
        push!(logs, "An error occurred: $(sprint(showerror, e))")
        @error "Error during model execution" exception=(e, catch_backtrace())

        error_response = Dict(
            "success" => false,
            "error" => sprint(showerror, e),
            "logs" => logs
        )
        return HTTP.Response(500, ["Content-Type" => "application/json"], JSON3.write(error_response))
    
    finally
        # Clean up the temporary directory
        rm(tmp_dir, recursive=true)
        # It's good practice to reactivate the main project environment
        Pkg.activate()
    end
end

# Define the router and register the endpoints
const ROUTER = HTTP.Router()
HTTP.register!(ROUTER, "GET", "/api/health", health_check_handler)
HTTP.register!(ROUTER, "POST", "/api/run_model", run_model_handler)

# Start the server with the CORS handler
port = 8081
println("Starting JuliaBUGS backend server on http://localhost:$(port)...")
HTTP.serve(cors_handler(ROUTER), "0.0.0.0", port)
