
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
    struct YearString end

    YearString(s) -> s

    YearString(n::Number) -> year2string(n)

This is a type that acts as a converter to ensure year columns are parsed correctly as strings.  If blank given, left blank.
"""
struct YearString end
function YearString(s::AbstractString)
    isempty(s) && return s
    if startswith(s, "y")
        return s
    elseif startswith(s, "Y")
        return lowercase(s)
    elseif startswith(s, r"\d")
        return string("y", s)
    else
        error("String $s cannot be converted to a year!")
    end

    # yregex = r"y(\d{4}\.?\d*)+"
    # ym = match(yregex, year)
    # if isnothing(ym)
    #     yregex = r"(\d{4}\.?\d*)+"
    #     ym = match(yregex, year)
    #     if isnothing(ym)
    #         error("Year string $s cannot be converted to a YearString")
    #     end
    #     return "y$(ym.captures[1])"
    # end
    # return s
end
YearString(n::Number) = year2str(n)
export YearString

"""
    year2int(year) -> 

Converts the year given as a String into a Int64.
"""
function year2int(year::AbstractString)
    year = year2float(year)
    year = round(Int, year, RoundNearestTiesUp)
    return year
end
export year2int

"""
    year2float(year) ->

Converts the year given as a String into a Int64
"""
function year2float(year::AbstractString)
    yregex = r"(\d{4}\.?\d*)+"
    ym = match(yregex, year)
    year = parse(Float64, ym.match)
    return year
end
export year2float

"""
    year2str(year) -> 

Converts the year given as a Number to a String in the standard "yXXXX" format.
"""
function year2str(year::Number)
    str_year = "y"*string(year)
    return str_year
end
export year2str

"""
    add_to_year(y::AbstractString, nyr::Number) -> y'

Adds `nyr` to `y`
"""
function add_to_year(y::AbstractString, nyr::Number)
    f = year2float(y)
    fnew = f+nyr
    isinteger(fnew) && return year2str(Int(fnew))
    return year2str(fnew) 
end
export add_to_year

"""
    diff_years(y1, y2) -> diff

Compute the difference between two year strings `y1 - y2`
"""
function diff_years(y1::AbstractString, y2::AbstractString)
    return year2float(y1) - year2float(y2)
end
export diff_years

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
    isbuilt(s::AbstractString)
"""
isbuilt(s::AbstractString) = s == "built"
isbuilt(row) = isbuilt(row.build_status)

"""
    isnew(s::AbstractString) -> ::Bool

    isnew(row::DataFrameRow) -> ::Bool
"""
isnew(s::AbstractString) = s == "new"
isnew(row) = isnew(row.build_status)


"""
    get_row_idxs(table, conditions) -> row_idxs

Returns row indices of the passed-in table that correspond to `conditions`, where `conditions` can be:
* `::Colon` - all rows
* `::Int64` - a single row
* `::AbstractVector{Int64}` - a list of rows
* `p::Pair` - returns a Vector containing the index of each row for which `comparison(p[2], typeof(row[p[1]]))(row[p[1]])` is true.  See [`comparison`](@ref) 
* `pairs`, an iterator of `Pair`s - returns a Vector containing the indices which satisfy all the pairs as above.

Some possible pairs to filter by:
* `:nation => "narnia"`: checks if the `nation` column is equal to the string "narnia"
* `:emis_co2 => >=(0.1)`: checks if the `emis_co2` column is greater than or equal to 0.1
* `:age => (2,10)`: checks if the `age` column is between 2, and 10, inclusive.  To be exclusive, use different values like (2.0001, 9.99999) for clarity
* `:state => in(("alabama", "arkansas"))`: checks if the `state` column is either "alabama" or "arkansas"

Used in [`get_table`](@ref) and [`get_table_row_idxs`](@ref).
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
export get_row_idxs


"""
    comparison(value, v) -> comp::Function

Returns the appropriate comparison function for `value` to be compared to each member of `v`.

    comparison(value, ::Type) -> comp::Function

