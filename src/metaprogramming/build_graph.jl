struct BuildGraph{stage} <: Analysis end
BuildGraph() = BuildGraph{:all}()

__vertex_id_map__ = gensym(:vertex_id_map)
__vertex_counter__ = gensym(:vertex_counter)
__adjacency_matrix__ = gensym(:adjacency_matrix)

function generate_function_expr(
    ::BuildGraph{:all},
    model_def::Expr,
    eval_env::NamedTuple{all_vars},
    loop_iter_bitmaps::Vector{<:BitArray},
) where {all_vars}
    scalars_in_eval_env = filter(
        x -> !(eval_env[x] isa AbstractArray) && !ismissing(eval_env[x]), all_vars
    )
    return @q function __build_graph(
        $__evaluate_env__::NamedTuple{all_vars},
        $__loop_iter_bitmaps__::Vector{<:BitArray},
        $__vertex_id_map__::NamedTuple{all_vars},
    ) where {all_vars}
        $(Expr(:(=), Expr(:tuple, Expr(:parameters, all_vars...)), __evaluate_env__))
        $__vertex_counter__ = 0
        $(
            generate_function_body(
                BuildGraph{1}(), model_def, loop_iter_bitmaps, scalars_in_eval_env, Ref(0)
            )...
        )

        $__adjacency_matrix__ = falses($__vertex_counter__, $__vertex_counter__)
        $__vertex_counter__ = 0
        $(
            generate_function_body(
                BuildGraph{2}(), model_def, loop_iter_bitmaps, scalars_in_eval_env, Ref(0)
            )...
        )
        return $__vertex_id_map__, JuliaBUGS.Graphs.SimpleDiGraph($__adjacency_matrix__)
    end
end

