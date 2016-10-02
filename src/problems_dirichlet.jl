# This file is a part of JuliaFEM.
# License is MIT: see https://github.com/JuliaFEM/JuliaFEM.jl/blob/master/LICENSE.md

"""
Problem u(X) = u₀ in Γ(d)
"""
type Dirichlet <: BoundaryProblem
    formulation :: Symbol
    variational :: Bool
    dual_basis :: Bool
    order :: Int
end

function Dirichlet()
    Dirichlet(:incremental, false, false, 1)
end

function get_unknown_field_name(::Type{Dirichlet})
    return "reaction force"
end

function get_formulation_type(problem::Problem{Dirichlet})
    return problem.properties.formulation
end

function assemble!(problem::Problem{Dirichlet}, time::Float64=0.0;
                   auto_initialize=true)
    # FIXME: boilerplate
    if !isempty(problem.assembly)
        warn("Assemble problem $(problem.name): problem.assembly is not empty and assembling, are you sure you know what are you doing?")
    end
    if isempty(problem.elements)
        warn("Assemble problem $(problem.name): problem.elements is empty, no elements in problem?")
    else
        first_element = first(problem.elements)
        unknown_field_name = get_unknown_field_name(problem)
        if !haskey(first_element, unknown_field_name)
            warn("Assemble problem $(problem.name): seems that problem is uninitialized.")
            if auto_initialize
                info("Initializing problem $(problem.name) at time $time automatically.")
                initialize!(problem, time)
            end
        end
    end

    if method_exists(assemble_prehook!, Tuple{typeof(problem), Float64})
        assemble_prehook!(problem, time)
    end

    if problem.properties.variational
        for element in get_elements(problem)
            assemble!(problem.assembly, problem, element, time)
        end
    else # nodal collocation
        field_vals = Dict{Int64, Float64}()
        field_name = get_parent_field_name(problem)
        field_dim = get_unknown_field_dimension(problem)
        for element in get_elements(problem)
            gdofs = get_gdofs(problem, element)
            for i=1:field_dim
                haskey(element, field_name*" $i") || continue
                ldofs = gdofs[i:field_dim:end]
                xis = get_reference_coordinates(typeof(element.properties))
                vals = Float64[]
                for xi in xis
                    g = element(field_name*" $i", xi, time)
                    # u = u_prev + Δu ⇒ Δu = u - u_prev
                    if haskey(element, field_name)
                        g_prev = element(field_name, xi, time)
                        g -= g_prev[i]
                    end
                    push!(vals, g)
                end
                for (dof, g) in zip(ldofs, vals)
                    field_vals[dof] = g
                end
            end
        end
        for (k, v) in field_vals
            push!(problem.assembly.C1, k, k, 1.0)
            push!(problem.assembly.C2, k, k, 1.0)
            push!(problem.assembly.g, k, 1, v)
        end
    end

    if method_exists(assemble_posthook!, Tuple{typeof(problem), Float64})
        assemble_posthook!(problem, time)
    end
end

function assemble!(assembly::Assembly, problem::Problem{Dirichlet},
                   element::Element, time::Float64)

    # get dimension and name of PARENT field
    nnodes = length(element)
    field_dim = get_unknown_field_dimension(problem)
    field_name = get_parent_field_name(problem)
    gdofs = get_gdofs(element, field_dim)
    props = problem.properties

    if problem.properties.dual_basis
        De, Me, Ae = get_dualbasis(element, time)
    else
        Ae = eye(nnodes)
        De = zeros(nnodes, nnodes)
        for ip in get_integration_points(element, props.order)
            N = element(ip, time)
            detJ = element(ip, time, Val{:detJ})
            De += ip.weight*N'*N*detJ
        end
    end

    # left hand side
    for i=1:field_dim
        ldofs = gdofs[i:field_dim:end]
        if haskey(element, field_name*" $i")
            add!(assembly.C1, ldofs, ldofs, De)
            add!(assembly.C2, ldofs, ldofs, De)
        end
    end

    # right hand side
    for ip in get_integration_points(element, props.order)
        detJ = element(ip, time, Val{:detJ})
        w = ip.weight*detJ
        N = element(ip, time)

        for i=1:field_dim
            ldofs = gdofs[i:field_dim:end]
            if haskey(element, field_name*" $i")
                g = element(field_name*" $i", ip, time)
                # u = u_prev + Δu ⇒ Δu = u - u_prev
                if haskey(element, field_name)
                    g_prev = element(field_name, ip, time)
                    g -= g_prev[i]
                end
                add!(assembly.g, ldofs, w*g*Ae*N')
            end
        end

    end

end

#=

function assemble!(assembly::Assembly, problem::Problem{DirichletProblem}, element::Element, time::Real)

    # get dimension and name of PARENT field
    field_dim = problem.parent_field_dim
    field_name = problem.parent_field_name

    gdofs = get_gdofs(element, field_dim)
    for ip in get_integration_points(element, Val{2})
        w = ip.weight
        J = get_jacobian(element, ip, time)
        JT = transpose(J)
        if size(JT, 2) == 1  # plane problem
            w *= norm(JT)
        else
            w *= norm(cross(JT[:,1], JT[:,2]))
        end
        N = element(ip, time)
        A = w*N'*N

        if haskey(element, field_name)
            # add all dimensions at once if defined
            # element["blaa"] = 0.0
            # or
            # element["blaa"] = Vector{Float64}[[0.1, 0.2], [0.3, 0.4]]
            g = element(field_name, ip, time)
            if length(g) != length(N)
                g = g*ones(length(N))
            end
            for i=1:field_dim
                ldofs = gdofs[i:field_dim:end]
                add!(assembly.C1, ldofs, ldofs, A)
                add!(assembly.C2, ldofs, ldofs, A)
            end
            add!(assembly.g, gdofs, w*g*N)
        end

        for i=1:field_dim
            if haskey(element, field_name*" $i")
                g = element(field_name*" $i", ip, time)
                ldofs = gdofs[i:field_dim:end]
                add!(assembly.C1, ldofs, ldofs, A)
                add!(assembly.C2, ldofs, ldofs, A)
                add!(assembly.g, ldofs, w*g*N)
            end
        end
    end
end
=#