# Containers
################################################################################

"""
    abstract type Container

Abstract type for containers that can be indexed by year and time.  i.e. `c[yr_idx, hr_idx]` will work, even if `c` contains a single number, a number for each year, a number for each hour, or a number for each year and hour.
"""
abstract type Container{T, D} <: AbstractArray{T, D} end
export Container

Container(x::Number) = OriginalContainer(x, ByNothing(x))

Container(c::Container) = c
Base.getindex(c::Container, inds::Vararg) = c.v[inds...]
Base.setindex!(c::Container, val, inds::Vararg) = (c.v[inds...] = val)

Base.isempty(c::Container) = false
Base.size(c::Container) = size(c.v)
Base.BroadcastStyle(::Type{C}) where {C<:Container} = Broadcast.ArrayStyle{C}()
Base.Broadcast.broadcastable(c::Container) = c

# Note that for comparisons, only returns true when all holds true.
Base.isless(c::Container, n::Number)  = all(<(n), c)
Base.isequal(c::Container, n::Number) = all(==(n), c)

Base.isless(n::Number, c::Container)  = all(>(n), c)
Base.isequal(n::Number, c::Container) = all(==(n), c)



Broadcast.result_join(::Broadcast.ArrayStyle{C1}, ::Broadcast.ArrayStyle{C2}, ::Broadcast.Unknown, ::Broadcast.Unknown) where {T1, D1, T2, D2, C1<:Container{T1,D1}, C2<:Container{T2,D2}}= begin
    C = ConflictContainerType(C1, C2)
    return Broadcast.ArrayStyle{C}()
end

function ConflictContainerType(::Type{C1}, ::Type{C2}) where {T1, D1, T2, D2, C1<:Container{T1,D1}, C2<:Container{T2,D2}}
    D = max(D1, D2)
    if D == 2
        if min(D1, D2) == 0
            if D1 == 2
                return C1
            else
                return C2
            end
        end
        return ByYearAndHour
    end
    if D1 == D
        return C1
    else
        return C2
    end
end

function Base.similar(bc::Broadcast.Broadcasted{Broadcast.ArrayStyle{C}}, ::Type{ElType}) where  {ElType, C<:Container}
    a = axes(bc)
    c = C(similar(Array{ElType}, a))
    c
end



mutable struct OriginalContainer{T, D, C} <: Container{T,D}
    original::Float64
    v::C
    function OriginalContainer(x, c::C) where {T,D, C<:Container{T,D}}
        new{T, D, C}(Float64(x), c)
    end
end

OriginalContainer(x, c::OriginalContainer) = OriginalContainer(x, c.v)


function Base.similar(bc::Broadcast.Broadcasted{Broadcast.ArrayStyle{OC}}, ::Type{ElType}) where  {ElType, C<:Container, T, D, OC<:OriginalContainer{T, D, C}}
    orig = find_original(bc)
    a = axes(bc)
    c = OriginalContainer(orig, ContainerType(C)(similar(Array{ElType}, a)))
    c
end


find_original(bc::Base.Broadcast.Broadcasted) = _find_original(bc).original
_find_original(bc::Base.Broadcast.Broadcasted) = _find_original(bc.args)
_find_original(args::Tuple) = _find_original(_find_original(args[1]), Base.tail(args))
_find_original(x) = x
_find_original(::Tuple{}) = begin
    nothing
end
_find_original(a::OriginalContainer, rest) = a
_find_original(a::OriginalContainer) = a
_find_original(::Any, rest) = _find_original(rest)

ContainerType(::Type{C}) where {C<:Container} = C
ContainerType(::Type{OC}) where {C<:Container, T,D,OC<:OriginalContainer{T,D,C}} = C

function ConflictContainerType(::Type{OC1}, ::Type{C2}) where {T1, D1, T2, D2, C1, OC1<:OriginalContainer{T1,D1, C1}, C2<:Container{T2,D2}}
    return OriginalContainer{T1, max(D1,D2), ConflictContainerType(C1, C2)}
