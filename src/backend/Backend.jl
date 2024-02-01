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

struct CompileState
    data # the original data, used for reconstructing
    variables_tracked_in_eval_module

    logical_statements::Vector{Statement{:(=)}}
    stochastic_statements::Vector{Statement{:(~)}}
    logical_for_statements::Vector{ForStatement{:(=)}}
    stochastic_for_statements::Vector{ForStatement{:(~)}}

    array_sizes
end

function CompileState(expr, data)
    assignments = filter(expr.args) do arg
        !Meta.isexpr(arg, :for)
    end

    fissioned_loops = loop_fission(expr.args)

    logical_statements = Statement{:(=)}[]
    stochastic_statements = Statement{:(~)}[]
    logical_for_statements = ForStatement{:(=)}[]
    stochastic_for_statements = ForStatement{:(~)}[]

    for assignment in assignments
        statement = Statement(assignment, data)
        if is_logical(statement)
            push!(logical_statements, statement)
        else
            push!(stochastic_statements, statement)
        end
    end

    for loop in fissioned_loops
        for_statement = ForStatement(loop, data)
        if is_logical(for_statement)
            push!(logical_for_statements, for_statement)
        else
            push!(stochastic_for_statements, for_statement)
        end
    end

    return CompileState(
        data,
        Set(keys(data)),
        logical_statements,
        stochastic_statements,
        logical_for_statements,
        stochastic_for_statements,
        Dict(),
    )
end

include("./determine_array_sizes.jl")

end # module
