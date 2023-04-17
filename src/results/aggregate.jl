"""
    aggregate_result(f::Function, data, table_name, col_name, idxs=(:), yr_idxs=(:), hr_idxs=(:)) -> x::Float64

Aggregate a result from `data`, via function `f`.  Aggregates differently depending on the [`Unit`](@ref) of the `col_name` provided, accessible via [`get_table_col_unit`](@ref).  `idxs`, `yr_idxs` and `hr_idxs` can be flexible (see [`get_row_idxs`](@ref), [`get_year_idxs`](@ref), and [`get_hour_idxs`](@ref)).

# Functions to choose from:
* [`total`](@ref) - compute the total of the thing.  If the column is a price or rate, computes the total spent.
* [`average`](@ref) - compute the average of the thing.
* `minimum` - find the minimum value in the range
* `maximum` - find the maximum value in the range

Note that some [`Unit`](@ref)s don't make sense for all of the functions above.  For example, it doesn't really make sense to have a `total` capacity factor, whereas an `average` capacity factor makes perfect sense.  If you define a new [`Unit`](@ref) and want it to work with one of the functions above, feel free to define a new method (it is probably only a couple of lines of code!)
"""
function aggregate_result(f::Function, data, table_name, col_name, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    table = get_table(data, table_name)
    unit = get_table_col_unit(data, table_name, col_name)
    _idxs = get_row_idxs(table, idxs)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)
    f(unit, data, table, col_name, _idxs, _yr_idxs, _hr_idxs)
end
export aggregate_result

"""
    aggregate_generation(data, grouping_col, idxs=(:), yr_idxs=(:), hr_idxs=(:)) -> d::OrderedDict

Aggregate the generation results by `grouping_col`.  Returns an OrderedDict where the keys are the grouping key, and the values are the energy generated.  `idxs`, `yr_idxs` and `hr_idxs` can be flexible (see [`get_row_idxs`](@ref), [`get_year_idxs`](@ref), and [`get_hour_idxs`](@ref)).
"""
function aggregate_generation(data, grouping_col, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    unit = get_table_col_unit(data, :gen, :egen)
    table = get_table(data, :gen, idxs)
    gen = get_table(data, :gen)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)
    gdf = groupby(table, grouping_col)
    d = OrderedDict()
    kk = sort(keys(gdf))
    for key in kk
        sdf = gdf[key]
        _idxs = getfield(sdf, :rows)
        d[key] = total(unit, data, gen, :egen, _idxs, _yr_idxs, _hr_idxs)
    end
    return d
end
export aggregate_generation

export total

function total(::Type{ShortTons}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    E = eltype(col)
    if ishourly(E)
        return total_sum(col, idxs, yr_idxs, hr_idxs)
    elseif isyearly(E)
        @assert hr_idxs == 1:get_num_hours(data) "Cannot aggregate yearly container unless all hours given"
        return total_sum(col, idxs, yr_idxs)
    else
        @assert hr_idxs == 1:get_num_hours(data) "Cannot aggregate single-value container unless all hours given"
        @assert yr_idxs == 1:get_num_years(data) "Cannot aggregate single-value container unless all years given"
        return total_sum(col, idxs)
    end
end

ishourly(::Type{<:ByNothing}) = false
ishourly(::Type{<:ByHour}) = true
ishourly(::Type{<:ByYearAndHour}) = true
ishourly(::Type{<:AbstractMatrix}) = true
ishourly(::Type{<:OriginalContainer{T}}) where T = ishourly(T)
ishourly(::Type) = false

"""
    isyearly(::Type) -> ::Bool

Returns whether or not a type is broken up by years.
"""
isyearly(::Type{<:ByNothing}) = false
isyearly(::Type{<:ByHour}) = false
isyearly(::Type{<:ByYearAndHour}) = true
isyearly(::Type{<:AbstractMatrix}) = true
isyearly(::Type{<:OriginalContainer{T}}) where T = isyearly(T)
isyearly(::Type{<:AbstractVector}) = true
isyearly(::Type) = false

function total(::Type{ShortTonsPerMWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function total(::Type{Dollars}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    E = eltype(col)
    if ishourly(E)
        return total_sum(col, idxs, yr_idxs, hr_idxs)
    elseif isyearly(E)
        @assert hr_idxs == 1:get_num_hours(data) "Cannot aggregate yearly container unless all hours given"
        return total_sum(col, idxs, yr_idxs)
    else
        @assert hr_idxs == 1:get_num_hours(data) "Cannot aggregate single-value container unless all hours given"
        @assert yr_idxs == 1:get_num_years(data) "Cannot aggregate single-value container unless all years given"
        return total_sum(col, idxs)
    end
end
function total(::Type{DollarsPerMWhServed}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :elserv], idxs, yr_idxs, hr_idxs)
end
function total(::Type{DollarsPerMWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function total(::Type{CreditsPerMWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function total(::Type{DollarsPerMWCapacity}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :pcap], idxs, yr_idxs, hr_idxs)
end
function total(::Type{DollarsPerShortTonCO2Captured}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :capt_co2], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhServed}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhCharged}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhDischarged}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhLoad}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhFlow}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhCurtailed}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end