end
function ConflictContainerType(::Type{C2}, ::Type{OC1}) where {T1, D1, T2, D2, C1, OC1<:OriginalContainer{T1,D1, C1}, C2<:Container{T2,D2}}
    return OriginalContainer{T1, max(D1,D2), ConflictContainerType(C1, C2)}
end
function ConflictContainerType(::Type{OC1}, ::Type{OC2}) where {T1, D1, C1, T2, D2, C2, OC1<:OriginalContainer{T1,D1, C1}, OC2<:OriginalContainer{T2,D2, C2}}
    return OriginalContainer{T1, max(D1,D2), ConflictContainerType(C1, C2)}
end

mutable struct ByNothing <: Container{Float64, 0} 
    v::Float64
end
export ByNothing
ByNothing(v::AbstractArray) = ByNothing(v...)
Base.setindex!(c::ByNothing, val::Number, idxs::Vararg) = (c.v = val)

struct ByYear <: Container{Float64, 1}
    v::Vector{Float64}
end
export ByYear

struct ByHour <: Container{Float64, 2}
    v::Vector{Float64}
end
export ByHour

ByHour(m::Matrix{Float64}) = ByHour([m...])
Base.size(bh::ByHour) = (1, length(bh.v))
Base.setindex!(c::ByHour, val::Float64, i1::Int, i2::Int) = (c.v[i2] = val)
Base.setindex!(c::ByHour, val::Float64, idxs::CartesianIndex{2}) = (c.v[idxs[2]] = val)

struct ByYearAndHour <: Container{Float64, 2}
    v::Vector{Vector{Float64}}
end
export ByYearAndHour

ByYearAndHour(m::AbstractMatrix) = ByYearAndHour([m[i,:] for i in axes(m,1)])
Base.size(c::ByYearAndHour) = (length(c.v), length(first(c.v)))
ByYearAndHour(m::Matrix) = ByYearAndHour([m[i,:] for i in axes(m,1)])
Base.setindex!(c::ByYearAndHour, val, i1::Int, i2::Int) = (c.v[i1][i2] = val)
Base.setindex!(c::ByYearAndHour, val, idxs::CartesianIndex{2}) = (c.v[idxs[1]][idxs[2]] = val)

struct HoursContainer <: Container{Float64, 2}
    v::Vector{Float64}
end
export HoursContainer

function Base.convert(::Type{<:OriginalContainer{N, D, C}}, x::OriginalContainer) where {N,D,C}
    return OriginalContainer(x.original, convert(C, x.v))
end
function Base.convert(::Type{<:OriginalContainer{N, D, C}}, x::ByNothing) where {N,D,C}
    return OriginalContainer(x.v, convert(C, x))
end
function Base.convert(::Type{ByNothing}, c::C) where {C<:Container}
    if all(==(1), size(c))
        return ByNothing(c[1,1])
    end
    error("To convert from $C to ByNothing, it must have only a single value")
end
function Base.convert(::Type{Float64}, c::Container)
    if all(==(1), size(c))
        return c[1,1]
    end
    error("Cannot convert Container of size $(size(c)) to Float64")
end

function Base.convert(::Type{<:Container}, c::Float64)
    return ByNothing(c)
end


function promote_col(col::Vector{C}) where {C<:Container}
    isabstracttype(C) || return col
    isempty(col) && return ByNothing[]
    T = get_promotion_type(col)
    if ismulti(T)
        scalar = _get_unity_scalar(T, col)
        for i in eachindex(col)
            col[i] = col[i] .* scalar
        end
    end

    return convert(Vector{T}, col)
end

function get_promotion_type(col::Vector{<:Container})
    ET = typeof(first(col))
    if all(e->e isa ET, col)
        return ET
    elseif all(e->length(e) == 1, col)
        return any(isoriginal, col) ? OriginalContainer{Float64, 0, ByNothing} : ByNothing
    else
        types = unique!(typeof.(col))
        res = 0.0
        for type in types
            i = findfirst(e->e isa type, col)
            val = col[i]
            res = res .* val
        end
        return typeof(res)
    end
    return Container
