# This file is a part of Julia. License is MIT: https://julialang.org/license

## array.jl: Dense arrays

"""
    DimensionMismatch([msg])

The objects called do not have matching dimensionality. Optional argument `msg` is a
descriptive error string.
"""
struct DimensionMismatch <: Exception
    msg::AbstractString
end
DimensionMismatch() = DimensionMismatch("")

## Type aliases for convenience ##
"""
    AbstractVector{T}

Supertype for one-dimensional arrays (or array-like types) with
elements of type `T`. Alias for [`AbstractArray{T,1}`](@ref).
"""
const AbstractVector{T} = AbstractArray{T,1}

"""
    AbstractMatrix{T}

Supertype for two-dimensional arrays (or array-like types) with
elements of type `T`. Alias for [`AbstractArray{T,2}`](@ref).
"""
const AbstractMatrix{T} = AbstractArray{T,2}

"""
    AbstractVecOrMat{T}

Union type of [`AbstractVector{T}`](@ref) and [`AbstractMatrix{T}`](@ref).
"""
const AbstractVecOrMat{T} = Union{AbstractVector{T}, AbstractMatrix{T}}
const RangeIndex = Union{<:BitInteger, AbstractRange{<:BitInteger}}
const DimOrInd = Union{Integer, AbstractUnitRange}
const IntOrInd = Union{Int, AbstractUnitRange}
const DimsOrInds{N} = NTuple{N,DimOrInd}
const NeedsShaping = Union{Tuple{Integer,Vararg{Integer}}, Tuple{OneTo,Vararg{OneTo}}}

"""
    Array{T,N} <: AbstractArray{T,N}

`N`-dimensional dense array with elements of type `T`.
"""
Array

"""
    Vector{T} <: AbstractVector{T}

One-dimensional dense array with elements of type `T`, often used to represent
a mathematical vector. Alias for [`Array{T,1}`](@ref).

See also [`empty`](@ref), [`similar`](@ref) and [`zero`](@ref) for creating vectors.
"""
const Vector{T} = Array{T,1}

"""
    Matrix{T} <: AbstractMatrix{T}

Two-dimensional dense array with elements of type `T`, often used to represent
a mathematical matrix. Alias for [`Array{T,2}`](@ref).

See also [`fill`](@ref), [`zeros`](@ref), [`undef`](@ref) and [`similar`](@ref)
for creating matrices.
"""
const Matrix{T} = Array{T,2}

"""
    VecOrMat{T}

Union type of [`Vector{T}`](@ref) and [`Matrix{T}`](@ref) which allows functions to accept either a Matrix or a Vector.

# Examples
```jldoctest
julia> Vector{Float64} <: VecOrMat{Float64}
true

julia> Matrix{Float64} <: VecOrMat{Float64}
true

julia> Array{Float64, 3} <: VecOrMat{Float64}
false
```
"""
const VecOrMat{T} = Union{Vector{T}, Matrix{T}}

"""
    DenseArray{T, N} <: AbstractArray{T,N}

`N`-dimensional dense array with elements of type `T`.
The elements of a dense array are stored contiguously in memory.
"""
DenseArray

"""
    DenseVector{T}

One-dimensional [`DenseArray`](@ref) with elements of type `T`. Alias for `DenseArray{T,1}`.
"""
const DenseVector{T} = DenseArray{T,1}

"""
    DenseMatrix{T}

Two-dimensional [`DenseArray`](@ref) with elements of type `T`. Alias for `DenseArray{T,2}`.
"""
const DenseMatrix{T} = DenseArray{T,2}

"""
    DenseVecOrMat{T}

Union type of [`DenseVector{T}`](@ref) and [`DenseMatrix{T}`](@ref).
"""
const DenseVecOrMat{T} = Union{DenseVector{T}, DenseMatrix{T}}

## Basic functions ##

"""
    @_safeindex

This internal macro converts:
- `getindex(xs::Tuple, i::Int)` -> `__safe_getindex(xs, i)`
- `setindex!(xs::Vector{T}, x, i::Int)` -> `__safe_setindex!(xs, x, i)`
to tell the compiler that indexing operations within the applied expression are always
inbounds and do not need to taint `:consistent` and `:nothrow`.
"""
macro _safeindex(ex)
    return esc(_safeindex(ex))
end
function _safeindex(ex)
    isa(ex, Expr) || return ex
    if ex.head === :(=)
        lhs = ex.args[1]
        if isa(lhs, Expr) && lhs.head === :ref # xs[i] = x
            rhs = ex.args[2]
            xs = lhs.args[1]
            args = Vector{Any}(undef, length(lhs.args)-1)
            for i = 2:length(lhs.args)
                args[i-1] = _safeindex(lhs.args[i])
            end
            return Expr(:call, GlobalRef(@__MODULE__, :__safe_setindex!), xs, _safeindex(rhs), args...)
        end
    elseif ex.head === :ref # xs[i]
        return Expr(:call, GlobalRef(@__MODULE__, :__safe_getindex), ex.args...)
    end
    args = Vector{Any}(undef, length(ex.args))
    for i = 1:length(ex.args)
        args[i] = _safeindex(ex.args[i])
    end
    return Expr(ex.head, args...)
end

vect() = Vector{Any}()
function vect(X::T...) where T
    @_terminates_locally_meta
    vec = Vector{T}(undef, length(X))
    @_safeindex for i = 1:length(X)
        vec[i] = X[i]
    end
    return vec
end

"""
    vect(X...)

Create a [`Vector`](@ref) with element type computed from the `promote_typeof` of the argument,
containing the argument list.

# Examples
```jldoctest
julia> a = Base.vect(UInt8(1), 2.5, 1//2)
3-element Vector{Float64}:
 1.0
 2.5
 0.5
```
"""
function vect(X...)
    T = promote_typeof(X...)
    return T[X...]
end

asize_from(a::Array, n) = n > ndims(a) ? () : (size(a,n), asize_from(a, n+1)...)

allocatedinline(@nospecialize T::Type) = (@_total_meta; ccall(:jl_stored_inline, Cint, (Any,), T) != Cint(0))

"""
    Base.isbitsunion(::Type{T})

Return whether a type is an "is-bits" Union type, meaning each type included in a Union is [`isbitstype`](@ref).

# Examples
```jldoctest
julia> Base.isbitsunion(Union{Float64, UInt8})
true

julia> Base.isbitsunion(Union{Float64, String})
false
```
"""
isbitsunion(u::Type) = u isa Union && allocatedinline(u)

function _unsetindex!(A::Array, i::Int)
    @inline
    @boundscheck checkbounds(A, i)
    @inbounds _unsetindex!(memoryref(A.ref, i))
    return A
end


# TODO: deprecate this (aligned_sizeof and/or elsize and/or sizeof(Some{T}) are more correct)
elsize(::Type{A}) where {T,A<:Array{T}} = aligned_sizeof(T)
function elsize(::Type{Ptr{T}}) where T
    # this only must return something valid for values which satisfy is_valid_intrinsic_elptr(T),
    # which includes Any and most concrete datatypes
    T === Any && return sizeof(Ptr{Any})
    T isa DataType || sizeof(Any) # throws
    return LLT_ALIGN(Core.sizeof(T), datatype_alignment(T))
