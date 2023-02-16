
"""
    get_year_idxs(data, year_idxs) -> idxs

Converts `year_idxs` into a usable set of indices that can index into `get_years(data)`.  `year_idxs` can be any of the following types:
* `Colon`
* `Int64`
* `AbstractVector{Int64}`
* `AbstractString` - Representing the year, i.e. "y2020"
* `AbstractVector{<:AbstractString}` - a vector of strings representing the year, i.e. "y2020"
* `Tuple{<:AbstractString, <:AbstractString}`
* `Function` - a function of the year string that returns a boolean.  I.e. <=("y2030")
"""
function get_year_idxs(data, year_idxs::Colon)
    1:get_num_years(data)
end
function get_year_idxs(data, f::Function)
    yrs = get_years(data)
    return [i for i in 1:length(yrs) if f(yrs[i])]
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
function get_year_idxs(data, year_string_range::Tuple{<:AbstractString, <:AbstractString})
    comp = ys->year_string_range[1]<=ys<=year_string_range[2]
    yrs = get_years(data)
    return [i for i in 1:length(yrs) if comp(yrs[i])]
end
export get_year_idxs



"""
    year2int(year) -> 

Converts the year given as a String into a Int64.
"""
function year2int(year::AbstractString)
    year = chop(year, head = 1, tail = 0)
    year = parse(Int64, year)
    return year
end
export year2int

"""
    year2str(year) -> 

Converts the year given as an Int to a String in the standard "yXXXX" format.
"""
function year2str(year::Int)
    str_year = "y"*string(year)
    return str_year
end
export year2str

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
function get_hour_idxs(data, pairs)
    return get_row_idxs(get_table(data, :hours), pairs)
end
export get_hour_idxs

"""
    get_row_idxs(table, conditions) -> row_idxs

Returns row indices of the passed-in table that correspond to `conditions`, where `conditions` can be:
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
function get_row_idxs(table, idxs::Colon)
    return 1:nrow(table)
end

function get_row_idxs(table, idxs::AbstractVector{Int64})
    return idxs
end

function get_row_idxs(table, idxs::Int64)
    return idxs
end

function get_row_idxs(table, pairs)
    row_idxs = Int64[i for i in 1:nrow(table)]
    for pair in pairs
        key, val = pair
        v = table[!,key]
        comp = comparison(val, v)
        filter!(row_idx->comp(v[row_idx]), row_idxs)
    end

    return row_idxs
end
function get_row_idxs(table, pairs::Pair...)
    row_idxs = Int64[i for i in 1:nrow(table)]
    for pair in pairs
        key, val = pair
        v = table[!,key]
        comp = comparison(val, v)
        filter!(row_idx->comp(v[row_idx]), row_idxs)
    end

    return row_idxs
end
function get_row_idxs(table, pair::Pair)
    row_idxs = Int64[i for i in 1:nrow(table)]
    key, val = pair
    v = table[!, key]
    comp = comparison(val, v)
    filter!(row_idx->comp(v[row_idx]), row_idxs)
    return row_idxs
end
export table_rows


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

function comparison(value::AbstractString, ::Type{<:Integer})
    num = parse(Int, value)
    return ==(num)
end

function comparison(value::AbstractString, ::Type{<:AbstractString})
    return ==(value)
end

function comparison(value::AbstractString, ::Type)
    return x->string(x) == value
end

function comparison(value::Tuple{<:Real, <:Real}, ::Type{<:Real})
    lo, hi = value
    return x -> lo <= x <= hi
end

function comparison(value::Vector, ::Type)
    return in(value)
end

function comparison(value::Tuple{<:AbstractString, <:AbstractString}, ::Type{<:AbstractString})
    lo, hi = value
    return x -> lo <= x <= hi
end

function comparison(value, ::Type)
    return ==(value)
end

"""
    parse_comparison(table, s) -> comp

Parses the string, `s` for a comparison with which to filter `table`.

