module Ratios

import Base: convert, promote_rule, +, -, *, /, ^, ==

export SimpleRatio

immutable SimpleRatio{T<:Integer} <: Real
    num::T
    den::T
end


for I in [Int8,Int16,Int32,Int64,Int128,
          UInt8,UInt16,UInt32,UInt64,UInt128]

    s = I <: Signed ? 's' : 'u'
    b = sizeof(I) << 3
    r = b == 8 ? "[2 x i8]" : "{ i$b, i8 }" # LLVM return type
    
    for op in [:add,:sub,:mul]
        f = symbol(:safe_,op)
        @eval @inline function $f(x::$I, y::$I)
            x,n = Base.llvmcall((
            $"declare { i$b, i1 } @llvm.$(s)$(op).with.overflow.i$b(i$b, i$b)",
            $"""
            %xo = call { i$b, i1 } @llvm.$(s)$(op).with.overflow.i$b(i$b %0, i$b %1)
            %x  = extractvalue { i$b, i1 } %xo, 0
            %o1 = extractvalue { i$b, i1 } %xo, 1
            %o8 = zext i1 %o1 to i8
            %rx = insertvalue $r undef, i$b %x, 0
            %r  = insertvalue $r %rx, i8 %o8, 1
            ret $r %r"""),
            Tuple{$I,Bool},Tuple{$I,$I},x,y)
            Nullable(x,n)
        end
    end
end

# overflow check macro
macro oc(ex)
    quote
        x = $(esc(ex))
        isnull(x) && @goto overflow
        get(x)
    end
end

safe_add(x::Integer,y::Integer) = safe_add(promote(x,y)...)
safe_sub(x::Integer,y::Integer) = safe_sub(promote(x,y)...)


import Base: divgcd

const ⊞ = safe_add
const ⊟ = safe_sub
const ⊠ = safe_mul
const ⊗ = widemul


convert{S}(::Type{BigFloat}, r::SimpleRatio{S}) = BigFloat(r.num)/r.den
function convert{T<:AbstractFloat,S}(::Type{T}, r::SimpleRatio{S})
    P = promote_type(T,S)
    convert(T, convert(P, r.num)/convert(P, r.den))
end
convert{T<:Integer}(::Type{SimpleRatio{T}}, i::Integer) = SimpleRatio{T}(convert(T, i), one(T))

convert{T<:Integer}(::Type{SimpleRatio{T}},x::SimpleRatio) = SimpleRatio(convert(T,x.num),convert(T,x.den))


function *{T}(x::SimpleRatio{T}, y::SimpleRatio{T})
    return SimpleRatio(@oc(x.num ⊠ y.num),@oc(x.den ⊠ y.den))

    @label overflow
    wnum = x.num ⊗ y.num
    wden = x.den ⊗ y.den
    num, den = divgcd(wnum, wden)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    return SimpleRatio(num % T, den % T)
end
#*(x::SimpleRatio, y::SimpleRatio) = *(promote(x,y)...)

*{T}(x::SimpleRatio{T}, y::Bool) = SimpleRatio(x.num*y, x.den)
*{T}(x::Bool, y::SimpleRatio{T}) = SimpleRatio(x*y.num, y.den)

function *{T}(x::SimpleRatio{T}, y::Integer)
    return SimpleRatio(@oc(x.num ⊠ y), x.den)
    
    @label overflow
    num = x.num ⊗ y
    num, den = divgcd(num, x.den)
    typemin(T) <= num <= typemax(T) || throw(OverflowError())
    return SimpleRatio(num % T, den % T)
end
*{T}(x::Integer, y::SimpleRatio{T}) = *(y,x)

    
function /{T}(x::SimpleRatio{T}, y::SimpleRatio{T})
    return SimpleRatio(@oc(x.num ⊠ y.den), @oc(x.num ⊠ y.den))

    @label overflow
    wnum = x.num ⊗ y.den
    wden = x.den ⊗ y.num
    num, den = divgcd(wnum, wden)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    return SimpleRatio(num % T, den % T)
end
#/(x::SimpleRatio, y::SimpleRatio) = /(promote(x,y)...)

function /{T}(x::SimpleRatio{T}, y::Integer)
    return SimpleRatio(x.num, @oc(x.den ⊠ y))

    @label overflow
    wden = x.den ⊗ y
    num, den = divgcd(x.num, wden)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    return SimpleRatio(num % T, den % T)