Returns the appropriate comparison function for `value` to be compared to the 2nd argument type.  Here are a few options:
* comparison(f::Function, ::Type) -> f
* comparison(s::String, ::Type{<:AbstractString}) -> ==(s)
"""
function comparison(value, v::AbstractVector)
    comparison(value, eltype(v))
end
export comparison

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
    parse_comparison(s) -> comp

Parses the string, `s` for a comparison with which to filter a table.

Possible examples of strings `s` to parse:
* `"nation=>narnia"` - All rows for which row.nation=="narnia"
* `"bus_idx=>5"` - All rows for which row.bus_idx==5
* `"year_on=>(y2002,y2030)"` - All rows for which `row.year_on` is between 2002 and 2030, inclusive.
* `"emis_co2=>(0.0,4.99)"` - All rows for which `row.emis_co2` is between 0.0 and 4.99, inclusive. (Works for integers and negatives too)
* `"emis_co2=> >(0)"` - All rows for which `row.emis_co2` is greater than 0 (Works for integers and negatives too)
* `"year_on=> >(y2002)` - All rows for which `row.year_on` is greater than "y2002" (works for fractional years too, such as "y2002.4")
* `"genfuel=>[ng, wind, solar]"` - All rows for which `row.genfuel` is "ng", "wind", or "solar".  Works for Ints and Floats too.
"""
function parse_comparison(s::AbstractString)
    # In the form "emis_rate=>(0.0001,4.9999)" (should work for Ints, negatives, and Inf too)
    if (m=match(r"([\w\s]+)=>\s*\((\s*-?\s*(?:Inf)?[\d.]*)\s*,\s*-?\s*(?:Inf)?([\d.]*)\s*\)", s)) !== nothing
        r1 = parse(Float64, replace(m.captures[2], ' '=>""))
        r2 = parse(Float64, replace(m.captures[3], ' '=>""))
        return strip(m.captures[1])=>(r1, r2)
    end

    # In the form "year_on=>(y2020, y2030)"
    if (m=match(r"([\w\s]+)=>\s*\(\s*(y[\d]{4})\s*,\s*(y[\d]{4})\s*\)", s)) !== nothing
        return strip(m.captures[1])=>(m.captures[2], m.captures[3])
    end

    # In the form "emis_rate=>>(0)" (should work for Ints, negatives, and Inf too)
    if (m=match(r"([\w\s]+)=>\s*([><]{1}=?)\s*\(?\s*(-?\s*[\d.]+)\s*\)?", s)) !== nothing
        r1 = parse(Float64, replace(m.captures[3],' '=>""))
        m.captures[2]==">" && (comp = >(r1))
        m.captures[2]=="<" && (comp = <(r1))
        m.captures[2]==">=" && (comp = >=(r1))
        m.captures[2]=="<=" && (comp = <=(r1))
        return strip(m.captures[1])=>comp
    end

    # In the form "year_on=> >(y2020)" (should work decimals)
    if (m=match(r"([\w\s]+)=>\s*([><]{1}=?)\s*\(?\s*(y[\d.]+)\s*\)?", s)) !== nothing
        r1 = String(m.captures[3])
        m.captures[2]==">" && (comp = >(r1))
        m.captures[2]=="<" && (comp = <(r1))
        m.captures[2]==">=" && (comp = >=(r1))
        m.captures[2]=="<=" && (comp = <=(r1))
        return strip(m.captures[1])=>comp
    end

    # In the form "genfuel=>[ng,solar,wind]"
    if (m=match(r"([\w\s]+)=>\s*\[([\w,.\s]*)\]", s)) !== nothing
        ar = str2array(m.captures[2])
        return strip(m.captures[1])=>ar
    end

    # In the form "nation=>narnia" or "bus_idx=>5"
    if (m = match(r"([\w\s]+)=>([\w\s]+)", s)) !== nothing
        return strip(m.captures[1])=>strip(m.captures[2])
    end
end
export parse_comparison

