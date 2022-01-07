"""
    TwosArray{N, T, L}

Represents a static array with N dimensions whose size is exactly 2 along each dimension.
This makes templating on the number of dimensions easier than with a regular SArray.
"""
struct TwosArray{N, T, L} <: StaticArray{NTuple{N, 2}, T, N}
    data::NTuple{L, T}
end

function TwosArray(x::NTuple{L, T}) where {L, T}
    @assert log2(L) == round(log2(L)) "L must equal 2^N for integer N"
    N = Int(log2(L))
    TwosArray{N, T, L}(x)
end

getindex(b::TwosArray, i::Int) = b.data[i]

similar_type(::Type{TwosArray{N, T, L}}, ::Type{T2}) where {N, T, L, T2} = TwosArray{N, T2, L}