end
elsize(::Type{Union{}}, slurp...) = 0

sizeof(a::Array) = length(a) * elsize(typeof(a)) # n.b. this ignores bitsunion bytes, as a historical fact

function isassigned(a::Array, i::Int...)
    @inline
    @_noub_if_noinbounds_meta
    @boundscheck checkbounds(Bool, a, i...) || return false
    ii = _sub2ind(size(a), i...)
    return @inbounds isassigned(memoryrefnew(a.ref, ii, false))
end

function isassigned(a::Vector, i::Int) # slight compiler simplification for the most common case
    @inline
    @_noub_if_noinbounds_meta
    @boundscheck checkbounds(Bool, a, i) || return false
    return @inbounds isassigned(memoryrefnew(a.ref, i, false))
end


## copy ##

"""
    unsafe_copyto!(dest::Ptr{T}, src::Ptr{T}, N)

Copy `N` elements from a source pointer to a destination, with no checking. The size of an
element is determined by the type of the pointers.

The `unsafe` prefix on this function indicates that no validation is performed on the
pointers `dest` and `src` to ensure that they are valid. Incorrect usage may corrupt or
segfault your program, in the same manner as C.
"""
function unsafe_copyto!(dest::Ptr{T}, src::Ptr{T}, n) where T
    # Do not use this to copy data between pointer arrays.
    # It can't be made safe no matter how carefully you checked.
    memmove(dest, src, n * aligned_sizeof(T))
    return dest
end

"""
    unsafe_copyto!(dest::Array, doffs, src::Array, soffs, n)

Copy `n` elements from a source array to a destination, starting at the linear index `soffs` in the
source and `doffs` in the destination (1-indexed).

The `unsafe` prefix on this function indicates that no validation is performed to ensure
that n is inbounds on either array. Incorrect usage may corrupt or segfault your program, in
the same manner as C.
"""
function unsafe_copyto!(dest::Array, doffs, src::Array, soffs, n)
    n == 0 && return dest
    unsafe_copyto!(memoryref(dest.ref, doffs), memoryref(src.ref, soffs), n)
    return dest
end

"""
    copyto!(dest, doffs, src, soffs, n)

Copy `n` elements from collection `src` starting at the linear index `soffs`, to array `dest` starting at
the index `doffs`. Return `dest`.
"""
copyto!(dest::Array, doffs::Integer, src::Array, soffs::Integer, n::Integer) = _copyto_impl!(dest, doffs, src, soffs, n)
copyto!(dest::Array, doffs::Integer, src::Memory, soffs::Integer, n::Integer) = _copyto_impl!(dest, doffs, src, soffs, n)
copyto!(dest::Memory, doffs::Integer, src::Array, soffs::Integer, n::Integer) = _copyto_impl!(dest, doffs, src, soffs, n)

# this is only needed to avoid possible ambiguities with methods added in some packages
copyto!(dest::Array{T}, doffs::Integer, src::Array{T}, soffs::Integer, n::Integer) where {T} = _copyto_impl!(dest, doffs, src, soffs, n)

function _copyto_impl!(dest::Union{Array,Memory}, doffs::Integer, src::Union{Array,Memory}, soffs::Integer, n::Integer)
    n == 0 && return dest
    n > 0 || _throw_argerror("Number of elements to copy must be non-negative.")
    @boundscheck checkbounds(dest, doffs:doffs+n-1)
    @boundscheck checkbounds(src, soffs:soffs+n-1)
    @inbounds let dest = memoryref(dest isa Array ? getfield(dest, :ref) : dest, doffs),
                  src = memoryref(src isa Array ? getfield(src, :ref) : src, soffs)
        unsafe_copyto!(dest, src, n)
    end
    return dest
end


# Outlining this because otherwise a catastrophic inference slowdown
# occurs, see discussion in #27874.
# It is also mitigated by using a constant string.
_throw_argerror(s) = (@noinline; throw(ArgumentError(s)))

_copyto2arg!(dest, src) = copyto!(dest, firstindex(dest), src, firstindex(src), length(src))

copyto!(dest::Array, src::Array) = _copyto2arg!(dest, src)
copyto!(dest::Array, src::Memory) = _copyto2arg!(dest, src)
copyto!(dest::Memory, src::Array) = _copyto2arg!(dest, src)

# also to avoid ambiguities in packages
copyto!(dest::Array{T}, src::Array{T}) where {T} = _copyto2arg!(dest, src)
copyto!(dest::Array{T}, src::Memory{T}) where {T} = _copyto2arg!(dest, src)
copyto!(dest::Memory{T}, src::Array{T}) where {T} = _copyto2arg!(dest, src)

# N.B: This generic definition in for multidimensional arrays is here instead of
# `multidimensional.jl` for bootstrapping purposes.
"""
    fill!(A, x)

Fill array `A` with the value `x`. If `x` is an object reference, all elements will refer to
the same object. `fill!(A, Foo())` will return `A` filled with the result of evaluating
`Foo()` once.

# Examples
```jldoctest
julia> A = zeros(2,3)
2Ã—3 Matrix{Float64}:
 0.0  0.0  0.0
 0.0  0.0  0.0

julia> fill!(A, 2.)
2Ã—3 Matrix{Float64}:
 2.0  2.0  2.0
 2.0  2.0  2.0

julia> a = [1, 1, 1]; A = fill!(Vector{Vector{Int}}(undef, 3), a); a[1] = 2; A
3-element Vector{Vector{Int64}}:
 [2, 1, 1]
 [2, 1, 1]
 [2, 1, 1]

julia> x = 0; f() = (global x += 1; x); fill!(Vector{Int}(undef, 3), f())
3-element Vector{Int64}:
 1
 1
 1
```
"""
function fill!(A::AbstractArray{T}, x) where T
    @inline
    xT = x isa T ? x : convert(T, x)::T
    return _fill!(A, xT)
end
function _fill!(A::AbstractArray{T}, x::T) where T
    for i in eachindex(A)
        A[i] = x
    end
    return A
end

"""
    copy(x)

Create a shallow copy of `x`: the outer structure is copied, but not all internal values.
For example, copying an array produces a new array with identically-same elements as the
original.

See also [`copy!`](@ref Base.copy!), [`copyto!`](@ref), [`deepcopy`](@ref).
"""
copy

@eval function copy(a::Array)
    # `copy` only throws when the size exceeds the max allocation size,
    # but since we're copying an existing array, we're guaranteed that this will not happen.
    @_nothrow_meta
    ref = a.ref
    newmem = typeof(ref.mem)(undef, length(a))
    @inbounds unsafe_copyto!(memoryref(newmem), ref, length(a))
    return $(Expr(:new, :(typeof(a)), :(memoryref(newmem)), :(a.size)))
end

