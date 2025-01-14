__precompile__(false)

import Core:
    SimpleVector

if VERSION < v"1.7-DEV"
    import Base:
        show_datatype,
        show_tuple_as_call,
        show_type_name

    show_tuple_as_call(io::IO, name::Symbol, sig::Type; demangle=false, kwargs=nothing, argnames=nothing, qualified=false, hasfirst=true) =
        Base.show_tuple_as_call(io, name, sig, demangle, kwargs, argnames, qualified)

    function show_datatype(io::IO, @nospecialize(x::DataType))
        parameters = x.parameters::SimpleVector
        istuple = x.name === Tuple.name
        n = length(parameters)

        # Print homogeneous tuples with more than 3 elements compactly as NTuple{N, T}
        if istuple && n > 3 && all(i -> (parameters[1] === i), parameters)
            print(io, "NTuple{", n, ", ", parameters[1], "}")
        else
            show_type_name(io, x.name)
            if (n > 0 || istuple) && x !== Tuple
                # Do not print the type parameters for the primary type if we are
                # printing a method signature or type parameter.
                # Always print the type parameter if we are printing the type directly
                # since this information is still useful.
                print(io, '{')
                omitted = get(io, :compacttrace, false) && n > 2
                omitted && (n = 2)
                for i = 1:n
                    p = parameters[i]
                    show(io, p)
                    i < n && print(io, ", ")
                end
                omitted && print(io, ", …")
                print(io, '}')
            end
        end
    end
else
    import Base:
        isgensym,
        show_can_elide,
        show_datatype,
        show_type_name,
        show_typeparams,
        unwrap_unionall

    function show_datatype(io::IO, x::DataType, wheres::Vector{TypeVar}=TypeVar[])
        parameters = x.parameters::SimpleVector
        istuple = x.name === Tuple.name
        n = length(parameters)

        # Print homogeneous tuples with more than 3 elements compactly as NTuple{N, T}
        if istuple
            if n > 3 && all(@nospecialize(i) -> (parameters[1] === i), parameters)
                print(io, "NTuple{", n, ", ")
                show(io, parameters[1])
                print(io, "}")
            elseif n > 2
                print(io, "Tuple{")
                # join(io, params, ", ") params but `show` it
                first = true
                for param in parameters[1:2]
                    first ? (first = false) : print(io, ", ")
                    show(io, param)
                end
                print(io, ", …")
                print(io, "}")
            else
                print(io, "Tuple{")
                # join(io, params, ", ") params but `show` it
                first = true
                for param in parameters
                    first ? (first = false) : print(io, ", ")
                    show(io, param)
                end
                print(io, "}")
            end
        else
            show_type_name(io, x.name)
            show_typeparams(io, parameters, (unwrap_unionall(x.name.wrapper)::DataType).parameters, wheres)
        end
    end

    function show_typeparams(io::IO, env::SimpleVector, orig::SimpleVector, wheres::Vector)
        n = length(env)
        elide = length(wheres)
        function egal_var(p::TypeVar, @nospecialize o)
            return o isa TypeVar &&
                ccall(:jl_types_egal, Cint, (Any, Any), p.ub, o.ub) != 0 &&
                ccall(:jl_types_egal, Cint, (Any, Any), p.lb, o.lb) != 0
        end
        for i = n:-1:1
            p = env[i]
            if p isa TypeVar
                if i == n && egal_var(p, orig[i]) && show_can_elide(p, wheres, elide, env, i)
                    n -= 1
                    elide -= 1
                elseif p.lb === Union{} && isgensym(p.name) && show_can_elide(p, wheres, elide, env, i)
                    elide -= 1
                elseif p.ub === Any && isgensym(p.name) && show_can_elide(p, wheres, elide, env, i)
                    elide -= 1
                end
            end
        end
        if n > 0
            print(io, "{")
            omitted = get(io, :compacttrace, false) && n > 2
            omitted && (n = 2)
            for i = 1:n
                p = env[i]
                if p isa TypeVar
                    if p.lb === Union{} && something(findfirst(@nospecialize(w) -> w === p, wheres), 0) > elide
                        print(io, "<:")
                        show(io, p.ub)
                    elseif p.ub === Any && something(findfirst(@nospecialize(w) -> w === p, wheres), 0) > elide
                        print(io, ">:")
                        show(io, p.lb)
                    else
                        show(io, p)
                    end
                else
                    show(io, p)
                end
                i < n && print(io, ", ")
            end
            omitted && print(io, ", …")
            print(io, "}")
        end
        resize!(wheres, elide)
        nothing
    end
end
