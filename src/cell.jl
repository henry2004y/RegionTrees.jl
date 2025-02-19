mutable struct Cell{Data, N, T, L}
    boundary::HyperRectangle{N, T}
    data::Data
    divisions::SVector{N, T}
    children::Union{TwosArray{N, Cell{Data, N, T, L}, L}, Nothing}
    parent::Union{Cell{Data, N, T, L}, Nothing}
end

function Cell(origin::SVector{N, T}, widths::SVector{N, T}, data::Data=nothing) where {Data, N, T}
    Cell(HyperRectangle(origin, widths), data)
end

@generated function Cell(boundary::HyperRectangle{N, T}, data::Data=nothing) where {Data, N, T}
    L = 2^N
    return quote
        T2 = Base.promote_op(/, T, Int)
        Cell{Data, N, T2, $L}(
            boundary,
            data,
            boundary.origin + boundary.widths / 2,
            nothing,
            nothing)
    end
end

@inline isleaf(cell::Cell) = cell.children === nothing
@inline children(cell::Cell) = cell.children
"Return the parent cell."
@inline parent(cell::Cell) = cell.parent
@inline center(cell::Cell) = center(cell.boundary)
@inline vertices(cell::Cell) = vertices(cell.boundary)

@inline size(::Type{C}) where {C <: Cell} = ()
@inline size(cell::Cell) = size(typeof(cell))

show(io::IO, cell::Cell) = print(io, "Cell: $(cell.boundary)")

@inline getindex(cell::Cell) = cell
@inline getindex(cell::Cell, ::CartesianIndex{0}) = cell
@inline getindex(cell::Cell, I) = getindex(cell.children, I)
@inline getindex(cell::Cell, I...) = getindex(cell.children, I...)

function child_boundary(cell::Cell, indices)
    half_widths = cell.boundary.widths ./ 2
    HyperRectangle(
        cell.boundary.origin .+ (SVector(indices) .- 1) .* half_widths,
        half_widths)
end

@generated function map_children(f::Function, cell::Cell{Data, N, T, L}) where {Data, N, T, L}
    Expr(:call, :TwosArray, Expr(:tuple,
        [:(f(cell, $(I.I))) for I in CartesianIndices(ntuple(_ -> 2, Val(N)))]...))
end


child_indices(cell::Cell{Data, N, T, L}) where {Data, N, T, L} = child_indices(Val(N))

@generated function child_indices(::Val{N}) where N
    Expr(:call, :TwosArray, Expr(:tuple,
        [I.I for I in CartesianIndices(ntuple(_ -> 2, Val(N)))]...))
end

function split!(cell::Cell{Data, N}) where {Data, N}
    split!(cell, (c, I) -> cell.data)
end

@generated function split!(cell::Cell{Data, N}, child_data::AbstractArray) where {Data, N}
    split!_impl(cell, child_data, Val(N))
end

split!(cell::Cell, child_data_function::Function) =
    split!(cell, map_children(child_data_function, cell))

function split!_impl(::Type{C}, child_data, ::Val{N}) where {C <: Cell, N}
    child_exprs = [:(Cell(child_boundary(cell, $(I.I)),
        child_data[$i])) for (i, I) in enumerate(CartesianIndices(ntuple(_ -> 2, Val(N))))]
    quote
        @assert isleaf(cell)
        cell.children = $(Expr(:call, :TwosArray, Expr(:tuple, child_exprs...)))
        for child in cell.children
            child.parent = cell
        end
        cell
    end
end

@generated function findleaf(cell::Cell{Data, N}, point::AbstractVector) where {Data, N}
    quote
        while true
            if isleaf(cell)
                return cell
            end
            length(point) == $N || throw(DimensionMismatch("expected a point of length $N"))
            @inbounds cell = $(Expr(:ref, :cell,
                [:(ifelse(point[$i] >= cell.divisions[$i], 2, 1)) for i in 1:N]...))
        end
    end
end

function findlevel(cell::Cell{Data, N}) where {Data, N}
    #TODO: optimize later!
    root = [p for p in allparents(cell)][end]
    round(Int, log2(root.boundary.widths[1] / cell.boundary.widths[1]))
end

function findneighbor(cell::Cell{Data, N}, direction) where {Data, N}
    @assert isleaf(cell) "Neighbor search is only available for active cells!"
    neighbor = Cell[]
    #TODO: optimize later!
    root = [p for p in allparents(cell)][end]
    (; origin, widths) = cell.boundary
    ϵ = eps(eltype(origin))

    if N == 1
        if direction == :left
            point = [origin[1] - ϵ]
        else
            point = [origin[1] + widths[1] + ϵ]
        end
        leaf = findleaf(root, point)
        if leaf != cell # not domain boundary cell
            push!(neighbor, leaf)
        end
    elseif N == 2
        
        if direction == :left
            point = [origin[1] - ϵ, origin[2] + ϵ]
        elseif direction == :right
            point = [origin[1] + widths[1] + ϵ, origin[2] + ϵ]
        elseif direction == :top
            point = [origin[1] + ϵ, origin[2] + widths[2] + ϵ]
        else
            point = [origin[1] + ϵ, origin[2] - widths[2] - ϵ]
        end

        leaf = findleaf(root, point)

        if leaf.boundary.widths[1] < widths[1] # refined
            if direction == :left
                push!(neighbor, children(leaf.parent)[2:2:4]...)
            elseif direction == :right
                push!(neighbor, children(leaf.parent)[1:2:3]...)
            elseif direction == :top
                push!(neighbor, children(leaf.parent)[1:2]...)
            else
                push!(neighbor, children(leaf.parent)[3:4]...)
            end
        elseif leaf != cell # not domain boundary cell
            push!(neighbor, leaf)
        end
    else # N == 3
        @error "To be implemented!"
    end

    return neighbor
end

function allcells(cell::Cell)
    Channel() do c
        queue = [cell]
        while !isempty(queue)
            current = pop!(queue)
            put!(c, current)
            if !isleaf(current)
                append!(queue, children(current))
            end
        end
    end
end

function allleaves(cell::Cell)
    Channel() do c
        for child in allcells(cell)
            if isleaf(child)
                put!(c, child)
            end
        end
    end
end

function allparents(cell::Cell)
    Channel() do c
        queue = [cell]
        while !isempty(queue)
            current = pop!(queue)
            p = parent(current)
            if !isnothing(p)
                put!(c, p)
                push!(queue, p)
            end
        end
    end
end