# a mutating version of copyto! that results in dst aliasing src afterwards
function _take!(dst::Array{T,N}, src::Array{T,N}) where {T,N}
    if getfield(dst, :ref) !== getfield(src, :ref)
        setfield!(dst, :ref, getfield(src, :ref))
    end
    if getfield(dst, :size) !== getfield(src, :size)
        setfield!(dst, :size, getfield(src, :size))
    end
    return dst
end

## Constructors ##

similar(a::Vector{T}) where {T}                    = Vector{T}(undef, size(a,1))
similar(a::Matrix{T}) where {T}                    = Matrix{T}(undef, size(a,1), size(a,2))
similar(a::Vector{T}, S::Type) where {T}           = Vector{S}(undef, size(a,1))
similar(a::Matrix{T}, S::Type) where {T}           = Matrix{S}(undef, size(a,1), size(a,2))
similar(a::Array{T}, m::Int) where {T}              = Vector{T}(undef, m)
similar(a::Array, T::Type, dims::Dims{N}) where {N} = Array{T,N}(undef, dims)
similar(a::Array{T}, dims::Dims{N}) where {T,N}     = Array{T,N}(undef, dims)
similar(::Type{Array{T,N}}, dims::Dims) where {T,N} = similar(Array{T}, dims)

# T[x...] constructs Array{T,1}
"""
    getindex(type[, elements...])

Construct a 1-d array of the specified type. This is usually called with the syntax
`Type[]`. Element values can be specified using `Type[a,b,c,...]`.

# Examples
```jldoctest
julia> Int8[1, 2, 3]
3-element Vector{Int8}:
 1
 2
 3

julia> getindex(Int8, 1, 2, 3)
3-element Vector{Int8}:
 1
 2
 3
```
"""
function getindex(::Type{T}, vals...) where T
    @inline
    @_effect_free_terminates_locally_meta
    a = Vector{T}(undef, length(vals))
    if vals isa NTuple
        @_safeindex for i in 1:length(vals)
            a[i] = vals[i]
        end
    else
        # use afoldl to avoid type instability inside loop
        afoldl(1, vals...) do i, v
            @inbounds a[i] = v
            return i + 1
        end
    end
    return a
end

function getindex(::Type{Any}, @nospecialize vals...)
    @_effect_free_terminates_locally_meta
    a = Vector{Any}(undef, length(vals))
    @_safeindex for i = 1:length(vals)
        a[i] = vals[i]
    end
    return a
end
getindex(::Type{Any}) = Vector{Any}()

function fill!(a::Union{Array{UInt8}, Array{Int8}}, x::Integer)
    ref = a.ref
    t = @_gc_preserve_begin ref
    p = unsafe_convert(Ptr{Cvoid}, ref)
    memset(p, x isa eltype(a) ? x : convert(eltype(a), x), length(a) % UInt)
    @_gc_preserve_end t
    return a
end

to_dim(d::Integer) = d
to_dim(d::OneTo) = last(d)

"""
    fill(value, dims::Tuple)
    fill(value, dims...)

Create an array of size `dims` with every location set to `value`.

For example, `fill(1.0, (5,5))` returns a 5Ã—5 array of floats,
with `1.0` in every location of the array.

The dimension lengths `dims` may be specified as either a tuple or a sequence of arguments.
An `N`-length tuple or `N` arguments following the `value` specify an `N`-dimensional
array. Thus, a common idiom for creating a zero-dimensional array with its only location
set to `x` is `fill(x)`.

Every location of the returned array is set to (and is thus [`===`](@ref) to)
the `value` that was passed; this means that if the `value` is itself modified,
all elements of the `fill`ed array will reflect that modification because they're
_still_ that very `value`. This is of no concern with `fill(1.0, (5,5))` as the
`value` `1.0` is immutable and cannot itself be modified, but can be unexpected
with mutable values like â€” most commonly â€” arrays.  For example, `fill([], 3)`
places _the very same_ empty array in all three locations of the returned vector:

```jldoctest
julia> v = fill([], 3)
3-element Vector{Vector{Any}}:
 []
 []
 []

julia> v[1] === v[2] === v[3]
true

julia> value = v[1]
Any[]

julia> push!(value, 867_5309)
1-element Vector{Any}:
 8675309

julia> v
3-element Vector{Vector{Any}}:
 [8675309]
 [8675309]
 [8675309]
```

To create an array of many independent inner arrays, use a [comprehension](@ref man-comprehensions) instead.
This creates a new and distinct array on each iteration of the loop:

```jldoctest
julia> v2 = [[] for _ in 1:3]
3-element Vector{Vector{Any}}:
 []
 []
 []

julia> v2[1] === v2[2] === v2[3]
false

julia> push!(v2[1], 8675309)
1-element Vector{Any}:
 8675309

julia> v2
3-element Vector{Vector{Any}}:
 [8675309]
 []
 []
```

See also [`fill!`](@ref), [`zeros`](@ref), [`ones`](@ref), [`similar`](@ref).

# Examples
```jldoctest
julia> fill(1.0, (2,3))
2Ã—3 Matrix{Float64}:
 1.0  1.0  1.0
 1.0  1.0  1.0

julia> fill(42)
0-dimensional Array{Int64, 0}:
42

julia> A = fill(zeros(2), 2) # sets both elements to the same [0.0, 0.0] vector
2-element Vector{Vector{Float64}}:
 [0.0, 0.0]
 [0.0, 0.0]

julia> A[1][1] = 42; # modifies the filled value to be [42.0, 0.0]

julia> A # both A[1] and A[2] are the very same vector
2-element Vector{Vector{Float64}}:
 [42.0, 0.0]
 [42.0, 0.0]
```
"""
function fill end

fill(v, dims::DimOrInd...) = fill(v, dims)
fill(v, dims::NTuple{N, Union{Integer, OneTo}}) where {N} = fill(v, map(to_dim, dims))
fill(v, dims::NTuple{N, Integer}) where {N} = (a=Array{typeof(v),N}(undef, dims); fill!(a, v); a)
fill(v, dims::NTuple{N, DimOrInd}) where {N} = (a=similar(Array{typeof(v),N}, dims); fill!(a, v); a)
fill(v, dims::Tuple{}) = (a=Array{typeof(v),0}(undef, dims); fill!(a, v); a)

"""
    zeros([T=Float64,] dims::Tuple)
    zeros([T=Float64,] dims...)

Create an `Array`, with element type `T`, of all zeros with size specified by `dims`.
See also [`fill`](@ref), [`ones`](@ref), [`zero`](@ref).

# Examples
```jldoctest
julia> zeros(1)
1-element Vector{Float64}:
 0.0

julia> zeros(Int8, 2, 3)
2Ã—3 Matrix{Int8}:
 0  0  0
 0  0  0
```
"""
function zeros end

"""
    ones([T=Float64,] dims::Tuple)
    ones([T=Float64,] dims...)

Create an `Array`, with element type `T`, of all ones with size specified by `dims`.
See also [`fill`](@ref), [`zeros`](@ref).

# Examples
```jldoctest
julia> ones(1,2)
1Ã—2 Matrix{Float64}:
 1.0  1.0

julia> ones(ComplexF64, 2, 3)
2Ã—3 Matrix{ComplexF64}:
 1.0+0.0im  1.0+0.0im  1.0+0.0im
 1.0+0.0im  1.0+0.0im  1.0+0.0im
```
"""
function ones end