function generate_function_body(
    analysis::BuildGraph{1},
    model_def::Expr,
    loop_iter_bitmaps::Vector{<:BitArray},
    loop_vars::Tuple{Vararg{Symbol}},
    statement_counter::Ref{Int},
)
    args = Any[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            arg = nothing
            arg = if lhs isa Symbol
                if only(loop_iter_bitmaps[statement_counter[]])
                    @q begin
                        $__vertex_counter__ += 1
                        $__vertex_id_map__.($lhs)[] = $__vertex_counter__
                    end
                end
            else
                if any(loop_iter_bitmaps[statement_counter[]])
                    @capture(lhs, v_[idxs__])
                    __indices__ = gensym(:indices)
                    if all(loop_iter_bitmaps[statement_counter[]])
                        @q begin
                            $__vertex_counter__ += 1
                            $__indices__ = ($(idxs...),)
                            if eltype($__indices__) === Int
                                $__vertex_id_map__.$v[$__indices__...] = $__vertex_counter__
                            else
                                $__vertex_id_map__.$v[$__indices__...] .=
                                    $__vertex_counter__
                            end
                        end
                    else
                        @q if $__loop_iter_bitmaps__[$(statement_counter[])][$(loop_vars...)]
                            $__vertex_counter__ += 1
                            $__indices__ = ($(idxs...),)
                            if eltype($__indices__) === Int
                                $__vertex_id_map__.$v[$__indices__...] = $__vertex_counter__
                            else
                                $__vertex_id_map__.$v[$__indices__...] .=
                                    $__vertex_counter__
                            end
                        end
                    end
                end
            end
            if arg !== nothing
                push!(args, arg.args...)
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            arg = nothing
            arg = if lhs isa Symbol
                @q begin
                    $__vertex_counter__ += 1
                    $__vertex_id_map__.$lhs[] = $__vertex_counter__
                end
            else
                @capture(lhs, v_[idxs__])
                __indices__ = gensym(:indices)
                @q begin
                    $__vertex_counter__ += 1
                    $__indices__ = ($(idxs...),)
                    if eltype($__indices__) === Int
                        $__vertex_id_map__.$v[$__indices__...] = $__vertex_counter__
                    else
                        $__vertex_id_map__.$v[$__indices__...] .= $__vertex_counter__
                    end
                end
            end
            if arg !== nothing
                push!(args, arg.args...)
            end
        elseif @capture(
            statement,
            for loop_var_ in loop_iter_
                body_
            end
        )
            loop_body = generate_function_body(
                analysis,
                body,
                loop_iter_bitmaps,
                (loop_vars..., loop_var),
                statement_counter,
            )
            if !isempty(loop_body)
                push!(args, @q(
                    for $loop_var in $loop_iter
                        $(loop_body...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return args
end

function generate_function_body(
    analysis::BuildGraph{2},
    model_def::Expr,
    loop_iter_bitmaps::Vector{<:BitArray},
    loop_vars::Tuple{Vararg{Symbol}},
    statement_counter::Ref{Int},
)
    args = Expr[]
    for statement in model_def.args
        if @capture(statement, lhs_ = rhs_)
            statement_counter[] += 1
            arg = nothing
            arg = if lhs isa Symbol
                if only(loop_iter_bitmaps[statement_counter[]])
                    @q begin
                        $__vertex_counter__ += 1
                        JuliaBUGS.@update_adjacency_matrix($statement, $(loop_vars...))
                    end
                end
            else
                if any(loop_iter_bitmaps[statement_counter[]])
                    @capture(lhs, v_[idxs__])
                    __indices__ = gensym(:indices)
                    if all(loop_iter_bitmaps[statement_counter[]])
                        @q begin
                            $__vertex_counter__ += 1
                            JuliaBUGS.@update_adjacency_matrix($statement, $(loop_vars...))
                        end
                    else
                        @q if $__loop_iter_bitmaps__[$(statement_counter[])][$(loop_vars...)]
                            $__vertex_counter__ += 1
                            JuliaBUGS.@update_adjacency_matrix($statement, $(loop_vars...))
                        end
                    end
                end
            end
            if arg !== nothing
                push!(args, arg.args...)
            end
        elseif @capture(statement, lhs_ ~ rhs_)
            statement_counter[] += 1
            arg = nothing
            arg = if lhs isa Symbol
                @q begin
                    $__vertex_counter__ += 1
                    JuliaBUGS.@update_adjacency_matrix($statement, $(loop_vars...))
                end
            else
                @capture(lhs, v_[idxs__])
                __indices__ = gensym(:indices)
                @q begin
                    $__vertex_counter__ += 1
                    JuliaBUGS.@update_adjacency_matrix($statement, $(loop_vars...))
                end
            end
            if arg !== nothing
                push!(args, arg.args...)
            end
        elseif @capture(
            statement,
            for loop_var_ in loop_iter_
                body_
            end
        )
            loop_body = generate_function_body(
                analysis,
                body,
                loop_iter_bitmaps,
                (loop_vars..., loop_var),
                statement_counter,
            )
            if !isempty(loop_body)
                push!(args, @q(
                    for $loop_var in $loop_iter
                        $(loop_body...)
                    end
                ))
            end
        else
            push!(args, statement)
        end
    end
    return args
end

macro update_adjacency_matrix(statement::Expr, loop_vars::Vararg{Symbol})
    return esc(_update_adjacency_matrix(statement, loop_vars...))
end

function _update_adjacency_matrix(statement::Expr, loop_vars::Vararg{Symbol})
    @capture(statement, lhs_ ~ rhs_) || @capture(statement, lhs_ = rhs_)
    rhs_variables = extract_variable_names_and_numdims(rhs, loop_vars)
    @show loop_vars
    rhs_scalars = [
        (var,) for var in keys(rhs_variables) if getfield(rhs_variables, var) === 0
    ]
    __rhs_vertex_ids__ = gensym(:rhs_vertex_id)
    __rhs_array_vars__ = gensym(:rhs_array_vars)
    __rhs_vertex_id__ = gensym(:rhs_vertex_id)
    return @q begin
        $__rhs_array_vars__ = JuliaBUGS.@rhs_vars($rhs)
        $__rhs_vertex_ids__ = JuliaBUGS.get_vertex_ids(
            $__vertex_id_map__, ($(rhs_scalars...),) ∪ $__rhs_array_vars__
        )
        for $__rhs_vertex_id__ in $__rhs_vertex_ids__
            if $__rhs_vertex_id__ == 0
                print($__rhs_vertex_ids__)
            end
            $__adjacency_matrix__[$__rhs_vertex_id__, $__vertex_counter__] = true
        end
    end
end

# this macro assume the env is populated by the values
macro rhs_vars(expr::Expr)
    expr = serialize_expr(expr)
    return esc(_compute_dependent_variables(expr))
end

function _compute_dependent_variables(expr::Expr)
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

function scalarize(var::Tuple{Symbol,Vararg{Int}})
    return [var]
end
function scalarize(var::Tuple{Symbol,Vararg{Union{Int,UnitRange{Int}}}})
    iter = Iterators.product(var[2:end]...)
    return map(i -> (var[1], i...), iter)
end

function get_vertex_ids(
    vertex_id_map::NamedTuple{all_vars},
    deps::Vector{Tuple{Symbol,Vararg{Union{Int,UnitRange{Int}}}}},
) where {all_vars}
    vertex_ids = Set{Int}()
    for dep in deps
        if length(dep) == 1
            push!(vertex_ids, vertex_id_map[dep[1]][])
        else
            scalarized = scalarize(dep)
            for var in scalarized
                push!(vertex_ids, vertex_id_map[var[1]][var[2:end]...])
            end
        end
    end
    return collect(vertex_ids)
end
