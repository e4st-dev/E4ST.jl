# Containers
################################################################################

"""
    abstract type Container

Abstract type for containers that can be indexed by year and time.
"""
abstract type Container end

Base.isempty(c::Container) = false

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
function Base.getindex(v::Vector{<:AbstractMatrix{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]
end

# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
function Base.getindex(v::Vector{<:AbstractVector{<:Real}}, i::Int64, y::Int64, h::Int64)
    return v[i][y]
end

# Assume that if we are trying to index into a vector of vectors, it is for yearly data only
function Base.getindex(v::Vector{<:Real}, i::Int64, y::Int64, h::Int64)
    return v[i]
end

function Base.getindex(v::Vector{<:Container}, i::Int64, y::Int64, h::Int64)
    return v[i][y,h]
end

###############################################################################
# Yearly Adjust
###############################################################################
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
    for _v in c.v
        _v .+= v
    end
    return c
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
    for _v in c.v
        _v .*= v
    end
    return c
end





###############################################################################
# Hourly Adjust
###############################################################################

"""
    set_hourly(c::Container, v::Vector{Float64}, yr_idx; default, nyr) -> Container

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
function set_hourly(c::ByYear, v, yr_idx; nyr=nothing)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:); nyr)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
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
    vv = [copy(c.v) for i in 1:nyr]
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
    add_hourly(c::Container, v::Vector{Float64}, yr_idx; nyr)

Adds the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `nyr` - the total number of years.
"""
function add_hourly(c::ByNothing, v, yr_idx::Colon; kwargs...)
    return OriginalContainer(c.v, ByHour(c.v .+ v))
end
function add_hourly(c::OriginalContainer, args...; kwargs...)
    return OriginalContainer(c.original, add_hourly(c.v, args...; kwargs...))
end
function add_hourly(c::ByNothing, v, yr_idx; nyr=nothing)
    @assert nyr !== nothing error("Attempting to add hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return add_hourly(c, v, (:); nyr)
    end
    default_hourly = fill(c.v, size(v))
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] .+= v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function add_hourly(c::ByYear, v, yr_idx::Colon; kwargs...)
    vv = [_v .+ v for _v in c.v]
    return ByYearAndHour(vv)
end

function add_hourly(c::ByYear, v, yr_idx; kwargs...)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return add_hourly(c, v, (:); kwargs...)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
    end
    foreach(i->(vv[i] .+= v), yr_idx)
    return ByYearAndHour(vv)
end

function add_hourly(c::ByHour, v, yr_idx::Colon; kwargs...)
    return ByHour(c.v .+ v)
end
function add_hourly(c::ByHour, v, yr_idx; nyr=nothing, kwargs...)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return add_hourly(c, v, (:); default, kwargs...)
    end
    vv = [copy(c.v) for i in 1:nyr]
    foreach(i->(vv[i] .+= v), yr_idx)
    return ByYearAndHour(vv)
end

function add_hourly(c::ByYearAndHour, v, yr_idx::Colon; kwargs...)
    foreach(_v->_v .+= v, c.v)
    return c
end
function add_hourly(c::ByYearAndHour, v, yr_idx; kwargs...)
    if all(in(yr_idx), 1:length(c.v))
        return add_hourly(c, v, (:); default, kwargs...)
    end
    foreach(i->(c.v[i] .+= v), yr_idx)
    return c
end







"""
    scale_hourly(c::Container, v::Vector{Float64}, yr_idx; nyr)

Scales the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `nyr` - the total number of years.
"""
function scale_hourly(c::ByNothing, v, yr_idx::Colon; kwargs...)
    return OriginalContainer(c.v, ByHour(c.v .* v))
end
function scale_hourly(c::OriginalContainer, args...; kwargs...)
    return OriginalContainer(c.original, scale_hourly(c.v, args...; kwargs...))
end
function scale_hourly(c::ByNothing, v, yr_idx; nyr=nothing)
    @assert nyr !== nothing error("Attempting to scale hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return scale_hourly(c, v, (:); nyr)
    end
    default_hourly = fill(c.v, size(v))
    vv = [fill(c.v, size(v)) for i in 1:nyr]
    foreach(i->(vv[i] .*= v), yr_idx)
    return OriginalContainer(c.v, ByYearAndHour(vv))
end

function scale_hourly(c::ByYear, v, yr_idx::Colon; kwargs...)
    vv = [_v .* v for _v in c.v]
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByYear, v, yr_idx; nyr=nothing)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return scale_hourly(c, v, (:); nyr)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, size(v))
    end
    foreach(i->(vv[i] .*= v), yr_idx)
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByHour, v, yr_idx::Colon; kwargs...)
    return ByHour(c.v .* v)
end
function scale_hourly(c::ByHour, v, yr_idx; nyr=nothing, kwargs...)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return scale_hourly(c, v, (:); default, kwargs...)
    end
    vv = [copy(c.v) for i in 1:nyr]
    foreach(i->(vv[i] .*= v), yr_idx)
    return ByYearAndHour(vv)
end

function scale_hourly(c::ByYearAndHour, v, yr_idx::Colon; kwargs...)
    foreach(_v->_v .*= v, c.v)
    return c
end
function scale_hourly(c::ByYearAndHour, v, yr_idx; kwargs...)
    if all(in(yr_idx), 1:length(c.v))
        return scale_hourly(c, v, (:); default, kwargs...)
    end
    foreach(i->(c.v[i] .*= v), yr_idx)
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

