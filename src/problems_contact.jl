# This file is a part of JuliaFEM.
# License is MIT: see https://github.com/JuliaFEM/JuliaFEM.jl/blob/master/LICENSE.md

"""

Parameters
----------
distval
    a charasteristic measure to skip element pair, 0..5 => near, 10+ => far
    5 means that distance of slave element midpoint and point to project
    is 5 times larger than length of element
"""
type Contact <: BoundaryProblem
    dimension :: Int
    rotate_normals :: Bool
    finite_sliding :: Bool
    friction :: Bool
    dual_basis :: Bool
    use_forwarddiff :: Bool
    forwarddiff_assemble_in_pieces :: Bool
    minimum_active_set_size :: Int
    distval :: Float64
    remove_from_set :: Bool # allow removal of non-potential contact pairs
    allow_quads :: Bool
    remove_nodes :: Vector{Int}
    always_in_contact :: Bool
    update_contact_pairing :: Bool
    store_fields :: Vector{AbstractString}
end

function Contact()
    default_fields = ["element area", "contact area", "weighted gap",
        "contact pressure", "active nodes", "inactive nodes", "stick nodes",
        "slip nodes", "complementarity condition", "contact error"]
    return Contact(
        -1,      # dimension
        false,   # rotate_normals
        false,   # finite_sliding
        false,   # friciton
        true,    # dual basis
        false,   # use forwarddiff
        false,   # when using forwarddiff, assemble interface in pieces
        0,       # minimum active set size
        5.0,     # distance value for contact detection
        false,   # allow removal of non-potential contact pairs
        false,   # allow quadrangles in contact discretization
        [],      # remove these nodes always from set
        false,   # mainly for debugging, do not remove inactive nodes
        true,    # update contact pairing on each loop
        default_fields)
end

function get_unknown_field_name(problem::Problem{Contact})
    return "reaction force"
end

function get_formulation_type(problem::Problem{Contact})
    if problem.properties.use_forwarddiff
        return :forwarddiff
    else
        return :incremental
    end
end

function assemble!(problem::Problem{Contact}, time::Real)
    if problem.properties.dimension == -1
        problem.properties.dimension = dim = size(first(problem.elements), 1)
        info("assuming dimension of mesh tie surface is $dim")
        info("if this is wrong set is manually using problem.properties.dimension")
    end
    dimension = Val{problem.properties.dimension}
    finite_sliding = Val{problem.properties.finite_sliding}
    friction = Val{problem.properties.friction}
    use_forwarddiff = Val{problem.properties.use_forwarddiff}
    assemble!(problem, time, dimension, finite_sliding, friction, use_forwarddiff)
end

typealias ContactElements2D Union{Seg2}
