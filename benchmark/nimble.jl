using RCall
R"""
library(nimble)
nimbleOptions(enableDerivs = TRUE)
nimbleOptions(buildModelDerivs = TRUE)
nimbleOptions(allowDynamicIndexing = FALSE)
"""
R"""
library(microbenchmark)
"""

# function to get log likelihood and gradient
R"""
logLikelihood_nf <- nimbleFunction(
  setup = function(model, paramNodes) {
    # Determine nodes for calculating the log likelihood for parameters given by
    # paramNodes, ignoring any priors.
    calcNodes <- model$getDependencies(paramNodes, self = FALSE)
    # Set up the additional arguments for nimDerivs involving model$calculate
    derivsInfo <- makeModelDerivsInfo(model, paramNodes, calcNodes)
    updateNodes <- derivsInfo$updateNodes
    constantNodes <- derivsInfo$constantNodes
    # Create a parameter transformation between original and unconstrained
    # parameter spaces.
    transformer <- parameterTransform(model, paramNodes)
  },
  methods = list(
    neg_logLikelihood_p = function(p = double(1)) {
      # Put values in model and calculate negative log likelihood.
      values(model, paramNodes) <<- p
      return(-model$calculate(calcNodes))
      returnType(double())
    },
    neg_logLikelihood = function(ptrans = double(1)) {
      # Objective function for optim,
      # using transformed parameter space.
      p <- transformer$inverseTransform(ptrans)
      return(neg_logLikelihood_p(p))
      returnType(double())
    },
    gr_neg_logLikelihood = function(ptrans = double(1)) {
      # Gradient of neg log likelihood
      p <- transformer$inverseTransform(ptrans)
      d <- derivs(neg_logLikelihood_p(p), wrt = 1:length(p), order = 1,
                  model = model, updateNodes = updateNodes,
                  constantNodes = constantNodes)
      return(d$jacobian[1,])
      returnType(double(1))
    },
    transform = function(p = double(1)) {
      # Give user access to the transformation ...
      return(transformer$transform(p))
      returnType(double(1))
    },
    inverse = function(ptrans = double(1)) { # ... and its inverse.
      return(transformer$inverseTransform(ptrans))
      returnType(double(1))
    }
  ),
  buildDerivs = 'neg_logLikelihood_p'
)
"""

# not used anymore
function create_nimble_model_from_juliabugs_example(model_name)
    bugs_program = JuliaBUGS.BUGSExamples.VOLUME_1[model_name].original_syntax_program
    bugs_data = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].data))
    bugs_inits = Dict(pairs(JuliaBUGS.BUGSExamples.VOLUME_1[model_name].inits))

    @rput bugs_program
    @rput bugs_data
    @rput bugs_inits

    open("bugs_program.txt", "w") do file
        write(file, bugs_program)
    end

    R"""
    model <- readBUGSmodel(model = "bugs_program.txt", data = bugs_data, inits = bugs_inits, buildDerivs = TRUE)
    Cmodel <- compileNimble(model)
    """
end

MODEL_VOL1_NIMBLE = OrderedDict(
    :rats => :rats,
    :pumps => :pump,
    :seeds => :seeds,
    :salm => :salm,
    :equiv => :equiv,
    :dyes => :dyes,
    :epil => :epil,
    :blockers => :blocker,
    :oxford => :oxford, # give nans
    :lsat => :lsat,
    # :bones => :bones, # discrete parameters
    # :mice => :mice, # not working, discrete parameters
    # :kidney => :kidney, # same reason as mice, I think they haven't figure it out yet
    # :leuk => :leuk, # doesn't work
    # :leukfr => :leukfr, # doesn't work
)

function create_nimble_model(model_name)
    nimble_model_name = MODEL_VOL1_NIMBLE[model_name]
    str = """
    model <- readBUGSmodel('$(nimble_model_name).bug', dir = getBUGSexampleDir('$(nimble_model_name)'))
    Cmodel <- compileNimble(model)
    """
    return reval(str)
end

# note:
# 1. add epil.bugs using content of epil2.bug
# 2. add `p.item[R,T]` to lsat var section

nimble_result = OrderedDict()
for model_name in keys(MODEL_VOL1_NIMBLE)
    println("Model: $model_name")
    create_nimble_model(model_name)

    # get parameters and dimension
    R"""
    stoch_nodes = model$getNodeNames(stochOnly = TRUE)
    parameters = stoch_nodes[!sapply(stoch_nodes, function(node) model$isData(node))]
    num_params <- length(parameters)
    rand_params <- runif(num_params)
    """

    R"""
        ll_model <- logLikelihood_nf(model, parameters)
        cll_model <- compileNimble(ll_model, project = model)
    """

    R"""
    ll <- cll_model$neg_logLikelihood(rand_params)
    gr <- cll_model$gr_neg_logLikelihood(rand_params)
    """
    @rget ll
    @rget gr
    @show ll, gr

    R"""
    nll_benchmark_result <- microbenchmark(
        cll_model$neg_logLikelihood(transformed_parameters)
    )
    """

    R"""
    gr_benchmark_result <- microbenchmark(
        cll_model$gr_neg_logLikelihood(transformed_parameters)
    )
    """

    @rget nll_benchmark_result
    nll_median_time = Statistics.median(nll_benchmark_result.time) * 1e-6 # give in microseconds, convert to seconds
    @rget gr_benchmark_result
    gr_median_time = Statistics.median(gr_benchmark_result.time) * 1e-6

    nimble_result[model_name] = (nll_median_time, gr_median_time)
end

##

# this doesn't work, should use the function above
function run_nimble_benchmark(model_name)
    create_nimble_model(model_name)
    # reval("model_name <- '$(string(model_name))'")
    R"""
        # model <- readBUGSmodel(model_name, dir = getBUGSexampleDir(model_name), buildDerivs = TRUE)
        compiledModel <- compileNimble(model)

        # compiled log joint computation function
        # calculate_nf <- nimbleFunction(
        #     setup = function(model) {},
        #     run = function() {
        #         ans <- model$calculate()
        #         return(ans)
        #         returnType(double(0))
        #     }
        # )
        # calculate_result <- calculate_nf(model)
        # compiledCalculate <- compileNimble(calculate_result, project = model)
        # logp <- compiledCalculate$run()

        derivs_nf <- nimbleFunction(
        setup = function(model, with_respect_to_nodes, calc_nodes) {},
        run = function(order = integer(1),
                        reset = logical(0, default = FALSE)) {
            ans <- nimDerivs(model$calculate(calc_nodes), wrt = with_respect_to_nodes,
                            order = order, reset = reset)
            return(ans)
            returnType(ADNimbleList())
        }
        )
        wrt_nodes <- model$getNodeNames(stochOnly = TRUE)
        # Filter out data nodes
        wrt_nodes <- wrt_nodes[!sapply(wrt_nodes, function(node) model$isData(node))]
        calc_nodes <- model$getDependencies(wrt_nodes)
        derivs_all <- derivs_nf(model, wrt_nodes, calc_nodes)
        cDerives_all <- compileNimble(derivs_all, project = model)
        derivs_result <- cDerives_all$run(order = 1)
        # benchmark_result_median <- median(microbenchmark(cDerives_all$run(order = 1), times = 100)$time)
    """
    return @rget derivs_result
    return @be reval("cDerives_all\$run(order = 1)")
end