end

isoriginal(e) = false
isoriginal(e::OriginalContainer) = true
ismulti(::Type{<:OriginalContainer{N, 0}}) where N = false
ismulti(::Type{<:Container}) = true
ismulti(::Type{<:ByNothing}) = false

function _get_unity_scalar(T, col)
    i = findfirst(e->e isa T, col)
    c = col[i]
    return c .* 0 .+ 1
end


"""
    get_original(c::Container) -> original::Float64

Returns the original value of a Container prior to setting, adding, and scaling.
"""
function get_original(c::OriginalContainer)
    return c.original
end
function get_original(c::ByNothing)
    return c.v
end
function get_original(c::ByYear)
    return c.v
end
function get_original(n::Number)
    return n
end
export get_original

"""
    Base.getindex(c::Container, year_idx, hour_idx) -> val::Float64

Retrieve the value from `c` at `year_idx` and `hour_idx`
"""
function Base.getindex(c::OriginalContainer, year_idx, hour_idx)
    return c.v[year_idx, hour_idx]
end
function Base.getindex(c::ByNothing, year_idx, hour_idx)
    c.v::Float64
end
function Base.getindex(c::ByYear, year_idx, hour_idx)
    c.v[year_idx]::Float64
end
Base.getindex(c::ByHour, idxs::CartesianIndex{2}) = c.v[idxs[2]]
function Base.getindex(c::ByHour, year_idx::Int64, hour_idx::Int64)
    c.v[hour_idx]::Float64
end
function Base.getindex(c::ByYearAndHour, year_idx::Int64, hour_idx::Int64)
    c.v[year_idx][hour_idx]::Float64
end
Base.getindex(c::ByYearAndHour, idxs::CartesianIndex{2}) = c.v[idxs[1]][idxs[2]]


function Base.getindex(c::ByYearAndHour, year_idx, hour_idx::Colon)
    c_arr = c.v[year_idx]
    return c_arr
end
function Base.getindex(n::Number, year_idx::Int64, hour_idx::Int64)
    return n
end
function Base.getindex(n::Number, year_idx::Int64, hour_idx::Colon)
    return n
end
function Base.getindex(n::Number, idx::Int64, year_idx::Int64, hour_idx::Int64)
    return n
end
function Base.getindex(n::Number, idx::Int64, year_idx::Int64, hour_idx::Colon)
    return n
end

function Base.getindex(c::HoursContainer, y::Int64, h::Int64)
    return c.v[h]
end
function Base.getindex(c::HoursContainer, i::Int64, y::Int64, h::Int64)
    return c.v[h]
end

