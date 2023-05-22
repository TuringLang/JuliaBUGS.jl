struct BUGSLogDensityProblem
    re::VarInfoReconstruct
end

function (p::BUGSLogDensityProblem)(x)
    vi = p.re(x)
    return vi.logp
end

function LogDensityProblems.logdensity(p::BUGSLogDensityProblem, x::AbstractArray)
    return p(x)
end

_dimension(::VarInfoReconstruct{L,DynamicPPL.DynamicTransformation}) where {L} = L
function LogDensityProblems.dimension(p::BUGSLogDensityProblem)
    return _dimension(p.re)
end

# LogDensityProblemsAD will set this to 1 
function LogDensityProblems.capabilities(::BUGSLogDensityProblem)
    return LogDensityProblems.LogDensityOrder{0}
end
