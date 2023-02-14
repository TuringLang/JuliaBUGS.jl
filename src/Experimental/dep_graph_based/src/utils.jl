function ref_to_getindex(expr)
    return MacroTools.postwalk(expr) do sub_expr
        if Meta.isexpr(sub_expr, :ref)
            return Expr(:call, :getindex, sub_expr.args...)
        else
            return sub_expr
        end
    end
end