end

function /{T}(x::Integer, y::SimpleRatio{T})
    return SimpleRatio(@oc(x ⊠ y.den), y.num)

    @label overflow
    wnum = x ⊗ y.den
    num, den = divgcd(wnum, y.num)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    return SimpleRatio(num % T, den % T)
end
    
function +{T}(x::Integer, y::SimpleRatio{T})
    return SimpleRatio(@oc(@oc(x ⊠ y.den) ⊞ y.num), y.den)

    @label overflow
    num = x ⊗ y.den + y.num
    num, den = divgcd(num, y.den)
    typemin(T) <= num <= typemax(T) || throw(OverflowError())
    SimpleRatio(num % T, den % T)
end
+{T}(x::SimpleRatio{T}, y::Integer) = +(y,x)


function -{T}(x::Integer, y::SimpleRatio{T})
    return SimpleRatio(@oc(@oc(x ⊠ y.den) ⊟ y.num), y.den)

    @label overflow
    num = x ⊗ y.den - y.num
    num, den = divgcd(num, y.den)
    typemin(T) <= num <= typemax(T) || throw(OverflowError())
    SimpleRatio(num % T, den % T)
end
function -{T}(x::SimpleRatio{T}, y::Integer)
    return SimpleRatio(@oc(x.num ⊟ @oc(y ⊠ x.den)), x.den)

    @label overflow
    num = x.num - y ⊗ x.den
    num, den = divgcd(num, x.den)
    typemin(T) <= num <= typemax(T) || throw(OverflowError())
    SimpleRatio(num % T, den % T)
end

function +{T}(x::SimpleRatio{T}, y::SimpleRatio{T})
    if x.den == y.den
        return SimpleRatio(@oc(x.num ⊞ y.num), x.den)
    else
        return SimpleRatio(@oc(@oc(x.num ⊠ y.den) ⊞ @oc(x.den ⊠ y.num)), @oc(x.den ⊠ y.den))
    end

    @label overflow
    num = (x.num ⊗ y.den) + (x.den ⊗ y.num)
    den = x.den ⊗ y.den
    num, den = divgcd(num, den)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    SimpleRatio(num % T, den % T)
end
#+(x::SimpleRatio, y::SimpleRatio) = +(promote(x,y)...)

function -{T}(x::SimpleRatio{T}, y::SimpleRatio{T})
    if x.den == y.den
        return SimpleRatio(@oc(x.num ⊟ y.num), x.den)
    else
        return SimpleRatio(@oc(@oc(x.num ⊠ y.den) ⊟ @oc(x.den ⊠ y.num)), @oc(x.den ⊠ y.den))
    end

    @label overflow
    num = x.num ⊗ y.den - x.den ⊗ y.num
    den = x.den ⊗ y.den
    num, den = divgcd(num, den)
    typemin(T) <= num <= typemax(T) && typemin(T) <= den <= typemax(T) || throw(OverflowError())
    SimpleRatio(num % T, den % T)
end
#-(x::SimpleRatio, y::SimpleRatio) = -(promote(x,y)...)

^(x::SimpleRatio, y::Integer) = Base.power_by_squaring(x,y)

-{T<:Signed}(x::SimpleRatio{T}) = SimpleRatio(-x.num, x.den)
-{T<:Unsigned}(x::SimpleRatio{T}) = throw(OverflowError())

promote_rule{T<:Integer,S<:Integer}(::Type{SimpleRatio{T}}, ::Type{S}) = SimpleRatio{promote_type(T,S)}
promote_rule{T<:Integer,S<:Integer}(::Type{SimpleRatio{T}}, ::Type{SimpleRatio{S}}) = SimpleRatio{promote_type(T,S)}
promote_rule{T<:Integer,S<:AbstractFloat}(::Type{SimpleRatio{T}}, ::Type{S}) = promote_type(T,S)

==(x::SimpleRatio, y::SimpleRatio) = x.num*y.den == x.den*y.num

==(x::SimpleRatio, y::Integer) = x.num == x.den*y
==(x::Integer, y::SimpleRatio) = x*y.den == y.num

function ==(x::AbstractFloat, q::SimpleRatio)
    if isfinite(x)
        (count_ones(q.den) == 1) & (x*q.den == q.num)
    else
        x == q.num/q.den
    end
end

==(q::SimpleRatio, x::AbstractFloat) = x == q


end