# For vector of AbstractMatrixes
function _getindex(v::Vector{<:AbstractMatrix{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]::Float64
end

# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
# _getindex is to protect us from having to overwrite getindex in a bad way for common types.
function _getindex(v::Vector{<:AbstractVector{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y]::Float64
end
function _getindex(v::Vector{<:AbstractVector{<:Real}}, i::Int64, y::Int64)
    return v[i][y]::Float64
end
_getindex(c::Container, i::Int64, y::Int64, h::Int64) = c[y,h]::Float64
_getindex(c::Container, i::Int64, y::Int64) = c[y,(:)]::Float64
_getindex(c::Container, i::Int64) = error("Cannot use _getindex into container $c with a single index")
function _getindex(args...)
    res = getindex(args...) |> Float64
    return res::Float64
end



# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
function Base.getindex(v::Vector{<:Real}, i::Int64, y::Int64, h::Int64)
    return v[i]
end
function Base.getindex(v::Vector{<:Real}, i::Int64, y::Int64)
    return v[i]
end

function Base.getindex(v::Vector{<:Container}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]
end
function Base.getindex(v::Vector{<:Container}, i::Int64, y::Int64)
    return v[i][y,(:)]
end

###############################################################################
# Yearly Adjust
###############################################################################
function operate_yearly(oper::AbstractString, args...)
    oper == "add"   && return add_yearly(args...)
    oper == "scale" && return scale_yearly(args...)
    oper == "set"   && return set_yearly(args...)
end

"""
    set_yearly(c::Container, v::Vector{<:Number}) -> Container 

Sets the yearly values for `c`.
"""
function set_yearly(c::ByNothing, v::Vector{<:Number})
    return OriginalContainer(c.v, ByYear(v))
end
function set_yearly(c::OriginalContainer, v::Vector{<:Number})
    return OriginalContainer(c.original, set_yearly(c.v, v))
end
function set_yearly(c::ByYear, v::Vector{<:Number})
    return ByYear(v)
end
function set_yearly(c::ByHour, v::Vector{<:Number})
    return ByYear(v)
end
function set_yearly(c::ByYearAndHour, v::Vector{<:Number})
    return ByYear(v)
end

"""
    set_yearly(c::Container, v::Float64, yr_idx::Int64, nyr::Int64) -> c'
"""
function set_yearly(c::OriginalContainer, v::Number, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, set_yearly(c.v, v, yr_idx, nyr))
end
function set_yearly(c::ByNothing, x::Number, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] = x
    return OriginalContainer(c.v, ByYear(v))
end
function set_yearly(c::ByYear, x::Number, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] = x
    return ByYear(v)
end
function set_yearly(c::ByYearAndHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = map(copy, c.v)
    v[yr_idx] .= x
    return ByYearAndHour(v)
end
function set_yearly(c::ByHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .= x
    return ByYearAndHour(v)
end

"""
    add_yearly(c::Container, v::Vector{Float64}) -> Container 

adds the yearly values for `c`.
"""
function add_yearly(c::ByNothing, v::Vector{<:Number})
    return OriginalContainer(c.v, ByYear(c.v .+ v))
end
function add_yearly(c::OriginalContainer, v::Vector{<:Number})
    return OriginalContainer(c.original, add_yearly(c.v, v))
end
function add_yearly(c::ByYear, v::Vector{<:Number})
    return ByYear(c.v .+ v)
end
function add_yearly(c::ByHour, v::Vector{<:Number})
    vv = map(v) do x
        c.v .+ x
    end
    return ByYearAndHour(vv)
end
function add_yearly(c::ByYearAndHour, v::Vector{<:Number})
    v′ = map(copy, c.v)
    for _v in v′
        _v .+= v
    end
    return ByYearAndHour(v′)
end

"""
    add_yearly(c::Container, v::Float64, yr_idx::Int64, nyr) -> c'
"""
function add_yearly(c::OriginalContainer, v::Number, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, add_yearly(c.v, v, yr_idx, nyr))
end
function add_yearly(c::ByNothing, x::Number, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] += x
    return OriginalContainer(c.v, ByYear(v))
end
function add_yearly(c::ByYear, x::Number, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] += x
    return ByYear(v)
end
function add_yearly(c::ByYearAndHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = map(copy, c.v)
    v[yr_idx] .+= x
    return ByYearAndHour(v)
end
function add_yearly(c::ByHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .+= x
    return ByYearAndHour(v)
end



"""
    scale_yearly(c::Container, v::Vector{Float64}) -> Container 

scales the yearly values for `c`.
"""
function scale_yearly(c::ByNothing, v::Vector{<:Number})
    return OriginalContainer(c.v, ByYear(c.v .* v))
end
function scale_yearly(c::OriginalContainer, v::Vector{<:Number})
    return OriginalContainer(c.original, scale_yearly(c.v, v))
end
function scale_yearly(c::ByYear, v::Vector{<:Number})
    return ByYear(c.v .* v)
end
function scale_yearly(c::ByYear, n::Number)
    return ByYear(c.v .* n)
end
function scale_yearly(c::ByHour, v::Vector{<:Number})
    vv = map(v) do x
        c.v .* x
    end
    return ByYearAndHour(vv)
end
function scale_yearly(c::ByYearAndHour, v::Vector{<:Number})
    v′ = map(copy, c.v)
    for _v in v′
        _v .*= v
    end
    return ByYearAndHour(v′)
end
function scale_yearly(c::Number, v::Vector{<:Number})
    return ByYear(c .* v)
end
function scale_yearly(c::ByYear, v::OriginalContainer)
    return scale_yearly(c, v.v)
end
function scale_yearly(c::OriginalContainer, v::ByYear)
    return scale_yearly(c, v.v)
end
function scale_yearly(c::ByYear, v::ByNothing)
    return scale_yearly(c, v.v)
end

"""
    scale_yearly(c::Container, v::Float64, yr_idx::Int64, nyr) -> c'
"""
function scale_yearly(c::OriginalContainer, v::Number, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, scale_yearly(c.v, v, yr_idx, nyr))
end
function scale_yearly(c::ByNothing, x::Number, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] *= x
    return OriginalContainer(c.v, ByYear(v))
end
function scale_yearly(c::ByYear, x::Number, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] *= x
    return ByYear(v)
end
function scale_yearly(c::ByYearAndHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = map(copy,c.v)
    v[yr_idx] .*= x
    return ByYearAndHour(v)
end
function scale_yearly(c::ByHour, x::Number, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .*= x
    return ByYearAndHour(v)
end
export scale_yearly




###############################################################################
# Hourly Adjust
###############################################################################
function operate_hourly(oper::AbstractString, args...)
    oper == "add"   && return add_hourly(args...)
    oper == "scale" && return scale_hourly(args...)
    oper == "set"   && return set_hourly(args...)
end

"""
    set_hourly(c::Container, v::Vector{Float64}, yr_idx, nyr) -> Container

Sets the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `nyr` - the total number of years.
"""
function set_hourly(c::ByNothing, v, yr_idx::Colon, nyr)
    return OriginalContainer(c.v, ByHour(v))
end
function set_hourly(c::OriginalContainer, args...)
    return OriginalContainer(c.original, set_hourly(c.v, args...))
end
function set_hourly(c::ByNothing, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:), nyr)
    end
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] = v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function set_hourly(c::ByYear, v, yr_idx::Colon, nyr)
    return ByHour(v)
end
function set_hourly(c::ByYear, v, yr_idx, nyr)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:), nyr)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
    end
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByHour, v, yr_idx::Colon, nyr)
    return ByHour(v)
end
function set_hourly(c::ByHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:), nyr)
    end
    vv = [copy(c.v) for i in 1:nyr]
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByYearAndHour, v, yr_idx::Colon, nyr)
    return ByHour(v)
end
function set_hourly(c::ByYearAndHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:), nyr)
    end
    v′ = map(copy, c.v)
    foreach(i->(v′[i] = v), yr_idx)
    return ByYearAndHour(v′)
end

"""
    add_hourly(c::Container, v::Vector{Float64}, yr_idx, nyr)

Adds the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `nyr` - the total number of years.
"""
function add_hourly(c::ByNothing, v, yr_idx::Colon, nyr)
    return OriginalContainer(c.v, ByHour(c.v .+ v))
end
function add_hourly(c::OriginalContainer, args...)
    return OriginalContainer(c.original, add_hourly(c.v, args...))
end
function add_hourly(c::ByNothing, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return add_hourly(c, v, (:), nyr)
    end
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] .+= v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function add_hourly(c::ByYear, v, yr_idx::Colon, nyr)
    vv = [_v .+ v for _v in c.v]
    return ByYearAndHour(vv)
end

function add_hourly(c::ByYear, v, yr_idx, nyr)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return add_hourly(c, v, (:), nyr)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
    end
    foreach(i->(vv[i] .+= v), yr_idx)
    return ByYearAndHour(vv)
end

function add_hourly(c::ByHour, v, yr_idx::Colon, nyr)
    return ByHour(c.v .+ v)
end
function add_hourly(c::ByHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return add_hourly(c, v, (:), nyr)
    end
    vv = [copy(c.v) for i in 1:nyr]
    foreach(i->(vv[i] .+= v), yr_idx)
    return ByYearAndHour(vv)
end

function add_hourly(c::ByYearAndHour, v, yr_idx::Colon, nyr)
    foreach(_v->_v .+= v, c.v)
    return c
end
function add_hourly(c::ByYearAndHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:length(c.v))
        return add_hourly(c, v, (:), nyr)
    end
    v′ = map(copy, c.v)
    foreach(i->(v′[i] .+= v), yr_idx)
    return ByYearAndHour(v′)
end







"""
    scale_hourly(c::Container, v::Vector{Float64}, yr_idx, nyr)

Scales the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `nyr` - the total number of years.
"""
function scale_hourly(c::ByNothing, v, yr_idx::Colon, nyr)
    return OriginalContainer(c.v, ByHour(c.v .* v))
end
function scale_hourly(c::OriginalContainer, args...)
    return OriginalContainer(c.original, scale_hourly(c.v, args...))
end
function scale_hourly(c::ByNothing, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return scale_hourly(c, v, (:), nyr)
    end
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] .*= v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function scale_hourly(c::ByYear, v, yr_idx::Colon, kwargs...)
    vv = [_v .* v for _v in c.v]
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByYear, v, yr_idx, nyr)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return scale_hourly(c, v, (:), nyr)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
    end
    foreach(i->(vv[i] .*= v), yr_idx)
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByHour, v, yr_idx::Colon, nyr)
    return ByHour(c.v .* v)
end
function scale_hourly(c::ByHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:nyr)
        return scale_hourly(c, v, (:), kwargs...)
    end
    vv = [copy(c.v) for i in 1:nyr]
    foreach(i->(vv[i] .*= v), yr_idx)
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByYearAndHour, v, yr_idx::Colon, nyr)
    foreach(_v->_v .*= v, c.v)
    return c