for (fname, felt) in ((:zeros, :zero), (:ones, :one))
    @eval begin
        $fname(dims::DimOrInd...) = $fname(dims)
        $fname(::Type{T}, dims::DimOrInd...) where {T} = $fname(T, dims)
        $fname(dims::Tuple{Vararg{DimOrInd}}) = $fname(Float64, dims)
        $fname(::Type{T}, dims::NTuple{N, Union{Integer, OneTo}}) where {T,N} = $fname(T, map(to_dim, dims))
        function $fname(::Type{T}, dims::NTuple{N, Integer}) where {T,N}
            a = Array{T,N}(undef, dims)
            fill!(a, $felt(T))
            return a
        end
        function $fname(::Type{T}, dims::Tuple{}) where {T}
            a = Array{T}(undef)
            fill!(a, $felt(T))
            return a
        end
        function $fname(::Type{T}, dims::NTuple{N, DimOrInd}) where {T,N}
            a = similar(Array{T,N}, dims)
            fill!(a, $felt(T))
            return a
        end
    end
end

## Conversions ##

convert(::Type{T}, a::AbstractArray) where {T<:Array} = a isa T ? a : T(a)::T

promote_rule(a::Type{Array{T,n}}, b::Type{Array{S,n}}) where {T,n,S} = el_same(promote_type(T,S), a, b)

## Constructors ##

# constructors should make copies
Array{T,N}(x::AbstractArray{S,N})         where {T,N,S} = copyto_axcheck!(Array{T,N}(undef, size(x)), x)
AbstractArray{T,N}(A::AbstractArray{S,N}) where {T,N,S} = copyto_axcheck!(similar(A,T), A)

## copying iterators to containers

"""
    collect(element_type, collection)

Return an `Array` with the given element type of all items in a collection or iterable.
The result has the same shape and number of dimensions as `collection`.

# Examples
```jldoctest
julia> collect(Float64, 1:2:5)
3-element Vector{Float64}:
 1.0
 3.0
 5.0
```
"""
collect(::Type{T}, itr) where {T} = _collect(T, itr, IteratorSize(itr))

_collect(::Type{T}, itr, isz::Union{HasLength,HasShape}) where {T} =
    copyto!(_array_for_inner(T, isz, _similar_shape(itr, isz)), itr)
function _collect(::Type{T}, itr, isz::SizeUnknown) where T
    a = Vector{T}()
    for x in itr
        push!(a, x)
    end
    return a
end

# make a collection similar to `c` and appropriate for collecting `itr`
_similar_for(c, ::Type{T}, itr, isz, shp) where {T} = similar(c, T)

_similar_shape(itr, ::SizeUnknown) = nothing
_similar_shape(itr, ::HasLength) = length(itr)::Integer
_similar_shape(itr, ::HasShape) = axes(itr)

_similar_for(c::AbstractArray, ::Type{T}, itr, ::SizeUnknown, ::Nothing) where {T} =
    similar(c, T, 0)
_similar_for(c::AbstractArray, ::Type{T}, itr, ::HasLength, len::Integer) where {T} =
    similar(c, T, len)
_similar_for(c::AbstractArray, ::Type{T}, itr, ::HasShape, axs) where {T} =
    similar(c, T, axs)

# make a collection appropriate for collecting `itr::Generator`
_array_for_inner(::Type{T}, ::SizeUnknown, ::Nothing) where {T} = Vector{T}(undef, 0)
_array_for_inner(::Type{T}, ::HasLength, len::Integer) where {T} = Vector{T}(undef, Int(len))
_array_for_inner(::Type{T}, ::HasShape{N}, axs) where {T,N} = similar(Array{T,N}, axs)

# used by syntax lowering for simple typed comprehensions
_array_for(::Type{T}, itr, isz) where {T} = _array_for_inner(T, isz, _similar_shape(itr, isz))


