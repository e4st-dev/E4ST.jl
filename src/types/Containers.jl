# Containers
################################################################################

"""
    abstract type Container

Abstract type for containers that can be indexed by year and time.  i.e. `c[yr_idx, hr_idx]` will work, even if `c` contains a single number, a number for each year, a number for each hour, or a number for each year and hour.
"""
abstract type Container end
export Container

Container(x::Number) = OriginalContainer(x, ByNothing(x))

Container(c::Container) = c

Base.isempty(c::Container) = false

mutable struct OriginalContainer{C} <: Container where {C<:Container}
    original::Float64
    v::C
end

OriginalContainer(x::Bool, v::Container) = OriginalContainer(Float64(x), v)

struct ByNothing <: Container 
    v::Float64
end
struct ByYear <: Container
    v::Vector{Float64}
end
struct ByHour <: Container
    v::Vector{Float64}
end
struct ByYearAndHour <: Container
    v::Vector{Vector{Float64}}
end
struct HoursContainer <: Container
    v::Vector{Float64}
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

function get_c_from_orig(c::OriginalContainer)
    return c.v
end
function get_c_from_orig(n::Number)
    return n
end
export get_c_from_orig




#########################################################
# Basic Functions
#########################################################

# Base.:-(c::ByNothing, n::Number) = ByNothing(c.v-n)
# Base.:+(c::ByNothing, n::Number) = ByNothing(c.v+n)
# Base.:*(c::ByNothing, n::Number) = ByNothing(c.v*n)
# Base.:/(c::ByNothing, n::Number) = ByNothing(c.v/n)

Base.:-(c1::ByNothing, c2::ByYear) = ByYear(c1.v .- c2.v)
Base.:+(c1::ByNothing, c2::ByYear) = ByYear(c1.v .+ c2.v)
Base.:*(c1::ByNothing, c2::ByYear) = ByYear(c1.v .* c2.v)
Base.:/(c1::ByNothing, c2::ByYear) = ByYear(c1.v ./ c2.v)

Base.:-(c1::ByYear, c2::ByNothing) = ByYear(c1.v .- c2.v)
Base.:+(c1::ByYear, c2::ByNothing) = ByYear(c1.v .+ c2.v)
Base.:*(c1::ByYear, c2::ByNothing) = ByYear(c1.v .* c2.v)
Base.:/(c1::ByYear, c2::ByNothing) = ByYear(c1.v ./ c2.v)

Base.:-(c::C, n::Number) where {C<:Container} = C(c.v .- n)
Base.:+(c::C, n::Number) where {C<:Container} = C(c.v .+ n)
Base.:*(c::C, n::Number) where {C<:Container} = C(c.v .* n)
Base.:/(c::C, n::Number) where {C<:Container} = C(c.v ./ n)

Base.:-(n::Number, c::C) where {C<:Container} = C(n .- c.v)
Base.:+(n::Number, c::C) where {C<:Container} = C(c.v .+ n)
Base.:*(n::Number, c::C) where {C<:Container} = C(c.v .* n)
Base.:/(n::Number, c::C) where {C<:Container} = C(n ./ c.v)

Base.:-(c1::ByYear, c2::ByYear) = ByYear(c1.v .- c2.v)
Base.:+(c1::ByYear, c2::ByYear) = ByYear(c1.v .+ c2.v)
Base.:*(c1::ByYear, c2::ByYear) = ByYear(c1.v .* c2.v)
Base.:/(c1::ByYear, c2::ByYear) = ByYear(c1.v ./ c2.v)

Base.:-(c::OriginalContainer, n::Number) = OriginalContainer(c.original, (c.v-n))
Base.:+(c::OriginalContainer, n::Number) = OriginalContainer(c.original, (c.v+n))
Base.:*(c::OriginalContainer, n::Number) = OriginalContainer(c.original, (c.v*n))
Base.:/(c::OriginalContainer, n::Number) = OriginalContainer(c.original, (c.v/n))

Base.:-(n::Number, c::OriginalContainer) = OriginalContainer(c.original, (n-c.v))
Base.:+(n::Number, c::OriginalContainer) = OriginalContainer(c.original, (c.v+n))
Base.:*(n::Number, c::OriginalContainer) = OriginalContainer(c.original, (c.v*n))
Base.:/(n::Number, c::OriginalContainer) = OriginalContainer(c.original, (n/c.v))

Base.:-(c1::OriginalContainer, c2::OriginalContainer) = Base.:-(c1.v, c2.v)
Base.:+(c1::OriginalContainer, c2::OriginalContainer) = Base.:+(c1.v, c2.v)
Base.:*(c1::OriginalContainer, c2::OriginalContainer) = Base.:*(c1.v, c2.v)
Base.:/(c1::OriginalContainer, c2::OriginalContainer) = Base.:/(c1.v, c2.v)

#(f::Function)(c::OriginalContainer, n::Number) = OriginalContainer(c.original, f(c.v, n))