Possible examples of strings `s` to parse:
* `"country=>narnia"` - All rows for which row.country=="narnia"
* `"bus_idx=>5"` - All rows for which row.bus_idx==5
* `"year_on=>(y2002,y2030)"` - All rows for which `row.year_on` is between 2002 and 2030, inclusive.
* `"emis_co2=>(0.0,4.99)"` - All rows for which `row.emis_co2` is between 0.0 and 4.99, inclusive. (Works for integers and negatives too)
* `"emis_co2=> >(0)"` - All rows for which `row.emis_co2` is greater than 0 (Works for integers and negatives too)
* `"year_on=> >(y2002)` - All rows for which `row.year_on` is greater than "y2002" (works for fractional years too, such as "y2002.4")
* `"genfuel=>[ng, wind, solar]"` - All rows for which `row.genfuel` is "ng", "wind", or "solar".  Works for Ints and Floats too.
"""
function parse_comparison(_s::AbstractString)
    s = replace(_s, ' '=>"")
    # In the form "country=>narnia" or "bus_idx=>5"
    if (m = match(r"(\w+)=>(\w+)", s)) !== nothing
        return m.captures[1]=>m.captures[2]
    end

    # In the form "emis_rate=>(0.0001,4.9999)" (should work for Ints, negatives, and Inf too)
    if (m=match(r"(\w+)=>\((-?(?:Inf)?[\d.]*),-?(?:Inf)?([\d.]*)\)", s)) !== nothing
        r1 = parse(Float64, m.captures[2])
        r2 = parse(Float64, m.captures[3])
        return m.captures[1]=>(r1, r2)
    end

    # In the form "year_on=>(y2020, y2030)"
    if (m=match(r"(\w+)=>\((y[\d]{4}),(y[\d]{4})\)", s)) !== nothing
        return m.captures[1]=>(m.captures[2], m.captures[3])
    end

    # In the form "emis_rate=>>(0)" (should work for Ints, negatives)
    if (m=match(r"(\w+)=>>\(?(-?[\d.]+)\)?", s)) !== nothing
        r1 = parse(Float64, m.captures[2])
        return m.captures[1]=>>(r1)
    end

    # In the form "emis_rate=>>(0)" (should work for Ints, negatives, and Inf too)
    if (m=match(r"(\w+)=>([><]{1}=?)\(?(-?[\d.]+)\)?", s)) !== nothing
        r1 = parse(Float64, m.captures[3])
        m.captures[2]==">" && (comp = >(r1))
        m.captures[2]=="<" && (comp = <(r1))
        m.captures[2]==">=" && (comp = >=(r1))
        m.captures[2]=="<=" && (comp = <=(r1))
        return m.captures[1]=>comp
    end

    # In the form "emis_rate=>>(0)" (should work for Ints, negatives, and Inf too)
    if (m=match(r"(\w+)=>([><]{1}=?)\(?(-?[\d.]+)\)?", s)) !== nothing
        r1 = parse(Float64, m.captures[3])
        m.captures[2]==">" && (comp = >(r1))
        m.captures[2]=="<" && (comp = <(r1))
        m.captures[2]==">=" && (comp = >=(r1))
        m.captures[2]=="<=" && (comp = <=(r1))
        return m.captures[1]=>comp
    end

    # In the form "year_on=> >(y2020)" (should work decimals)
    if (m=match(r"(\w+)=>([><]{1}=?)\(?(y[\d.]+)\)?", s)) !== nothing
        r1 = String(m.captures[3])
        m.captures[2]==">" && (comp = >(r1))
        m.captures[2]=="<" && (comp = <(r1))
        m.captures[2]==">=" && (comp = >=(r1))
        m.captures[2]=="<=" && (comp = <=(r1))
        return m.captures[1]=>comp
    end

    # In the form "genfuel=>[ng,solar,wind]"
    if (m=match(r"(\w+)=>\[([\w,.]*)\]", s)) !== nothing
        ar = str2array(m.captures[2])
        return m.captures[1]=>ar
    end


end
export parse_comparison

function parse_comparisons(row::DataFrameRow)
    pairs = []
    for i in 1:10000
        name = "filter$i"
        hasproperty(row, name) || break
        s = row[name]
        isempty(s) && break
        pair = parse_comparison(s)
        push!(pairs, pair)
    end
    
    # Check for area/subarea
    if hasproperty(row, :area) && ~isempty(row.area) && hasproperty(row, :subarea) && ~isempty(row.subarea)
        push!(pairs, row.area=>row.subarea)
    end

    # Check for genfuel and gentype
    hasproperty(row, :genfuel) && ~isempty(row.genfuel) && push!(pairs, :genfuel=>row.genfuel)
    hasproperty(row, :gentype) && ~isempty(row.gentype) && push!(pairs, :gentype=>row.gentype)
    hasproperty(row, :load_type) && ~isempty(row.load_type) && push!(pairs, :load_type=>row.load_type)
    
    return pairs
end


"""
    parse_year_idxs(s::AbstractString) -> comparisons

Parse a year comparison.  Could take the following forms:
* `"y2020"` - year 2020 only
* `""` - All years, returns (:)
* `"1"` - year index 1
* `"[1,2,3]"`
"""
function parse_year_idxs(_s::AbstractString)
    isempty(_s) && return (:)
    s = replace(_s, ' '=>"")
    if (m=match(r"y[\d]{4}", s)) !== nothing
        return m.match
    end
    if (m=match(r"\d*", s)) !== nothing
        return parse(Int64, m.match)
    end
    if (m = match(r"(\w+)=>(\w+)", s)) !== nothing
        return m.captures[1]=>m.captures[2]
    end

    error("No match found for $s")
end



"""
    parse_hour_idxs(s::AbstractString) -> comparisons