"""
    collect(iterator)

Return an `Array` of all items in a collection or iterator. For dictionaries, returns
a `Vector` of `key=>value` [Pair](@ref Pair)s. If the argument is array-like or is an iterator
with the [`HasShape`](@ref IteratorSize) trait, the result will have the same shape
and number of dimensions as the argument.

Used by [comprehensions](@ref man-comprehensions) to turn a [generator expression](@ref man-generators)
into an `Array`. Thus, *on generators*, the square-brackets notation may be used instead of calling `collect`,
see second example.

The element type of the returned array is based on the types of the values collected. However, if the
iterator is empty then the element type of the returned (empty) array is determined by type inference.

# Examples

Collect items from a `UnitRange{Int64}` collection:

```jldoctest
julia> collect(1:3)
3-element Vector{Int64}:
 1
 2
 3
```

Collect items from a generator (same output as `[x^2 for x in 1:3]`):

```jldoctest
julia> collect(x^2 for x in 1:3)
3-element Vector{Int64}:
 1
 4
 9
```

Collecting an empty iterator where the result type depends on type inference:

```jldoctest
julia> [rand(Bool) ? 1 : missing for _ in []]
Union{Missing, Int64}[]
```

When the iterator is non-empty, the result type depends only on values:

```julia-repl
julia> [rand(Bool) ? 1 : missing for _ in [""]]
1-element Vector{Int64}:
 1
```
"""
collect(itr) = _collect(1:1 #= Array =#, itr, IteratorEltype(itr), IteratorSize(itr))

collect(A::AbstractArray) = _collect_indices(axes(A), A)

collect_similar(cont, itr) = _collect(cont, itr, IteratorEltype(itr), IteratorSize(itr))

_collect(cont, itr, ::HasEltype, isz::Union{HasLength,HasShape}) =
    copyto!(_similar_for(cont, eltype(itr), itr, isz, _similar_shape(itr, isz)), itr)

function _collect(cont, itr, ::HasEltype, isz::SizeUnknown)
    a = _similar_for(cont, eltype(itr), itr, isz, nothing)
    for x in itr
        push!(a,x)
    end
    return a
end

function _collect_indices(::Tuple{}, A)
    dest = Array{eltype(A),0}(undef)
    isempty(A) && return dest
    return copyto_unaliased!(IndexStyle(dest), dest, IndexStyle(A), A)
end
function _collect_indices(indsA::Tuple{Vararg{OneTo}}, A)
    dest = Array{eltype(A)}(undef, length.(indsA))
    isempty(A) && return dest
    return copyto_unaliased!(IndexStyle(dest), dest, IndexStyle(A), A)
end
function _collect_indices(indsA, A)
    B = Array{eltype(A)}(undef, length.(indsA))
    copyto!(B, CartesianIndices(axes(B)), A, CartesianIndices(indsA))
end

# NOTE: this function is not meant to be called, only inferred, for the
# purpose of bounding the types of values generated by an iterator.
function _iterator_upper_bound(itr)
    x = iterate(itr)
    while x !== nothing
        val = getfield(x, 1)
        if inferencebarrier(nothing)
            return val
        end
        x = iterate(itr, getfield(x, 2))
    end
    throw(nothing)
end

# define this as a macro so that the call to Core.Compiler
# gets inlined into the caller before recursion detection
# gets a chance to see it, so that recursive calls to the caller
# don't trigger the inference limiter
macro default_eltype(itr)
    I = esc(itr)
    return quote
        if $I isa Generator && ($I).f isa Type
            T = ($I).f
        else
            T = Base._return_type(_iterator_upper_bound, Tuple{typeof($I)})
        end
        promote_typejoin_union(T)
    end
end

function collect(itr::Generator)
    isz = IteratorSize(itr.iter)
    et = @default_eltype(itr)
    if isa(isz, SizeUnknown)
        return grow_to!(Vector{et}(), itr)
    else
        shp = _similar_shape(itr, isz)
        y = iterate(itr)
        if y === nothing
            return _array_for_inner(et, isz, shp)
        end
        v1, st = y
        dest = _array_for_inner(typeof(v1), isz, shp)
        # The typeassert gives inference a helping hand on the element type and dimensionality
        # (work-around for #28382)
        etâ€² = et <: Type ? Type : et
        RT = dest isa AbstractArray ? AbstractArray{<:etâ€², ndims(dest)} : Any
        collect_to_with_first!(dest, v1, itr, st)::RT
    end
end

_collect(c, itr, ::EltypeUnknown, isz::SizeUnknown) =
    grow_to!(_similar_for(c, @default_eltype(itr), itr, isz, nothing), itr)

function _collect(c, itr, ::EltypeUnknown, isz::Union{HasLength,HasShape})
    et = @default_eltype(itr)
    shp = _similar_shape(itr, isz)
    y = iterate(itr)
    if y === nothing
        return _similar_for(c, et, itr, isz, shp)
    end
    v1, st = y
    dest = _similar_for(c, typeof(v1), itr, isz, shp)
    # The typeassert gives inference a helping hand on the element type and dimensionality
    # (work-around for #28382)
    etâ€² = et <: Type ? Type : et
    RT = dest isa AbstractArray ? AbstractArray{<:etâ€², ndims(dest)} : Any
    collect_to_with_first!(dest, v1, itr, st)::RT
end

function collect_to_with_first!(dest::AbstractArray, v1, itr, st)
    i1 = first(LinearIndices(dest))
    dest[i1] = v1
    return collect_to!(dest, itr, i1+1, st)
end

function collect_to_with_first!(dest, v1, itr, st)
    push!(dest, v1)
    return grow_to!(dest, itr, st)
end

function setindex_widen_up_to(dest::AbstractArray{T}, el, i) where T
    @inline
    new = similar(dest, promote_typejoin(T, typeof(el)))
    f = first(LinearIndices(dest))
    copyto!(new, first(LinearIndices(new)), dest, f, i-f)
    @inbounds new[i] = el
    return new
end

# Batch-widen an array given (index => value) pairs that don't fit the current element type.
function setindices_widen_up_to(dest::AbstractArray, widen_buffers::Vector{Vector{Pair{Int, Any}}})
    widen_pairs = reduce(vcat, widen_buffers; init=Pair{Int,Any}[])
    isempty(widen_pairs) && return dest
    new_T = eltype(dest)
    for p in widen_pairs
        new_T = promote_typejoin(new_T, typeof(p.second))
    end
    new_T === eltype(dest) && return dest
    # Function barrier: specializes on new_T so the compiler sees
    # concrete element types for both source and destination arrays.
    return _setindices_widen_up_to(new_T, dest, widen_pairs)
end

function _setindices_widen_up_to(::Type{T}, dest::AbstractArray, widen_pairs::Vector{Pair{Int, Any}}) where T
    new = similar(dest, T)
    copyto!(new, dest)
    for (idx, val) in widen_pairs
        @inbounds new[idx] = val
    end
    return new
end

function collect_to!(dest::AbstractArray{T}, itr, offs, st) where T
    # collect to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    i = offs
    while true
        y = iterate(itr, st)
        y === nothing && break
        el, st = y
        if el isa T
            @inbounds dest[i] = el
            i += 1
        else
            new = setindex_widen_up_to(dest, el, i)
            return collect_to!(new, itr, i+1, st)
        end
    end
    return dest
end

function grow_to!(dest, itr)
    y = iterate(itr)
    y === nothing && return dest
    dest2 = empty(dest, typeof(y[1]))
    push!(dest2, y[1])
    grow_to!(dest2, itr, y[2])
end

function push_widen(dest, el)
    @inline
    new = sizehint!(empty(dest, promote_typejoin(eltype(dest), typeof(el))), length(dest))
    if new isa AbstractSet
        # TODO: merge back these two branches when copy! is re-enabled for sets/vectors
        union!(new, dest)
    else
        append!(new, dest)
    end
    push!(new, el)
    return new
end

function grow_to!(dest, itr, st)
    T = eltype(dest)
    y = iterate(itr, st)
    while y !== nothing
        el, st = y
        if el isa T
            push!(dest, el)
        else
            new = push_widen(dest, el)
            return grow_to!(new, itr, st)
        end
        y = iterate(itr, st)
    end
    return dest
end

## Indexing: getindex ##

"""
    getindex(collection, key...)

Retrieve the value(s) stored at the given key or index within a collection. The syntax
`a[i,j,...]` is converted by the compiler to `getindex(a, i, j, ...)`.

See also [`get`](@ref), [`keys`](@ref), [`eachindex`](@ref).

# Examples
```jldoctest; filter = r"^\\s+\\S+\\s+=>\\s+\\d\$"m
julia> A = Dict("a" => 1, "b" => 2)
Dict{String, Int64} with 2 entries:
  "b" => 2
  "a" => 1

julia> getindex(A, "a")
1
```
"""
function getindex end

function getindex(A::Array, i1::Int, i2::Int, I::Int...)
    @inline
    @boundscheck checkbounds(A, i1, i2, I...) # generally _to_linear_index requires bounds checking
    return @inbounds A[_to_linear_index(A, i1, i2, I...)]
end

# Faster contiguous indexing using copyto! for AbstractUnitRange and Colon
function getindex(A::Array, I::AbstractUnitRange{<:Integer})
    @inline
    @boundscheck checkbounds(A, I)
    lI = length(I)
    X = similar(A, axes(I))
    if lI > 0
        copyto!(X, firstindex(X), A, first(I), lI)
    end
    return X
end

# getindex for carrying out logical indexing for AbstractUnitRange{Bool} as Bool <: Integer
getindex(a::Array, r::AbstractUnitRange{Bool}) = getindex(a, to_index(r))

function getindex(A::Array, c::Colon)
    lI = length(A)
    X = similar(A, lI)
    if lI > 0
        unsafe_copyto!(X, 1, A, 1, lI)
    end
    return X
end

# This is redundant with the abstract fallbacks, but needed for bootstrap
function getindex(A::Array{S}, I::AbstractRange{Int}) where S
    return S[ A[i] for i in I ]
end

## Indexing: setindex! ##

"""
    setindex!(collection, value, key...)

Store the given value at the given key or index within a collection. The syntax `a[i,j,...] =
x` is converted by the compiler to `(setindex!(a, x, i, j, ...); x)`.

# Examples
```jldoctest; filter = r"^\\s+\\S+\\s+=>\\s+\\d\$"m
julia> a = Dict("a"=>1)
Dict{String, Int64} with 1 entry:
  "a" => 1

julia> setindex!(a, 2, "b")
Dict{String, Int64} with 2 entries:
  "b" => 2
  "a" => 1
```
"""
function setindex! end

function setindex!(A::Array{T}, x, i::Int) where {T}
    @_propagate_inbounds_meta
    x = x isa T ? x : convert(T, x)::T
    return _setindex!(A, x, i)
end
function _setindex!(A::Array{T}, x::T, i::Int) where {T}
    @_noub_if_noinbounds_meta
    @boundscheck checkbounds(A, i)
    memoryrefset!(memoryrefnew(A.ref, i, false), x, :not_atomic, false)
    return A
end
function setindex!(A::Array{T}, x, i1::Int, i2::Int, I::Int...) where {T}
    @_propagate_inbounds_meta
    x = x isa T ? x : convert(T, x)::T
    return _setindex!(A, x, i1, i2, I...)
end
function _setindex!(A::Array{T}, x::T, i1::Int, i2::Int, I::Int...) where {T}
    @inline
    @_noub_if_noinbounds_meta
    @boundscheck checkbounds(A, i1, i2, I...) # generally _to_linear_index requires bounds checking
    memoryrefset!(memoryrefnew(A.ref, _to_linear_index(A, i1, i2, I...), false), x, :not_atomic, false)
    return A
end

__safe_setindex!(A::Vector{Any}, @nospecialize(x), i::Int) = (@inline; @_nothrow_noub_meta;
    memoryrefset!(memoryrefnew(A.ref, i, false), x, :not_atomic, false); return A)
__safe_setindex!(A::Vector{T}, x::T, i::Int) where {T} = (@inline; @_nothrow_noub_meta;
    memoryrefset!(memoryrefnew(A.ref, i, false), x, :not_atomic, false); return A)
__safe_setindex!(A::Vector{T}, x,    i::Int) where {T} = (@inline;
    __safe_setindex!(A, convert(T, x)::T, i))

# This is redundant with the abstract fallbacks but needed and helpful for bootstrap
function setindex!(A::Array, X::AbstractArray, I::AbstractVector{Int})
    @_propagate_inbounds_meta
    @boundscheck setindex_shape_check(X, length(I))
    @boundscheck checkbounds(A, I)
    require_one_based_indexing(X)
    Xâ€² = unalias(A, X)
    Iâ€² = unalias(A, I)
    count = 1
    for i in Iâ€²
        @inbounds A[i] = Xâ€²[count]
        count += 1
    end
    return A
end

# Faster contiguous setindex! with copyto!
function setindex!(A::Array{T}, X::Array{T}, I::AbstractUnitRange{Int}) where T
    @inline
    @boundscheck checkbounds(A, I)
    lI = length(I)
    @boundscheck setindex_shape_check(X, lI)
    if lI > 0
        unsafe_copyto!(A, first(I), X, 1, lI)
    end
    return A
end
function setindex!(A::Array{T}, X::Array{T}, c::Colon) where T
    @inline
    lI = length(A)
    @boundscheck setindex_shape_check(X, lI)
    if lI > 0
        unsafe_copyto!(A, 1, X, 1, lI)
    end
    return A
end

# Pick new memory size for efficiently growing an array
# TODO: This should know about the size of our GC pools
# Specifically we are wasting ~10% of memory for small arrays
# by not picking memory sizes that max out a GC pool
function overallocation(maxsize)
    # compute maxsize = maxsize + 3*maxsize^(7/8) + maxsize/8
    # for small n, we grow faster than O(n)
    # for large n, we grow at O(n/8)
    # and as we reach O(memory) for memory>>1MB,
    # this means we end by adding about 10% of memory each time
    # most commonly, this will take steps of 0-3-9-34 or 1-4-16-66 or 2-8-33
    exp2 = sizeof(maxsize) * 8 - Core.Intrinsics.ctlz_int(maxsize)
    maxsize += (1 << div(exp2 * 7, 8)) * 3 + div(maxsize, 8)
    return maxsize
end

array_new_memory(mem::Memory, newlen::Int) = typeof(mem)(undef, newlen) # when implemented, this should attempt to first expand mem

function _growbeg_internal!(a::Vector, delta::Int, len::Int)
    @_terminates_locally_meta
    ref = a.ref
    mem = ref.mem
    offset = memoryrefoffset(ref)
    newlen = len + delta
    memlen = length(mem)
    if offset + len - 1 > memlen || offset < 1
        throw(ConcurrencyViolationError("Vector has invalid state. Don't modify internal fields incorrectly, or resize without correct locks"))
    end
    # since we will allocate the array in the middle of the memory we need at least 2*delta extra space
    # the +1 is because I didn't want to have an off by 1 error.
    newmemlen = max(overallocation(len), len + 2 * delta + 1)
    newoffset = div(newmemlen - newlen, 2) + 1
    # If there is extra data after the end of the array we can use that space so long as there is enough
    # space at the end that there won't be quadratic behavior with a mix of growth from both ends.
    # Specifically, we want to ensure that we will only do this operation once before
    # increasing the size of the array, and that we leave enough space at both the beginning and the end.
    if newoffset + newlen < memlen
        newoffset = div(memlen - newlen, 2) + 1
        newmem = mem
        unsafe_copyto!(newmem, newoffset + delta, mem, offset, len)
        for j in offset:newoffset+delta-1
            @inbounds _unsetindex!(mem, j)
        end
    else
        newmem = array_new_memory(mem, newmemlen)
        unsafe_copyto!(newmem, newoffset + delta, mem, offset, len)
    end
    if ref !== a.ref
        throw(ConcurrencyViolationError("Vector can not be resized concurrently"))
    end
    setfield!(a, :ref, @inbounds memoryref(newmem, newoffset))
end

function _growbeg!(a::Vector, delta::Integer)
    @_noub_meta
    delta = Int(delta)
    delta == 0 && return # avoid attempting to index off the end
    delta >= 0 || throw(ArgumentError("grow requires delta >= 0"))
    ref = a.ref
    len = length(a)
    offset = memoryrefoffset(ref)
    newlen = len + delta
    # if offset is far enough advanced to fit data in existing memory without copying
    if delta <= offset - 1
        setfield!(a, :ref, @inbounds memoryref(ref, 1 - delta))
        setfield!(a, :size, (newlen,))
    else
        @noinline _growbeg_internal!(a, delta, len)
        setfield!(a, :size, (newlen,))
    end
    return
end

function _growend_internal!(a::Vector, delta::Int, len::Int)
    ref = a.ref
    mem = ref.mem
    memlen = length(mem)
    newlen = len + delta
    offset = memoryrefoffset(ref)
    newmemlen = offset + newlen - 1
    if offset + len - 1 > memlen || offset < 1
        throw(ConcurrencyViolationError("Vector has invalid state. Don't modify internal fields incorrectly, or resize without correct locks"))
    end

    if offset - 1 > div(5 * newlen, 4)
        # If the offset is far enough that we can copy without resizing
        # while maintaining proportional spacing on both ends of the array
        # note that this branch prevents infinite growth when doing combinations
        # of push! and popfirst! (i.e. when using a Vector as a queue)
        newmem = mem
        newoffset = div(newlen, 8) + 1
    else
        # grow either by our computed overallocation factor
        # or exactly the requested size, whichever is larger
        # TODO we should possibly increase the offset if the current offset is nonzero.
        newmemlen2 = max(overallocation(memlen), newmemlen)
        newmem = array_new_memory(mem, newmemlen2)
        newoffset = offset
    end
    newref = @inbounds memoryref(newmem, newoffset)
    unsafe_copyto!(newref, ref, len)
    if ref !== a.ref
        @noinline throw(ConcurrencyViolationError("Vector can not be resized concurrently"))
    end
    setfield!(a, :ref, newref)
return
end

function _growend!(a::Vector, delta::Integer)
    @_noub_meta
    delta = Int(delta)
    delta >= 0 || throw(ArgumentError("grow requires delta >= 0"))
    ref = a.ref
    mem = ref.mem
    memlen = length(mem)
    len = length(a)
    newlen = len + delta
    offset = memoryrefoffset(ref)
    newmemlen = offset + newlen - 1
    if memlen < newmemlen
        @noinline _growend_internal!(a, delta, len)
    end
    setfield!(a, :size, (newlen,))
    return
end

function _growat!(a::Vector, i::Integer, delta::Integer)
    @_terminates_globally_noub_meta
    delta = Int(delta)
    i = Int(i)
    i == 1 && return _growbeg!(a, delta)
    len = length(a)
    i == len + 1 && return _growend!(a, delta)
    delta >= 0 || throw(ArgumentError("grow requires delta >= 0"))
    1 < i <= len || throw(BoundsError(a, i))
    ref = a.ref
    mem = ref.mem
    memlen = length(mem)
    newlen = len + delta
    offset = memoryrefoffset(ref)
    newmemlen = offset + newlen - 1

    # which side would we rather grow into?
    prefer_start = i <= div(len, 2)
    # if offset is far enough advanced to fit data in beginning of the memory
    if prefer_start && delta <= offset - 1
        newref = @inbounds memoryref(mem, offset - delta)
        unsafe_copyto!(newref, ref, i)
        setfield!(a, :ref, newref)
        setfield!(a, :size, (newlen,))
        for j in i:i+delta-1
            @inbounds _unsetindex!(a, j)
        end
    elseif !prefer_start && memlen >= newmemlen
        unsafe_copyto!(mem, offset - 1 + delta + i, mem, offset - 1 + i, len - i + 1)
        setfield!(a, :size, (newlen,))
        for j in i:i+delta-1
            @inbounds _unsetindex!(a, j)
        end
    else
        # since we will allocate the array in the middle of the memory we need at least 2*delta extra space
        # the +1 is because I didn't want to have an off by 1 error.
        newmemlen = max(overallocation(memlen), len+2*delta+1)
        newoffset = (newmemlen - newlen) Ã· 2 + 1
        newmem = array_new_memory(mem, newmemlen)
        newref = @inbounds memoryref(newmem, newoffset)
        unsafe_copyto!(newref, ref, i-1)
        unsafe_copyto!(newmem, newoffset + delta + i - 1, mem, offset + i - 1, len - i + 1)
        setfield!(a, :ref, newref)
        setfield!(a, :size, (newlen,))
    end
end

# efficiently delete part of an array
function _deletebeg!(a::Vector, delta::Integer)
    delta = Int(delta)
    len = length(a)
    # See comment in _deleteend!
    if unsigned(delta) > unsigned(len)
        throw(ArgumentError("_deletebeg! requires delta in 0:length(a)"))
    end
    for i in 1:delta
        @inbounds _unsetindex!(a, i)
    end
    newlen = len - delta
    setfield!(a, :size, (newlen,))
    if newlen != 0 # if newlen==0 we could accidentally index past the memory
        newref = @inbounds memoryref(a.ref, delta + 1)
        setfield!(a, :ref, newref)
    end
    return
end
function _deleteend!(a::Vector, delta::Integer)
    delta = Int(delta)
    len = length(a)
    # Do the comparison unsigned, to so the compiler knows `len` cannot be negative.
    # This works because if delta is negative, it will overflow and still trigger.
    # This enables the compiler to skip the check sometimes.
    if unsigned(delta) > unsigned(len)
        throw(ArgumentError("_deleteend! requires delta in 0:length(a)"))
    end
    newlen = len - delta
    for i in newlen+1:len
        @inbounds _unsetindex!(a, i)
    end
    setfield!(a, :size, (newlen,))
    return
end
function _deleteat!(a::Vector, i::Integer, delta::Integer)
    i = Int(i)
    len = length(a)
    0 <= delta || throw(ArgumentError("_deleteat! requires delta >= 0"))
    1 <= i <= len || throw(BoundsError(a, i))
    i + delta <= len + 1 || throw(BoundsError(a, i + delta - 1))
    newa = a
    if 2*i + delta <= len
        unsafe_copyto!(newa, 1 + delta, a, 1, i - 1)
        _deletebeg!(a, delta)
    else
        unsafe_copyto!(newa, i, a, i + delta, len + 1 - delta - i)
        _deleteend!(a, delta)
    end
    return
end
## Dequeue functionality ##

"""
    push!(collection, items...) -> collection

Insert one or more `items` in `collection`. If `collection` is an ordered container,
the items are inserted at the end (in the given order).

# Examples
```jldoctest
julia> push!([1, 2, 3], 4, 5, 6)
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```

If `collection` is ordered, use [`append!`](@ref) to add all the elements of another
collection to it. The result of the preceding example is equivalent to `append!([1, 2, 3], [4,
5, 6])`. For `AbstractSet` objects, [`union!`](@ref) can be used instead.

See [`sizehint!`](@ref) for notes about the performance model.

See also [`pushfirst!`](@ref).
"""
function push! end

function push!(a::Vector{T}, item) where T
    @inline
    # convert first so we don't grow the array if the assignment won't work
    # and also to avoid a dynamic dynamic dispatch in the common case that
    # `item` is poorly-typed and `a` is well-typed
    item = item isa T ? item : convert(T, item)::T
    return _push!(a, item)
end
function _push!(a::Vector{T}, item::T) where T
    _growend!(a, 1)
    @_safeindex a[length(a)] = item
    return a
end

# specialize and optimize the single argument case
function push!(a::Vector{Any}, @nospecialize x)
    _growend!(a, 1)
    @_safeindex a[length(a)] = x
    return a
end
function push!(a::Vector{Any}, @nospecialize x...)
    @_terminates_locally_meta
    na = length(a)
    nx = length(x)
    _growend!(a, nx)
    @_safeindex for i = 1:nx
        a[na+i] = x[i]
    end
    return a
end

"""
    append!(collection, collections...) -> collection.

For an ordered container `collection`, add the elements of each `collections`
to the end of it.

!!! compat "Julia 1.6"
    Specifying multiple collections to be appended requires at least Julia 1.6.

# Examples
```jldoctest
julia> append!([1], [2, 3])
3-element Vector{Int64}:
 1
 2
 3

julia> append!([1, 2, 3], [4, 5], [6])
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```

Use [`push!`](@ref) to add individual items to `collection` which are not already
themselves in another collection. The result of the preceding example is equivalent to
`push!([1, 2, 3], 4, 5, 6)`.

See [`sizehint!`](@ref) for notes about the performance model.

See also [`vcat`](@ref) for vectors, [`union!`](@ref) for sets,
and [`prepend!`](@ref) and [`pushfirst!`](@ref) for the opposite order.
"""
function append! end

function append!(a::Vector{T}, items::Union{AbstractVector{<:T},Tuple}) where T
    items isa Tuple && (items = map(x -> convert(T, x), items))
    n = Int(length(items))::Int
    _growend!(a, n)
    copyto!(a, length(a)-n+1, items, firstindex(items), n)
    return a
end

append!(a::AbstractVector, iter) = _append!(a, IteratorSize(iter), iter)
push!(a::AbstractVector, iter...) = append!(a, iter)
append!(a::AbstractVector, iter...) = (foreach(v -> append!(a, v), iter); a)

function _append!(a::AbstractVector, ::Union{HasLength,HasShape}, iter)
    n = Int(length(iter))::Int
    sizehint!(a, length(a) + n; shrink=false)
    for item in iter
        push!(a, item)
    end
    a
end
function _append!(a::AbstractVector, ::IteratorSize, iter)
    for item in iter
        push!(a, item)
    end
    a
end

"""
    prepend!(a::Vector, collections...) -> collection

Insert the elements of each `collections` to the beginning of `a`.

When `collections` specifies multiple collections, order is maintained:
elements of `collections[1]` will appear leftmost in `a`, and so on.

!!! compat "Julia 1.6"
    Specifying multiple collections to be prepended requires at least Julia 1.6.

# Examples
```jldoctest
julia> prepend!([3], [1, 2])
3-element Vector{Int64}:
 1
 2
 3

julia> prepend!([6], [1, 2], [3, 4, 5])
6-element Vector{Int64}:
 1
 2
 3
 4
 5
 6
```
"""
function prepend! end

function prepend!(a::Vector{T}, items::Union{AbstractVector{<:T},Tuple}) where T
    items isa Tuple && (items = map(x -> convert(T, x), items))
    n = length(items)
    _growbeg!(a, n)
    # in case of aliasing, the _growbeg might have shifted our data, so copy
    # just the last n elements instead of all of them from the first
    copyto!(a, 1, items, lastindex(items)-n+1, n)
    return a
end

prepend!(a::AbstractVector, iter) = _prepend!(a, IteratorSize(iter), iter)
pushfirst!(a::AbstractVector, iter...) = prepend!(a, iter)
prepend!(a::AbstractVector, iter...) = (for v = reverse(iter); prepend!(a, v); end; return a)

function _prepend!(a::Vector, ::Union{HasLength,HasShape}, iter)
    @_terminates_locally_meta
    require_one_based_indexing(a)
    n = Int(length(iter))::Int
    sizehint!(a, length(a) + n; first=true, shrink=false)
    n = 0
    for item in iter
        n += 1
        pushfirst!(a, item)
    end
    reverse!(a, 1, n)
    a
end
function _prepend!(a::Vector, ::IteratorSize, iter)
    n = 0
    for item in iter
        n += 1
        pushfirst!(a, item)
    end
    reverse!(a, 1, n)
    a
end

"""
    resize!(a::Vector, n::Integer) -> a

Resize `a` to contain `n` elements. If `n` is smaller than the current collection
length, the first `n` elements will be retained. If `n` is larger, the new elements are not
guaranteed to be initialized.

# Examples
```jldoctest
julia> resize!([6, 5, 4, 3, 2, 1], 3)
3-element Vector{Int64}:
 6
 5
 4

julia> a = resize!([6, 5, 4, 3, 2, 1], 8);

julia> length(a)
8

julia> a[1:6]
6-element Vector{Int64}:
 6
 5
 4
 3
 2
 1
```
"""
function resize!(a::Vector, nl_::Integer)
    nl = Int(nl_)::Int
    l = length(a)
    if nl > l
        # Since l is positive, if nl > l, both are positive, and so nl-l is also
        # positive. But the compiler does not know that, so we mask out top bit.
        # This allows the compiler to skip the check
        _growend!(a, (nl-l) & typemax(Int))
    elseif nl != l
        if nl < 0
            _throw_argerror("new length must be â‰¥ 0")
        end
        _deleteend!(a, l-nl)
    end
    return a
end

"""
    sizehint!(s, n; first::Bool=false, shrink::Bool=true) -> s

Suggest that collection `s` reserve capacity for at least `n` elements. That is, if
you expect that you're going to have to push a lot of values onto `s`, you can avoid
the cost of incremental reallocation by doing it once up front; this can improve
performance.

If `first` is `true`, then any additional space is reserved before the start of the collection.
This way, subsequent calls to `pushfirst!` (instead of `push!`) may become faster.
Supplying this keyword may result in an error if the collection is not ordered
or if `pushfirst!` is not supported for this collection.

If `shrink=true` (the default), the collection's capacity may be reduced if its current
capacity is greater than `n`.

See also [`resize!`](@ref).

# Notes on the performance model

For types that support `sizehint!`,

1. `push!` and `append!` methods generally may (but are not required to) preallocate extra
   storage. For types implemented in `Base`, they typically do, using a heuristic optimized for
   a general use case.

2. `sizehint!` may control this preallocation. Again, it typically does this for types in
   `Base`.

3. `empty!` is nearly costless (and O(1)) for types that support this kind of preallocation.

!!! compat "Julia 1.11"
    The `shrink` and `first` arguments were added in Julia 1.11.
"""
function sizehint! end

function sizehint!(a::Vector, sz::Integer; first::Bool=false, shrink::Bool=true)
    len = length(a)
    ref = a.ref
    mem = ref.mem
    memlen = length(mem)
    sz = max(Int(sz), len)
    inc = sz - len
    if sz <= memlen
        # if we don't save at least 1/8th memlen then its not worth it to shrink
        if !shrink || memlen - sz <= div(memlen, 8)
            return a
        end
        newmem = array_new_memory(mem, sz)
        if first
            newref = memoryref(newmem, inc + 1)
        else
            newref = memoryref(newmem)
        end
        unsafe_copyto!(newref, ref, len)
        setfield!(a, :ref, newref)
    elseif first
        _growbeg!(a, inc)
        newref = getfield(a, :ref)
        newref = memoryref(newref, inc + 1)
        setfield!(a, :size, (len,)) # undo the size change from _growbeg!
        setfield!(a, :ref, newref) # undo the offset change 
