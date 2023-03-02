function ref_to_getindex(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            return Expr(:call, :getindex, sub_expr.args...)
        else
            return sub_expr
        end
    end
end

function print_to_file(x::Dict, filename="output.jl")
    file_path = "/home/sunxd/JuliaBUGS.jl/notebooks/" * filename
    open(file_path, "w+") do f
        for (k, v) in trace
            println(f, k, " = ", v)
        end
    end
end
