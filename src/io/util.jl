
"""
    get_year_idxs(data, year_idxs) -> idxs

Converts `year_idxs` into a usable set of indices that can index into `get_years(data)`.  `year_idxs` can be any of the following types:
* `Colon`
* `Int64`
* `AbstractVector{Int64}`
* `AbstractString` - Representing the year, i.e. "y2020"
* `AbstractVector{<:AbstractString}` - a vector of strings representing the year, i.e. "y2020"
"""
function get_year_idxs(data, year_idxs::Colon)
    year_idxs
end
function get_year_idxs(data, year_idxs::AbstractVector{Int64})
    year_idxs
end
function get_year_idxs(data, year_idxs::Int64)
    year_idxs
end
function get_year_idxs(data, year_idxs::AbstractString)
    return findfirst(==(year_idxs), get_years(data))
end
function get_year_idxs(data, year_idxs::AbstractVector{<:AbstractString})
    yrs = get_years(data)
    return map(y->findfirst(==(y), yrs), year_idxs)
end
export get_year_idxs


"""
    get_hour_idxs(data, hour_idxs)

Converts `hour_idxs` into a usable set of indices that can index into hourly data.  `hour_idxs` can be any of the following types:
* `Colon`
* `Int64`
* `AbstractVector{Int64}`    
"""
function get_hour_idxs(data, hour_idxs::Colon)
    hour_idxs
end
function get_hour_idxs(data, hour_idxs::AbstractVector{Int64})
    hour_idxs
end
function get_hour_idxs(data, hour_idxs::Int64)
    hour_idxs
end
export get_hour_idxs

"""
    table_rows(table, idxs) -> row_idxs

Returns row indices of the passed-in table that correspond to idxs, where `idxs` can be:
* `::Colon` - all rows
* `::Int64` - a single row
* `::AbstractVector{Int64}` - a list of rows
* `p::Pair` - returns a Vector containing the index of each row for which row[p[1]] == p[2]
* `pairs`, an iterator of `Pair`s - returns a Vector containing the indices which satisfy all the pairs as above.

See also [`filter_view`](@ref)
"""
function table_rows(table, idxs::Colon)
    return idxs
end

function table_rows(table, idxs::AbstractVector{Int64})
    return idxs
end

function table_rows(table, idxs::Int64)
    return idxs
end

function table_rows(table, pairs)
    row_idxs = Int64[i for i in 1:nrow(table)]
    for pair in pairs
        key, val = pair
        v = table[!,key]
        comp = comparison(val, v)
        filter!(row_idx->comp(v[row_idx]), row_idxs)
    end

    return row_idxs
end
function table_rows(table, pair::Pair)
    row_idxs = Int64[i for i in 1:nrow(table)]
    key, val = pair
    v = table[!, key]
    comp = comparison(val, v)
    filter!(row_idx->comp(v[row_idx]), row_idxs)
    return row_idxs
end


"""
    comparison(value, v) -> comp

Returns the appropriate comparison function for `value` to be compared to each member of `v`.

    comparison(value, ::Type)

Returns the appropriate comparison function for `value` to be compared to the 2nd argument type.
"""
function comparison(value, v::AbstractVector)
    comparison(value, eltype(v))
end

function comparison(value::Function, ::Type)
    return value
end

function comparison(value::String, ::Type{<:Integer})
    num = parse(Int, value)
    return ==(num)
end

function comparison(value::Tuple{<:Real, <:Real}, ::Type{<:Real})
    lo, hi = value
    return x -> lo <= x <= hi
end

function comparison(value, ::Type)
    return ==(value)
end