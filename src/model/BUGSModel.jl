module BUGSModel

include("model.jl")
include("evaluation.jl")
include("model_operations.jl")
include("serialization.jl")

export BUGSModel, initialize!

end # BUGSModel
