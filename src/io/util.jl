
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
    1:get_num_years(data)
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
    1:get_num_hours(data)
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
* `p::Pair` - returns a Vector containing the index of each row for which `comparison(p[2], typeof(row[p[1]]))(row[p[1]])` is true.  See [`comparison`](@ref) 
* `pairs`, an iterator of `Pair`s - returns a Vector containing the indices which satisfy all the pairs as above.

Some possible pairs to filter by:
* `:country => "narnia"`: checks if the `country` column is equal to the string "narnia"
* `:emis_co2 => >=(0.1)`: checks if the `emis_co2` column is greater than or equal to 0.1
* `:age => (2,10)`: checks if the `age` column is between 2, and 10, inclusive.  To be exclusive, use different values like (2.0001, 9.99999) for clarity
* `:state => in(("alabama", "arkansas"))`: checks if the `state` column is either "alabama" or "arkansas"

See also [`filter_view`](@ref)
"""
function table_rows(table, idxs::Colon)
    return 1:nrow(table)
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

Returns the appropriate comparison function for `value` to be compared to the 2nd argument type.  Here are a few options:
* comparison(f::Function, ::Type) -> f
* comparison(s::String, ::String) -> 
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

function comparison(value::String, ::Type{<:AbstractString})
    return ==(value)
end

function comparison(value::String, ::Type)
    return x->string(x) == value
end

function comparison(value::Tuple{<:Real, <:Real}, ::Type{<:Real})
    lo, hi = value
    return x -> lo <= x <= hi
end

function comparison(value, ::Type)
    return ==(value)
end