# #TODO: this is not how c.original works, doesn't give the type just the original value so need to updated how this is done
# Base.:-(c1::OriginalContainer, c2::OriginalContainer) = oper_on_containers(c1, c2, -)
# Base.:+(c1::OriginalContainer, c2::OriginalContainer) = oper_on_containers(c1, c2, +)
# Base.:*(c1::OriginalContainer, c2::OriginalContainer) = oper_on_containers(c1, c2, *)
# Base.:/(c1::OriginalContainer, c2::OriginalContainer) = oper_on_containers(c1, c2, /)
# #TODO: possibly add warnings about adding or subtracting ByYear and ByHour from each other. Also maybe add something so ByYear and ByHour need to be multiplied in the right order. 



# function oper_on_containers(c1::Container, c2::Container, oper)
#     #calculate container values
#     oper == - && v = c1.v .- c2.v 
#     oper == + && v = c1.v .+ c2.v
#     oper == * && v = c1.v .* c2.v
#     oper == / && v = c1.v ./ c2.v

#     t1 = typeof(c1)
#     t2 = typeof(c2)

#     # determine the type of the resulting container
#     if t1 == t2
#         return t1
#     elseif t1 == ByYearAndHour || t2 == ByYearAndHour
#         return ByYearAndHour(v)
#     elseif (t1 == ByYear && t2 == ByHour) || (t2 == ByYear && t1 == ByHour)
#         return ByYearAndHour(v)
#     elseif t1 == ByYear || t2 == ByYear
#         return ByYear(v)
#     elseif t1 == ByHour || t2 == ByHour
#         return ByHour(v)
#     else
#         return ByNothing(v)
#     end

# end




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
function Base.getindex(c::ByHour, year_idx, hour_idx)
    c.v[hour_idx]::Float64
end
function Base.getindex(c::ByYearAndHour, year_idx, hour_idx)
    c.v[year_idx][hour_idx]::Float64
end
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

function Base.getindex(c::HoursContainer, y::Int64, h::Int64)
    return c.v[h]
end
function Base.getindex(c::HoursContainer, i::Int64, y::Int64, h::Int64)
    return c.v[h]
end

