module Backend

using JuliaBUGS
using JuliaBUGS.BUGSPrimitives
using BangBang
using MacroTools
using Missings
using RuntimeGeneratedFunctions
using Setfield
using Graphs, MetaGraphsNext
RuntimeGeneratedFunctions.init(@__MODULE__)

include("./utils.jl")
include("./statement_types.jl")

function create_eval_module(data)
    m = Module(gensym(), true, true)
    Base.eval(m, :(import Core: eval; eval(expr) = Base.eval(@__MODULE__, expr)))
    @eval m begin
        using JuliaBUGS.BUGSPrimitives
        using RuntimeGeneratedFunctions
        RuntimeGeneratedFunctions.init(@__MODULE__)
    end
    for (k, v) in pairs(data)
        @eval m $k = $v
    end
    return m
end

struct CompileState
    data # the original data, used for reconstructing

    eval_module::Module
    variables_tracked_in_eval_module::Set{Symbol} # data variables and transformed variables

    logical_statements::Vector{Statement{:(=)}}
    stochastic_statements::Vector{Statement{:(~)}}
    logical_for_statements::Vector{ForStatement{:(=)}}
    stochastic_for_statements::Vector{ForStatement{:(~)}}

    # logical statements that are fully evaluated for transformed variables
    excluded_logical_statements
    excluded_logical_for_statements

    array_sizes
end

function CompileState(expr, data)
    logical_statements = Statement{:(=)}[]
    stochastic_statements = Statement{:(~)}[]
    logical_for_statements = ForStatement{:(=)}[]
    stochastic_for_statements = ForStatement{:(~)}[]

    assignments = filter(expr.args) do arg
        !Meta.isexpr(arg, :for)
    end
    for assignment in assignments
        statement = Statement(assignment, data)
        if is_logical(statement)
            push!(logical_statements, statement)
        else
            push!(stochastic_statements, statement)
        end
    end

    for loop in loop_fission(expr.args)
        for_statement = ForStatement(loop, data)
        if is_logical(for_statement)
            push!(logical_for_statements, for_statement)
        else
            push!(stochastic_for_statements, for_statement)
        end
    end

    return CompileState(
        data,
        create_eval_module(data),
        Set(keys(data)),
        logical_statements,
        stochastic_statements,
        logical_for_statements,
        stochastic_for_statements,
        [],
        [],
        Dict(),
    )
end

include("./determine_array_sizes.jl")
include("./check_multiple_assignments.jl")
include("./compute_transformed.jl")

end # module
