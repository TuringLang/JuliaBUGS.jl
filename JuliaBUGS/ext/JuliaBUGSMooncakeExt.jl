module JuliaBUGSMooncakeExt

using JuliaBUGS
using Mooncake

# The callable contains code and caches; all model values are explicit arguments.
Mooncake.tangent_type(::Type{<:JuliaBUGS._MistyClosureFunction}) = Mooncake.NoTangent

# Differentiate the same source using the backend's current method table. Runtime
# specialization caches are not part of the mathematical function.
Mooncake.@mooncake_overlay function (f::JuliaBUGS._MistyClosureFunction)(a, b)
    return f.source(a, b)
end

end