end
function scale_hourly(c::ByYearAndHour, v, yr_idx, nyr)
    if all(in(yr_idx), 1:length(c.v))
        return scale_hourly(c, v, (:), nyr)
    end
    v′ = map(copy, c.v)
    foreach(i->(v′[i] .*= v), yr_idx)
    return ByYearAndHour(v′)
end




"""
    LoadContainer()

Contains a vector of views of the load_array, so that it is possible to access by 
"""
struct LoadContainer <: Container{Float64, 2}
    v::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
end


_add_view!(c::LoadContainer, v) = push!(c.v, v)

LoadContainer() = LoadContainer(SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}[])
function Base.getindex(c::LoadContainer, year_idx, hour_idx)
    isempty(c.v) && return 0.0
    return sum(vv->vv[year_idx, hour_idx], c.v)::Float64
end
Base.size(c::LoadContainer) = size(first(c.v))


function Base.show(io::IO, c::LoadContainer)
    isempty(c.v) && return print(io, "empty LoadContainer")
    l,m = size(c.v[1])
    n = length(c.v)
    # print(io, "LoadContainer(")
    print(io, sum(c.v))
    # print(io, ")")
    # print(io, "$n-element LoadContainer of $(l)×$m Matrix")
end

"""
    to_container!(table, col_name)

Converts `table[!, :col_name]` to a `Vector{Container}`.
"""
function to_container!(table::DataFrame, col_name)
    v = to_container(table[!, col_name])::Vector{Container}
    table[!, col_name] = v
end
function to_container!(table::SubDataFrame, col_name)
    to_container!(getfield(table, :parent), col_name)::Vector{Container}
end

"""
    to_container(v) -> cv::Vector{Container}

Converts `v` to a `Vector{Container}`
"""
function to_container(v::Vector{Container})
    v
end
function to_container(v::Vector)
    Container[Container(x) for x in v]
end

export to_container!
export to_container

