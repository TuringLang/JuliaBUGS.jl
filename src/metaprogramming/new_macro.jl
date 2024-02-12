using StaticArrays: StaticArrays
using MacroTools: prewalk, postwalk, @q

const __DATA_KEYS__ = gensym(:KEYS)
const __DATA_VALUE_TYPES__ = gensym(:VALUE_TYPES)

include("utils.jl")
include("determine_array_sizes.jl")
include("check_multiple_assignments.jl")
include("compute_transformed_variables.jl")

macro _bugs(expr::Expr)
    # TODO: LineNumberNodes
    expr = MacroTools.postwalk(MacroTools.rmlines, expr)
    gen_expr = Expr(:block, )
    push!(gen_expr.args, gen_deter_arr_sizes_func(expr))
    return esc(gen_expr)
end
