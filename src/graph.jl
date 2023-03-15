struct Graph end

abstract type NodeFunction end
struct IsStochastic <: NodeFunction end
struct IsLogical <: NodeFunction end

using MetaGraphsNext