"""
    parse_comparisons(row::DataFrameRow) -> pairs

Returns a set of pairs to be used in filtering rows of another table.  Looks for the following properties in the row:
* `area, subarea` - if the row has a non-empty area and subarea, it will parse the comparison `row.area=>row.subarea`
* `filter_` - if the row has any non-empty `filter_` (i.e. `filter1`, `filter2`) values, it will parse the comparison via [`parse_comparison`](@ref)
* `genfuel` - if the row has a non-empty `genfuel`, it will add an comparion that checks that each row's `genfuel` equals this value
* `gentype` - if the row has a non-empty `gentype`, it will add an comparion that checks that each row's `gentype` equals this value
* `load_type` - if the row has a non-empty `load_type`, it will add an comparion that checks that each row's `load_type` equals this value
"""
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
        push!(pairs, parse_comparison("$(row.area)=>$(row.subarea)"))
    end

    # Check for genfuel and gentype
    hasproperty(row, :genfuel) && ~isempty(row.genfuel) && push!(pairs, parse_comparison("genfuel=>$(row.genfuel)"))
    hasproperty(row, :gentype) && ~isempty(row.gentype) && push!(pairs, parse_comparison("gentype=>$(row.gentype)"))
    hasproperty(row, :load_type) && ~isempty(row.load_type) && push!(pairs, parse_comparison("load_type=>$(row.load_type)"))
    hasproperty(row, :build_id) && ~isempty(row.build_id) && push!(pairs, parse_comparison("build_id=>$(row.build_id)"))
    
    return pairs
end
export parse_comparisons

"""
    parse_comparisons(d::AbstractDict) -> pairs

Returns a set of pairs to be used in filtering rows of another table, where each value `d`
"""
function parse_comparisons(d::AbstractDict)
    pairs = collect(parse_comparison("$k=>$v") for (k,v) in d if ~isempty(v))
end


"""
    parse_year_idxs(s::AbstractString) -> comparisons

Parse a year comparison.  Could take the following forms:
* `"y2020"` - year 2020 only
* `""` - All years, returns (:)
* `"1"` - year index 1
* `"[1,2,3]"`
"""
function parse_year_idxs(s::AbstractString)
    isempty(s) && return (:)
    # "y2020"
    if (m=match(r"y[\d]{4}", s)) !== nothing
        return m.match
    end
    # "1"
    if (m=match(r"\d*", s)) !== nothing
        return parse(Int64, m.match)
    end

    # not sure when this would be necessary, maybe if we end up having a years table.
    # if (m = match(r"([\w\s]+)=>([\w\s]+)", s)) !== nothing
    #     return strip(m.captures[1])=>strip(m.captures[2])
    # end

    error("No match found for $s")
end
export parse_year_idxs



"""
    parse_hour_idxs(s::AbstractString) -> comparisons

Parse a year comparison.  Could take the following forms:
* `"1"` - hour 1 only
* `""` - All hours, returns (:)
* `"season=>winter"` - returns "season"=>"winter"
"""
function parse_hour_idxs(s::AbstractString)
    isempty(s) && return (:)
    
    # "1"
    if (m=match(r"\d+", s)) !== nothing
        return parse(Int64, m.match)
    end
    
    # "season=>winter"
    if (m = match(r"([\w\s]+)=>([\w\s]+)", s)) !== nothing
        return strip(m.captures[1])=>strip(m.captures[2])
    end

    error("No match found for $s")
end
export parse_hour_idxs

function str2array(s::AbstractString)
    v = split(s,',')
    v = strip.(v)
    v_int = tryparse.(Int64, v)
    v_int isa Vector{Int64} && return v_int
    v_float = tryparse.(Float64, v)
    v_float isa Vector{Float64} && return v_float
    return String.(v)
end

"""
    scale_hourly!(load_arr, shape, row_idx, yr_idx)
    
Scales the hourly load in `load_arr` by `shape` for `row_idx` and `yr_idx`.
"""
function scale_hourly!(load_arr, shape, row_idxs, yr_idxs)
    for yr_idx in yr_idxs, row_idx in row_idxs
        scale_hourly!(load_arr, shape, row_idx, yr_idx)
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
    
