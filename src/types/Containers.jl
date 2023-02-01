# Containers
################################################################################

"""
    abstract type Container

Abstract type for containers that can be indexed by year and time.
"""
abstract type Container end

mutable struct OriginalContainer{C} <: Container where {C<:Container}
    original::Float64
    v::C
end
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



"""
    set_hourly(c::Container, v::Vector{Float64}, yr_idx; default, nyr)

Sets the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `default` - the default hourly values for years not specified, if they aren't already set.
* `nyr` - the total number of years.
"""
function set_hourly(c::ByNothing, v, yr_idx::Colon; kwargs...)
    return OriginalContainer(c.v, ByHour(v))
end
function set_hourly(c::OriginalContainer, args...; kwargs...)
    return OriginalContainer(c.original, set_hourly(c.v, args...; kwargs...))
end
function set_hourly(c::ByNothing, v, yr_idx; nyr=nothing)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:); nyr)
    end
    default_hourly = fill(c.v, size(v))
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] = v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function set_hourly(c::ByYear, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByYear, v, yr_idx; kwargs...)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:); kwargs...)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, nyr)
    end
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByHour, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByHour, v, yr_idx; nyr=nothing, kwargs...)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:); default, kwargs...)
    end
    vv = fill(v, nyr)
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByYearAndHour, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByYearAndHour, v, yr_idx; kwargs...)
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:); default, kwargs...)
    end
    foreach(i->(c.v[i] = v), yr_idx)
    return c
end

"""
    DemandContainer()

Contains a vector of views of the demand_array, so that it is possible to access by 
"""
struct DemandContainer <: Container
    v::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
end

_add_view!(c::DemandContainer, v) = push!(c.v, v)

DemandContainer() = DemandContainer(SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}[])
function Base.getindex(c::DemandContainer, year_idx, hour_idx)
    isempty(c.v) && return 0.0
    return sum(vv->vv[year_idx, hour_idx], c.v)::Float64
end

function Base.show(io::IO, c::DemandContainer)
    isempty(c.v) && return print(io, "empty DemandContainer")
    l,m = size(c.v[1])
    n = length(c.v)
    print(io, "$n-element DemandContainer of $(l)×$m Matrix")
end

