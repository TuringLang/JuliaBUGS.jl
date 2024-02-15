struct BuildGraph <: Analysis end

__g__ = gensym(:g)

function generate_analysis_function(
    analysis::BuildGraph, simplified_model_def::Expr, ::NamedTuple{all_vars}
) where {all_vars}
    return @q function __build_graph($__evaluate_env__::NamedTuple)
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        # $__g__ = JuliaBUGS.MetaGraphNext.MetaGraph(
        #     DiGraph(); label_type=Tuple{Symbol,Vararg{Int}}, vertex_data_type=Int
        # )
        $__g__ = Dict{
            Tuple{Symbol,Vararg{Union{Int,UnitRange{Int}}}},
            Vector{Tuple{Symbol,Vararg{Union{Int,UnitRange{Int}}}}},
        }()
        $(generate_analysis_function_mainbody(analysis, simplified_model_def)...)
        return $__g__
    end
end

function generate_analysis_function_mainbody(
    analysis::BuildGraph,
    model_def::Expr,
    loop_vars::Tuple{Vararg{Symbol}}=(),
    statement_counter::Ref{Int}=Ref(0),
)
    args = Expr[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            push!(
                args,
                @q(
                    JuliaBUGS.@build_graph_with_expr(
                        $statement, $(statement_counter[]), $(loop_vars...)
                    )
                )
            )
        elseif @capture(
            statement,
            if cond_
                body_
            end
        ) # `if` is introduced after `LoopIteration` to guard against already computed deterministic variables 
            statement_counter[] += 1
            @capture(only(body), lhs_ = rhs_)
            push!(
                args,
                @q(
                    JuliaBUGS.@build_graph_with_expr(
                        $statement, $(statement_counter[]), $(loop_vars...)
                    )
                )
            )
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            push!(
                args,
                @q(
                    JuliaBUGS.@build_graph_with_expr(
                        $statement, $(statement_counter[]), $(loop_vars...)
                    )
                )
            )
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
                            generate_analysis_function_mainbody(
                                analysis, body, (loop_vars..., loop_var), statement_counter
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

macro build_graph_with_expr(
    statement::Expr, statement_counter::Int, loop_vars::Vararg{Symbol}
)
    return esc(_build_graph_with_expr(statement, statement_counter, loop_vars...))
end

function _build_graph_with_expr(
    statement::Expr, statement_counter::Int, loop_vars::Vararg{Symbol}
)
    @capture(statement, lhs_ ~ rhs_) || @capture(statement, lhs_ = rhs_)
    rhs_vars = extract_variable_names(rhs, loop_vars)
    rhs_scalars = [(var,) for var in keys(rhs_vars) if getfield(rhs_vars, var) === 0]
    __lhs_label__ = gensym(:lhs_label)
    __rhs_labels__ = gensym(:rhs_labels)

    ex_body = if !isempty(rhs_scalars)
        @q begin
            $__lhs_label__ = JuliaBUGS.@lhs_var_label($lhs)
            $__rhs_labels__ = [
                $(Meta.quot((rhs_scalars...)))
                JuliaBUGS.@rhs_var_labels($rhs, $(loop_vars...))...
            ]
            $__g__[$__lhs_label__] = $__rhs_labels__
        end
    else
        @q begin
            $__lhs_label__ = JuliaBUGS.@lhs_var_label($lhs)
            $__rhs_labels__ = JuliaBUGS.@rhs_var_labels($rhs, $(loop_vars...))
            $__g__[$__lhs_label__] = $__rhs_labels__
        end
    end

    if Meta.isexpr(statement, :(=))
        return @q if !JuliaBUGS._is_concrete($lhs)
            $(ex_body.args...)
        end
    else
        return @q begin
            $(ex_body.args...)
        end
    end
end

macro lhs_var_label(lhs::Union{Symbol,Expr})
    if lhs isa Symbol
        return esc(@q(($(Meta.quot(lhs)),)))
    else
        @capture(lhs, v_[indices__])
        return esc(@q(($(Meta.quot(v)), $(indices...))))
    end
end

# this macro assume the env is populated by the values
macro rhs_var_labels(expr::Expr, loop_vars::Vararg{Symbol})
    expr = serialize_expr(expr)
    return esc(_compute_dependent_variables(expr, loop_vars...))
end

function _compute_dependent_variables(expr::Expr, loop_vars::Vararg{Symbol})
    __deps__ = gensym(:deps)
    __indices__ = gensym(:indices)
    __not_evaluated__ = gensym(:not_evaluated)
    __val__ = gensym(:val)
    return @q begin
        $__deps__ = Tuple{Symbol,Vararg{Union{Int,UnitRange{Int}}}}[]
        $(
            MacroTools.postwalk(expr) do sub_expr
                if MacroTools.@capture(sub_expr, v_[indices__])
                    return MacroTools.@q begin
                        $__indices__ = ($(indices...),)
                        $__not_evaluated__ = findall(ismissing, $(__indices__))
                        if !isempty($__not_evaluated__)
                            for i in $__not_evaluated__
                                $(__indices__)[i] = 1:(size($v)[i])
                            end
                            push!($__deps__, ($(Meta.quot(v)), $__indices__...))
                            missing
                        else
                            $__val__ = $v[$(__indices__)...]
                            if ismissing($__val__) || any(ismissing, $__val__)
                                push!($__deps__, ($(Meta.quot(v)), $__indices__...))
                            end
                            $v[$(__indices__)...]
                        end
                    end
                elseif @capture(sub_expr, f_(args__))
                    f = if f ∈ BUGSPrimitives.BUGS_FUNCTIONS
                        @q(JuliaBUGS.BUGSPrimitives.$f)
                    else
                        f
                    end
                    return @q try
                        $f($(args...))
                    catch
                        missing
                    end
                end
                return sub_expr
            end
        )
        $__deps__
    end
end

function serialize_expr(expr::Expr)
    ret_ex = Expr(:block)
    ex = MacroTools.postwalk(expr) do sub_expr
        if @capture(sub_expr, v_[indices__])
            gen_names = Any[]
            for (i, index) in enumerate(indices)
                if index isa Union{Int,Float64} || index isa Symbol
                    push!(gen_names, index)
                    continue
                end
                gen_name = gensym(Symbol(v, "_index_", i))
                push!(gen_names, gen_name)
                push!(ret_ex.args, MacroTools.@q($(gen_name) = $index))
            end
            return @q($(v)[$(gen_names...)])
        elseif @capture(sub_expr, f_(args__))
            gen_names = Any[]
            for (i, arg) in enumerate(args)
                if arg isa Union{Int,Float64} || arg isa Symbol
                    push!(gen_names, arg)
                    continue
                end
                gen_name = gensym(Symbol(f, "_arg_", i))
                push!(gen_names, gen_name)
                push!(ret_ex.args, @q($(gen_name) = $arg))
            end
            return @q($f($(gen_names...)))
        end
        return sub_expr
    end
    push!(ret_ex.args, ex)
    return ret_ex
end
