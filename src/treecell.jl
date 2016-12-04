type Cell{Data, N, T, L}
    boundary::HyperRectangle{N, T}
    data::Data
    divisions::SVector{N, T}
    children::Nullable{TwosArray{N, Cell{Data, N, T, L}, L}}
    parent::Nullable{Cell{Data, N, T, L}}
end

function Cell{Data, N, T}(origin::SVector{N, T}, widths::SVector{N, T}, data::Data=nothing)
    Cell(HyperRectangle(origin, widths), data)
end

@generated function Cell{Data, N, T}(boundary::HyperRectangle{N, T}, data::Data=nothing)
    L = 2^N
    :(Cell{Data, N, T, $L}(boundary, 
                           data, boundary.origin + boundary.widths / 2,
                           Nullable{TwosArray{N, T, $L}}(),
                           Nullable{Cell{Data, N, T, $L}}()))
end

isleaf(cell::Cell) = isnull(cell.children)
children(cell::Cell) = get(cell.children)
parent(cell::Cell) = get(cell.parent)

size{C <: Cell}(::Type{C}) = ()
@inline size(cell::Cell) = size(typeof(cell))

show(io::IO, cell::Cell) = print(io, "Cell: $(cell.boundary)")

getindex(cell::Cell) = cell
getindex(cell::Cell, ::CartesianIndex{0}) = cell
getindex(cell::Cell, I) = getindex(get(cell.children), I)
getindex(cell::Cell, I...) = getindex(get(cell.children), I...)

function child_boundary(cell::Cell, indices)
    HyperRectangle(cell.boundary.origin + 0.5 * (SVector(indices) - 1) .* cell.boundary.widths,
                   cell.boundary.widths / 2)
end

@generated function map_children{Data, N, T, L}(f::Function, cell::Cell{Data, N, T, L})
    Expr(:call, :TwosArray, Expr(:tuple,
        [:(f(cell, $(I.I))) for I in CartesianRange(ntuple(_ -> 2, Val{N}))]...))
end


child_indices{Data, N, T, L}(cell::Cell{Data, N, T, L}) = child_indices(Val{N})

@generated function child_indices{N}(::Type{Val{N}})
    Expr(:call, :TwosArray, Expr(:tuple, 
        [I.I for I in CartesianRange(ntuple(_ -> 2, Val{N}))]...))
end

@generated function split!(cell::Cell, child_data::AbstractArray)
    split!_impl(cell, child_data)
end

function split!_impl{Data, N, T, L}(::Type{Cell{Data, N, T, L}}, child_data)
    child_exprs = [:(Cell(child_boundary(cell, $(I.I)),
                          child_data[$i])) for (i, I) in
                    enumerate(CartesianRange(ntuple(_ -> 2, Val{N})))]
    quote
        @assert isleaf(cell)
        cell.children = $(Expr(:call, :TwosArray, Expr(:tuple, child_exprs...)))
        for child in get(cell.children)
            child.parent = cell
        end
        cell
    end
end

@generated function findleaf{Data, N}(cell::Cell{Data, N}, point::AbstractVector)
    quote
        while true
            if isleaf(cell)
                return cell
            end
            cell = $(Expr(:ref, :cell, [:(point[$i] >= cell.divisions[$i] ? 2 : 1) for i in 1:N]...))
        end
    end
end