# For vector of AbstractMatrixes
function _getindex(v::Vector{<:AbstractMatrix{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]
end

# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
# _getindex is to protect us from having to overwrite getindex in a bad way for common types.
function _getindex(v::Vector{<:AbstractVector{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y]
end
function _getindex(v::Vector{<:AbstractVector{<:Real}}, i::Int64, y::Int64)
    return v[i][y]
end
_getindex(args...) = getindex(args...)


# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
function Base.getindex(v::Vector{<:Real}, i::Int64, y::Int64, h::Int64)
    return v[i]
end

function Base.getindex(v::Vector{<:Container}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]
end




function Base.max(n::Number, c::ByYear)
    maxs = zeros(length(c.v))
    for i in size(c.v)
        maxs[i] = max(n, c.v[i])
    end
    return ByYear(maxs)
end
function Base.max(n::Number, c::ByNothing)
    m = max(n, c.v)
    return ByNothing(m)
end
Base.max(n::Number, c::OriginalContainer) = max(n, c.v)
Base.max(c::OriginalContainer, n::Number) = max(n, c.v)

function Base.min(n::Number, c::ByYear)
    mins = zeros(length(c.v))
    for i in size(c.v)
        mins[i] = min(n, c.v[i])
    end
    return ByYear(mins)
end
function Base.min(n::Number, c::ByNothing)
    m = min(n, c.v)
    return ByNothing(m)
end
Base.min(n::Number, c::OriginalContainer) = min(n, c.v)
Base.min(c::OriginalContainer, n::Number) = min(n, c.v)




function Base.isless(n::Number, c::ByYear)
    x = zeros(length(c.v))
    for i in size(c.v)
        x[i] = isless(n, c.v[i]) 
    end
    return x
end
Base.isless(n::Number, c::OriginalContainer) = isless(n, c.v)
Base.isless(c::OriginalContainer, n::Number) = isless(n, c.v)


function Base.length(c::Container)
    return length(c.v)   
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
    set_yearly(c::Container, v::Vector{Float64}) -> Container 

Sets the yearly values for `c`.
"""
function set_yearly(c::ByNothing, v::Vector{Float64})
    return OriginalContainer(c.v, ByYear(v))
end
function set_yearly(c::OriginalContainer, v::Vector{Float64})
    return OriginalContainer(c.original, set_yearly(c.v, v))
end
function set_yearly(c::ByYear, v::Vector{Float64})
    return ByYear(v)
end
function set_yearly(c::ByHour, v::Vector{Float64})
    return ByYear(v)
end
function set_yearly(c::ByYearAndHour, v::Vector{Float64})
    return ByYear(v)
end

"""
    set_yearly(c::Container, v::Float64, yr_idx::Int64, nyr::Int64) -> c'
"""
function set_yearly(c::OriginalContainer, v::Float64, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, set_yearly(c.v, v, yr_idx, nyr))
end
function set_yearly(c::ByNothing, x::Float64, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] = x
    return OriginalContainer(c.v, ByYear(v))
end
function set_yearly(c::ByYear, x::Float64, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] = x
    return ByYear(v)
end
function set_yearly(c::ByYearAndHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = map(copy, c.v)
    v[yr_idx] .= x
    return ByYearAndHour(v)
end
function set_yearly(c::ByHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .= x
    return ByYearAndHour(v)
end


"""
    add_yearly(c::Container, v::Vector{Float64}) -> Container 

adds the yearly values for `c`.
"""
function add_yearly(c::ByNothing, v::Vector{Float64})
    return OriginalContainer(c.v, ByYear(c.v .+ v))
end
function add_yearly(c::OriginalContainer, v::Vector{Float64})
    return OriginalContainer(c.original, add_yearly(c.v, v))
end
function add_yearly(c::ByYear, v::Vector{Float64})
    return ByYear(c.v .+ v)
end
function add_yearly(c::ByHour, v::Vector{Float64})
    vv = map(v) do x
        c.v .+ x
    end
    return ByYearAndHour(vv)
end
function add_yearly(c::ByYearAndHour, v::Vector{Float64})
    v′ = map(copy, c.v)
    for _v in v′
        _v .+= v
    end
    return ByYearAndHour(v′)
end

"""
    add_yearly(c::Container, v::Float64, yr_idx::Int64, nyr) -> c'
"""
function add_yearly(c::OriginalContainer, v::Float64, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, add_yearly(c.v, v, yr_idx, nyr))
end
function add_yearly(c::ByNothing, x::Float64, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] += x
    return OriginalContainer(c.v, ByYear(v))
end
function add_yearly(c::ByYear, x::Float64, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] += x
    return ByYear(v)
end
function add_yearly(c::ByYearAndHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = map(copy, c.v)
    v[yr_idx] .+= x
    return ByYearAndHour(v)
end
function add_yearly(c::ByHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .+= x
    return ByYearAndHour(v)
end





"""
    scale_yearly(c::Container, v::Vector{Float64}) -> Container 

scales the yearly values for `c`.
"""
function scale_yearly(c::ByNothing, v::Vector{Float64})
    return OriginalContainer(c.v, ByYear(c.v .* v))
end
function scale_yearly(c::OriginalContainer, v::Vector{Float64})
    return OriginalContainer(c.original, scale_yearly(c.v, v))
end
function scale_yearly(c::ByYear, v::Vector{Float64})
    return ByYear(c.v .* v)
end
function scale_yearly(c::ByHour, v::Vector{Float64})
    vv = map(v) do x
        c.v .* x
    end
    return ByYearAndHour(vv)
end
function scale_yearly(c::ByYearAndHour, v::Vector{Float64})
    v′ = map(copy, c.v)
    for _v in v′
        _v .*= v
    end
    return ByYearAndHour(v′)
end
function scale_yearly(c::Number, v::Vector{Float64})
    return ByYear(c .* v)
end

"""
    scale_yearly(c::Container, v::Float64, yr_idx::Int64, nyr) -> c'
"""
function scale_yearly(c::OriginalContainer, v::Float64, yr_idx::Int64, nyr::Int64)
    return OriginalContainer(c.original, scale_yearly(c.v, v, yr_idx, nyr))
end
function scale_yearly(c::ByNothing, x::Float64, yr_idx::Int64, nyr::Int64)
    v = fill(c.v, nyr)
    v[yr_idx] *= x
    return OriginalContainer(c.v, ByYear(v))
end
function scale_yearly(c::ByYear, x::Float64, yr_idx::Int64, nyr::Int64)
    v = copy(c.v)
    v[yr_idx] *= x
    return ByYear(v)
end
function scale_yearly(c::ByYearAndHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = map(copy,c.v)
    v[yr_idx] .*= x
    return ByYearAndHour(v)
end
function scale_yearly(c::ByHour, x::Float64, yr_idx::Int64, nyr::Int64)
    v = [copy(c.v) for _ in 1:nyr]
    v[yr_idx] .*= x
    return ByYearAndHour(v)
end





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
struct LoadContainer <: Container
    v::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
end

_add_view!(c::LoadContainer, v) = push!(c.v, v)

LoadContainer() = LoadContainer(SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}[])
function Base.getindex(c::LoadContainer, year_idx, hour_idx)
    isempty(c.v) && return 0.0
    return sum(vv->vv[year_idx, hour_idx], c.v)::Float64
end

function Base.show(io::IO, c::LoadContainer)
    isempty(c.v) && return print(io, "empty LoadContainer")
    l,m = size(c.v[1])
    n = length(c.v)
    print(io, "$n-element LoadContainer of $(l)×$m Matrix")
end


function _to_container!(table::DataFrame, col_name)
    v = _to_container(table[!, col_name])::Vector{Container}
    table[!, col_name] = v
end
function _to_container!(table::SubDataFrame, col_name)
    _to_container!(getfield(table, :parent), col_name)::Vector{Container}
end
function _to_container(v::Vector{Container})
    v
end
function _to_container(v::Vector)
    Container[ByNothing(x) for x in v]
end

