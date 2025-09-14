module AutoMarginalizationExperiments

using Random
using LinearAlgebra
using Statistics
using Printf

using Distributions
using ADTypes
using LogDensityProblems
using LogDensityProblemsAD

using JuliaBUGS
using JuliaBUGS: @bugs, compile, settrans
import JuliaBUGS.Model

include("metrics.jl")
include("ordering.jl")
include("synth_gmm.jl")
include("synth_hmm.jl")
include("harness.jl")

export 
    # Metrics
    Metrics,
    # GMM
    synth_gmm, build_gmm_model, run_gmm_autmarg_nuts,
    # HMM
    synth_hmm_binary, build_hmm2_model, run_hmm_autmarg_nuts,
    # Ordering helpers
    build_interleaved_order, prepare_minimal_cache_keys

end # module
