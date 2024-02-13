using StaticArrays: StaticArrays
using MacroTools: prewalk, postwalk, @q, @qq

const __DATA_KEYS__ = gensym(:KEYS)
const __DATA_VALUE_TYPES__ = gensym(:VALUE_TYPES)

const __ARRAY_VARS__ = gensym(:ARRAY_VARS)

const __data__ = gensym(:data)
const __array_var_names__ = gensym(:array_var_names)
const __array_sizes__ = gensym(:array_sizes)

const __evaluate_env__ = gensym(:evaluate_env)

const __ALL_VARS__ = gensym(:ALL_VARS)

const __RHS_UNION_TYPE__ = Union{Int,Float64,Symbol,Expr}
const __REAL_WITH_MISSING__ = Union{Int,Float64,Missing}

abstract type Analysis end

function generate_analysis_function(::Analysis, expr::Expr) end

function generate_analysis_function_statement_deterministic end
function generate_analysis_function_statement_stochastic end

# add statement counter to the argument
function generate_analysis_function_mainbody!(
    analysis::Analysis, model_def::Expr, statement_counter::Ref{Int}=Ref(0)
)
    args = Expr[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            arg = generate_analysis_function_statement_deterministic(
                analysis, lhs, rhs, statement_counter[]
            )
            if arg !== nothing
                push!(args, arg)
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            arg = generate_analysis_function_statement_stochastic(
                analysis, lhs, rhs, statement_counter[]
            )
            if arg !== nothing
                push!(args, arg)
            end
        elseif @capture(
            statement,
            for loop_var_ in lower_:upper_
                body_
            end
        )
            push!(
                args,
                @q(
                    for $loop_var in ($lower):($upper)
                        $(
                            generate_analysis_function_mainbody!(
                                analysis, body, statement_counter
                            )...
                        )
                    end
                )
            )
        else
            push!(args, statement) # Debugging: don't change other type of statements
        end
    end
    return args
end

include("utils.jl")
include("determine_array_sizes.jl")
include("check_multiple_assignments.jl")
include("compute_transformed.jl")
include("count_free_vars.jl")
include("refine_loops.jl")
