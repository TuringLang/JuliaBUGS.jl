"""
    CompilerPass

Abstract supertype for all compiler passes. Concrete subtypes should store data needed and artifacts.
"""
abstract type CompilerPass end

"""
    program!(pass::CompilerPass, expr::Expr, env::Dict, vargs...)

All compiler pass share the same interface. `program!` is the entry point for the compiler pass. It
traverses the AST and calls `assignment!` and `tilde_assignment!` for each assignment. It also calls
`for_loop!` for each for loop. Finally, it calls `post_process` to do any post processing.
"""
function program!(pass::CompilerPass, expr::Expr, env::Dict, vargs...)
    for ex in expr.args
        if Meta.isexpr(ex, :(=))
            assignment!(pass, ex, env, vargs...)
        elseif Meta.isexpr(ex, :(~))
            tilde_assignment!(pass, ex, env, vargs...)
        elseif Meta.isexpr(ex, :for)
            for_loop!(pass, ex, env, vargs...)
        else
            error()
        end
    end
    return post_process(pass, expr, env, vargs...)
end

function for_loop!(pass::CompilerPass, expr, env, vargs...)
    loop_var = expr.args[1].args[1]
    lb, ub = expr.args[1].args[2].args
    body = expr.args[2]
    lb, ub = eval(lb, env), eval(ub, env)
    @assert lb isa Int && ub isa Int "Only integer ranges are supported"
    for i in lb:ub
        for ex in body.args
            if Meta.isexpr(ex, [:(=), :(~)])
                assignment!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            elseif Meta.isexpr(ex, :for)
                for_loop!(pass, ex, merge(env, Dict(loop_var => i)), vargs...)
            else
                error()
            end
        end
    end
end

function assignment!(::CompilerPass, expr::Expr, env::Dict, vargs...) end

function tilde_assignment!(pass::CompilerPass, expr::Expr, env::Dict, vargs...)end

function post_process(pass::CompilerPass, expr, env, vargs...) end