Parse a year comparison.  Could take the following forms:
* `"1"` - hour 1 only
* `""` - All hours, returns (:)
* `"season=>winter"` - returns "season"=>"winter"
"""
function parse_hour_idxs(_s::AbstractString)
    s = replace(_s, ' '=>"")
    isempty(s) && return (:)
    
    # "1"
    if (m=match(r"\d+", s)) !== nothing
        return parse(Int64, m.match)
    end
    
    # "season=>winter"
    if (m = match(r"(\w+)=>(\w+)", s)) !== nothing
        return m.captures[1]=>m.captures[2]
    end

    error("No match found for $s")
end

function str2array(s::AbstractString)
    v = split(s,',')
    v_int = tryparse.(Int64, v)
    v_int isa Vector{Int64} && return v_int
    v_float = tryparse.(Float64, v)
    v_float isa Vector{Float64} && return v_float
    return String.(v)
end

"""
    scale_hourly!(demand_arr, shape, row_idx, yr_idx)
    
Scales the hourly demand in `demand_arr` by `shape` for `row_idx` and `yr_idx`.
"""
function scale_hourly!(demand_arr, shape, row_idxs, yr_idxs)
    for yr_idx in yr_idxs, row_idx in row_idxs
        scale_hourly!(demand_arr, shape, row_idx, yr_idx)
    end
    return nothing
end
function scale_hourly!(ars::AbstractArray{<:AbstractArray}, shape, yr_idxs)
    for ar in ars, yr_idx in yr_idxs
        scale_hourly!(ar, shape, yr_idx)
    end
    return nothing
end
function scale_hourly!(ar::AbstractArray{Float64}, shape, yr_idxs)
    for yr_idx in yr_idxs
        scale_hourly!(ar, shape, yr_idx)
    end
    return nothing
end
function scale_hourly!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, idxs::Int64...)
    view(ar, idxs..., :) .+= shape
    return nothing
end

"""
    add_hourly!(ar, shape, row_idx, yr_idx)

    add_hourly!(ar, shape, row_idxs, yr_idxs)
    
adds to the hourly demand in `ar` by `shape` for `row_idx` and `yr_idx`.
"""
function add_hourly!(ar, shape, row_idxs, yr_idxs; kwargs...)
    for yr_idx in yr_idxs, row_idx in row_idxs
        add_hourly!(ar, shape, row_idx, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ars::AbstractArray{<:AbstractArray}, shape, yr_idxs; kwargs...)
    for ar in ars, yr_idx in yr_idxs
        add_hourly!(ar, shape, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ar::AbstractArray{Float64}, shape, yr_idxs; kwargs...)
    for yr_idx in yr_idxs
        add_hourly!(ar, shape, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, idxs::Int64...)
    view(ar, idxs..., :) .+= shape
    return nothing
end

"""
    add_hourly_scaled!(ar, v::AbstractVector{Float64}, s::Float64, idx1, idx2)

Adds `v.*s` to `ar[idx1, idx2, :]`, without allocating.
"""
function add_hourly_scaled!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, s::Float64, idx1::Int64, idx2::Int64)
    view(ar, idx1, idx2, :) .+= shape .* s
    return nothing
end
function add_hourly_scaled!(ar, shape, s, idxs1, idxs2)
    for idx1 in idxs1, idx2 in idxs2
        add_hourly_scaled!(ar, shape, s, idx1, idx2)
    end
    return nothing
end

"""
    _match_yearly!(demand_arr, match, row_idxs, yr_idx, hr_weights)

Match the yearly demand represented by `demand_arr[row_idxs, yr_idx, :]` to `match`, with hourly weights `hr_weights`.
"""
function _match_yearly!(demand_arr::Array{Float64, 3}, match::Float64, row_idxs, yr_idx::Int64, hr_weights)
    # Select the portion of the demand_arr to match
    _match_yearly!(view(demand_arr, row_idxs, yr_idx, :), match, hr_weights)
end
function _match_yearly!(demand_mat::SubArray{Float64, 2}, match::Float64, hr_weights)
    # The demand_mat is now a 2d matrix indexed by [row_idx, hr_idx]
    s = _sum_product(demand_mat, hr_weights)
    scale_factor = match / s
    demand_mat .*= scale_factor
end

"""
    _sum_product(M, v) -> s

Computes the sum of M*v
"""
function _sum_product(M::AbstractMatrix, v::AbstractVector)
    @inbounds sum(M[row_idx, hr_idx]*v[hr_idx] for row_idx in 1:size(M,1), hr_idx in 1:size(M,2))
end