"""
    total(::Type{MWCapacity}, data, table, column_name, idxs, yr_idxs, hr_idxs)

The total average load power of all elements corresponding to `idxs`
"""
function total(::Type{MWCapacity}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_sum(table[!, column_name], hc, idxs, yr_idxs, hr_idxs) / total_sum(hc, 1, yr_idxs, hr_idxs)
end
"""
    total(::Type{MWLoad}, data, table, column_name, idxs, yr_idxs, hr_idxs)

The total average load power of all elements corresponding to `idxs`
"""
function total(::Type{MWLoad}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_sum(table[!, column_name], hc, idxs, yr_idxs, hr_idxs) / total_sum(hc, 1, yr_idxs, hr_idxs)
end


function average(::Type{ShortTonsPerMWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_avg(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function average(::Type{CreditsPerMWhGenerated}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_avg(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
export average
function average(::Type{DollarsPerMWhServed}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_avg(table[!, column_name], table[!, :elserv], idxs, yr_idxs, hr_idxs)
end

"""
    average(::Type{MWLoad}, data, table, column_name, idxs, yr_idxs, hr_idxs)

The per-bus average load power.
"""
function average(::Type{MWLoad}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_avg(table[!, column_name], hc, idxs, yr_idxs, hr_idxs)
end

function average(::Type{MWhGeneratedPerMWhCapacity}, data, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    num = weighted_sum(table[!, column_name], table[!, :pcap], hc, idxs, yr_idxs, hr_idxs)
    den = weighted_sum(table.pcap, hc, idxs, yr_idxs, hr_idxs)
    return num / den
end


function Base.maximum(::Type, data, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    return maximum(col, idxs, yr_idxs, hr_idxs)
end

function Base.maximum(v, idxs, yr_idxs, hr_idxs)
    return maximum(_getindex(v, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

function Base.minimum(::Type, data, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    return minimum(col, idxs, yr_idxs, hr_idxs)
end

function Base.minimum(v, idxs, yr_idxs, hr_idxs)
    return minimum(_getindex(v, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

#########################################################################
# Aggregation utilities
#########################################################################

"""
    total_sum(v::Vector, idxs, yr_idxs, hr_idxs)

    total_sum(v::Vector, idxs, yr_idxs)

    total_sum(v::Vector, idxs)

Compute `sum(_getindex(v, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function total_sum(v, idxs, yr_idxs, hr_idxs)
    isempty(v) && return 0.0
    isempty(idxs) && return 0.0
    isempty(yr_idxs) && return 0.0
    isempty(hr_idxs) && return 0.0
    sum(_getindex(v, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

function total_sum(v, idxs, yr_idxs)
    isempty(v) && return 0.0
    isempty(idxs) && return 0.0
    isempty(yr_idxs) && return 0.0
    sum(_getindex(v,i,y) for i in idxs, y in yr_idxs)
end

function total_sum(v, idxs)
    isempty(v) && return 0.0
    isempty(idxs) && return 0.0
    sum(_getindex(v,i) for i in idxs)
end

"""
    weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)

Compute the `sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)
    isempty(v1) && return 0.0
    isempty(v2) && return 0.0
    isempty(idxs) && return 0.0
    isempty(yr_idxs) && return 0.0
    isempty(hr_idxs) && return 0.0
    sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

"""
    weighted_sum(v1, v2, v3, idxs, yr_idxs, hr_idxs)

Compute the `sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h)*_getindex(v3,i,y,h) for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function weighted_sum(v1, v2, v3, idxs, yr_idxs, hr_idxs)
    isempty(v1) && return 0.0
    isempty(v2) && return 0.0
    isempty(v3) && return 0.0
    isempty(idxs) && return 0.0
    isempty(yr_idxs) && return 0.0
    isempty(hr_idxs) && return 0.0
    sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h)*_getindex(v3,i,y,h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

"""
    weighted_avg(v1, v2, idxs, yr_idxs, hr_idxs)

Compute the `v2`-weighted average of `v1`.  I.e. computed [`weighted_sum`](@ref) divided by the sum of `v2`.
"""
function weighted_avg(v1, v2, idxs, yr_idxs, hr_idxs)
    ws = weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)
    s = sum(_getindex(v2, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
    return ws/s
end