adds to the hourly load in `ar` by `shape` for `row_idx` and `yr_idx`.
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
    _match_yearly!(load_arr, match, row_idxs, yr_idx, hr_weights)

Match the yearly load represented by `load_arr[row_idxs, yr_idx, :]` to `match`, with hourly weights `hr_weights`.
"""
function _match_yearly!(load_arr::Array{Float64, 3}, match::Float64, row_idxs, yr_idx::Int64, hr_weights)
    # Select the portion of the load_arr to match
    _match_yearly!(view(load_arr, row_idxs, yr_idx, :), match, hr_weights)
end
function _match_yearly!(load_mat::SubArray{Float64, 2}, match::Float64, hr_weights)
    # The load_mat is now a 2d matrix indexed by [row_idx, hr_idx]
    s = _sum_product(load_mat, hr_weights)
    scale_factor = match / s
    load_mat .*= scale_factor
end

"""
    _sum_product(M, v) -> s

Computes the sum of M*v
"""
function _sum_product(M::AbstractMatrix, v::AbstractVector)
    @inbounds sum(M[row_idx, hr_idx]*v[hr_idx] for row_idx in axes(M,1), hr_idx in axes(M,2))
end


"""
    replace_nans!(v, x) -> v

Replaces all `NaN` values in `v` with `x`
"""
function replace_nans!(v, x)
    for i in eachindex(v)
        isnan(v[i]) || continue
        v[i] = x
    end
    return v
end
export replace_nans!

"""
    replace_zeros!(v, x) -> v

Replaces all zero values in `v` with `x`
"""
function replace_zeros!(v, x)
    for i in eachindex(v)
        iszero(v[i]) || continue
        v[i] = x
    end
    return v
end
export replace_zeros!

function zeroifnan(x::T) where {T <: Number}
    isnan(x) ? zero(T) : x
end
zeroifnan(v::Vector{T}) where {T<:Number} = replace_nans!(v, zero(T))


function table2markdown(df::DataFrame)
    io = IOBuffer()
    print(io, "|")
    for n in names(df)
        print(io, " ", n, " |")
    end
    println(io)
    print(io, "|")
    foreach(x->print(io, " :-- |"), 1:ncol(df))
    println(io)
    for row in eachrow(df)
        print(io, "|")
        foreach(x->print(io, " ", table_element(x), " |"), row)
        println(io)
    end
    return String(take!(io))
end
export table2markdown

table_element(x) = x
table_element(x::Symbol) = "`$x`"

function TableSummary()
    DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[],  "required"=>Bool[],"description"=>String[])
end
export TableSummary

"""
    sum0(f, itr)

Returns `0.0` if `itr` is empty, and `sum(f, itr)` if it is not
"""
function sum0(f, itr)
    isempty(itr) && return 0.0
    return sum(f, itr)
end

function sum0(itr)
    isempty(itr) && return 0.0
    return sum(itr)
end

"""
    anyany(f, v::AbstractVector{<:AbstractArray}) -> ::Bool

Returns whether any f(x) holds true for any value of each element of v.
"""
function anyany(f, v)
    any(x->any(f, x), v)
end
export anyany

function Base.convert(T::Type{Symbol}, x::String)
    return Symbol(x)
end

"""
    get_past_invest_percentages(g, years) -> ::ByYear

Computes the percentage of past investment costs and/or subsidies to still be paid in each `year`, given the `year_on`, `year_unbuilt` and `econ_life` of `g`.
"""
function get_past_invest_percentages(g, years)
    year_on = g.year_on::AbstractString
    year_unbuilt = g.year_unbuilt::AbstractString
    econ_life = g.econ_life::Float64
    diff = diff_years(year_on, year_unbuilt)
    v = map(years) do y
        percent = (diff_years(year_on, y) + econ_life) / diff
        return min(1.0, max(0.0, percent))
    end
    return OriginalContainer(0.0, ByYear(v))
end