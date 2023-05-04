struct BUGSLogDensityProblem 
    re::JuliaBUGS.VarInfoReconstruct
end

function (p::BUGSLogDensityProblem)(x) 
    vi = p.re(x)
    return vi.logp
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, x::AbstractArray)
    return p(x)
end

_dimension(re::JuliaBUGS.VarInfoReconstruct{L, DynamicPPL.DynamicTransformation}) where L = L
function LogDensityProblems.dimension(p::BUGSLogDensityProblem) 
    _dimension(p.re)
end

function LogDensityProblems.capabilities(::BUGSLogDensityProblem) 
    return LogDensityProblems.LogDensityOrder{0}
end
