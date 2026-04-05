# This file is a part of Julia. License is MIT: https://julialang.org/license

import Core: Bool

# promote Bool to any other numeric type
promote_rule(::Type{Bool}, ::Type{T}) where {T<:Number} = T

typemin(::Type{Bool}) = false
typemax(::Type{Bool}) = true

## boolean operations ##

(~)(x::Bool) = !x
(&)(x::Bool, y::Bool) = and_int(x, y)
(|)(x::Bool, y::Bool) = or_int(x, y)

"""
    xor(x, y)
    âŠ»(x, y)

Bitwise exclusive or of `x` and `y`. Implements
[three-valued logic](https://en.wikipedia.org/wiki/Three-valued_logic),
returning [`missing`](@ref) if one of the arguments is `missing`.

The infix operation `a âŠ» b` is a synonym for `xor(a,b)`, and
`âŠ»` can be typed by tab-completing `\\xor` or `\\veebar` in the Julia REPL.

# Examples
```jldoctest
julia> xor(true, false)
true

julia> xor(true, true)
false

julia> xor(true, missing)
missing

julia> false âŠ» false
false

julia> [true; true; false] .âŠ» [true; false; false]
3-element BitVector:
 0
 1
 0
```
"""
xor(x::Bool, y::Bo
