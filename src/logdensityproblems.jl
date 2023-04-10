struct BUGSLogDensityProblem end

function (p::BUGSLogDensityProblem)(x) end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, x)
    return p(x)
end

function LogDensityProblems.dimension(p::BUGSLogDensityProblem) end

# https://github.com/tpapp/LogDensityProblemsAD.jl/blob/master/ext/LogDensityProblemsADReverseDiffExt.jl
function LogDensityProblems.logdensity_and_gradient(p::BUGSLogDensityProblem, x) end

function LogDensityProblems.capabilities(p::BUGSLogDensityProblem) end
