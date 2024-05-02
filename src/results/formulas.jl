"""
    setup_results_formulas!(config, data)

Sets up the results formulas from `config[:results_formulas_file]`, if provided, or loads a default set of formulas.  See [`summarize_table(::Val{:results_formulas})`](@ref).
"""
function setup_results_formulas!(config, data)
    data[:results_formulas] = OrderedDict{Tuple{Symbol, Symbol},ResultsFormula}()
    
    results_formulas_file = get(config, :results_formulas_file) do
        joinpath(@__DIR__, "results_formulas.csv")
    end
        
    results_formulas_table = read_table(data, results_formulas_file, :results_formulas)

    for row in eachrow(results_formulas_table)
        add_results_formula!(data, row.table_name, row.result_name, row.formula, row.unit, row.description)
    end
end
export setup_results_formulas!

"""
    filter_results_formulas!(data)

Filters any results formulas that depend on columns that do not exist.
"""
function filter_results_formulas!(data)
    results_formulas = get_results_formulas(data)

    # Need to iterate so all the dependencies work out.
    diff = 1
    while diff > 0
        original_length = length(results_formulas)    
        filter!(results_formulas) do (p, rf)
            (table_name, result_name) = p
            dependent_columns = rf.dependent_columns
            if rf.isderived === true
                invalid_cols = filter(col->!haskey(results_formulas, (table_name, col)), dependent_columns)
                isvalid = isempty(invalid_cols)
                isvalid || @warn "Derived result $result_name for table $table_name cannot be computed because there are not results_formulas for:\n  $invalid_cols"
                return isvalid
            else
                table = get_table(data, table_name)
                invalid_cols = filter(col->!hasproperty(table, col) && !haskey(data, col), dependent_columns)
                isvalid = isempty(invalid_cols)
                isvalid || @warn "Result $result_name for table $table_name cannot be computed because table does not have columns:\n  $invalid_cols"
                return isvalid
            end
        end
        diff = original_length - length(results_formulas)
    end
    return nothing
end
export filter_results_formulas!

@doc """
    summarize_table(::Val{:results_formulas})

$(table2markdown(summarize_table(Val(:results_formulas))))
"""
function summarize_table(::Val{:results_formulas})
    df = TableSummary()
    push!(df, (:table_name, Symbol, NA, true, "The name of the table that the result is for."))
    push!(df, (:result_name, Symbol, NA, true, "The name of the result that the formula is for."))
    push!(df, (:formula, String, NA, true, "The string representing the formula for the table.  See [`add_results_formula!`](@ref) for more info on this."))
    push!(df, (:unit, Type{<:Unit}, NA, true, "The unit for the result."))
    push!(df, (:description, String, NA, true, "A description of the result."))
    return df
end

"""
    add_results_formula!(data, table_name::Symbol, result_name::Symbol, formula::String, unit::Type{<:Unit}, description::String)

Adds a formula that can be used to compute results.  See [`compute_result`](@ref).  This is also used by [`AggregationTemplate`](@ref) and [`YearlyTable`](@ref).

Arguments:
* `data`
* `table_name` - the name of the table that the result is calculated from, either directly or as a combination of other results
* `result_name` - the name of the result being calculated.  Cannot be a column name within the table.
* `formula` - `formula` can take two different forms.
  * it can be a combination of columns to be aggregated directly from `table_name`.  I.e. `"SumHourly(vom, egen)"`. See [`Sum`](@ref), [`SumHourly`](@ref), [`SumYearly`](@ref), [`AverageYearly`](@ref), [`MinHourly`](@ref).  Note that the columns here can either be column names or variable names stored with `data`, like `dam_co2`
  * it can also be a combination of other results. I.e. `"(vom_cost + fuel_cost) / egen_total"`.
* `unit` - the [`Unit`](@ref) of the resulting number
* `description` - a short description of the calculation.
"""
function add_results_formula!(data, table_name::Symbol, result_name::Symbol, formula::String, unit::Type{<:Unit}, description::String)
    table = get_table(data, table_name)
    if hasproperty(table, result_name)
        error("Cannot have a result name $result_name that matches a colum name in the $table_name table")
    end

    results_formulas = get_results_formulas(data)

    rf = ResultsFormula(table_name, result_name, formula, unit, description)

    # push!(results_formulas_table, (;table_name, result_name, formula, unit, description, dependent_columns, fn))
    results_formulas[table_name, result_name] = rf
end
function add_results_formula!(data, table_name, result_name, formula::String, unit::Type{<:Unit}, description::String)
    return add_results_formula!(data, table_name |> Symbol, result_name |> Symbol, formula, unit, description)
end
export add_results_formula!

"""
    add_to_results_formula!(data, table_name::Symbol, result_name::Symbol, formula)

Adds a term to an existing results formula.  Can be more complex expressions.
* if it is a derived formula (like `\"vom_cost + fom_cost\"`), then you can supply any expression to get added to the formula, like `\"-my_result_name / 2\"`
* if it is a primary formula (like `\"SumHourly(col1, col2)\"`), then you can provide additional columns like `\"col3, col4\"`.
"""
function add_to_results_formula!(data, table_name::Symbol, result_name::Symbol, formula)
    rf = get_results_formula(data, table_name, result_name)
    formula_original = rf.formula
    if rf.isderived
        formula_new = string(formula_original, " + ", formula)
    else
        formula_new = replace(formula_original, ")"=>",$formula)")
    end
    rf_new = ResultsFormula(table_name, result_name, formula_new, rf.unit, rf.description)
    results_formulas = get_results_formulas(data)
    results_formulas[table_name, result_name] = rf_new
end
export add_to_results_formula!


"""
    struct ResultsFormula

This is a type used to store a formula for computing a result.
"""
struct ResultsFormula
    table_name::Symbol
    result_name::Symbol
    formula::String
    unit::Type{<:Unit}
    description::String
    isderived::Bool
    dependent_columns::Vector{Symbol}
    fn::Function
end
export ResultsFormula

function ResultsFormula(table_name::Symbol, result_name::Symbol, formula::String, unit::Type{<:Unit}, description::String)
    
    # Raw results calculations. I.e. "SumHourly(vom, egen)"
    if startswith(formula, r"[\w]+\(")
        args_string = match(r"\([^\)]*\)", formula).match
        dependent_columns = collect(Symbol(m.match) for m in eachmatch(r"(\w+)", args_string))
        fn_string = match(r"([\w]+)\(",formula).captures[1]
        T = getfield(E4ST, Symbol(fn_string))
        fn = T(dependent_columns...)
        isderived = false
        
    # Derived results calculations: I.e. "vom_total / egen_total"
    else
        dependent_columns = collect(Symbol(m.match) for m in eachmatch(r"([A-Za-z]\w+)", formula))
        isderived = true
        fn = _ResultsFunction(formula)
    end

    return ResultsFormula(table_name, result_name, formula, unit, description, isderived, dependent_columns, fn)
end

struct _ResultsFunction{F} <: Function end
function _ResultsFunction(s::String)
    fn = _Func(s)
    _ResultsFunction{fn}()
end
(::_ResultsFunction{F})(args...) where F = zeroifnan(F(args...))

struct Op{F, A} <: Function end
struct Args{A1, A2} <: Function end
struct Var{S} <: Function end
struct Num{N} <: Function end
struct Tail <: Function end

_Func(s::String) = _Func(Meta.parse(s))
_Func(e::Expr) = Op{getfield(Base, e.args[1]), _Func((view(e.args, 2:length(e.args))...,))}
_Func(s::Symbol) = Var{s}
_Func(n::Number) = Num{Float64(n)}
function _Func(args::Tuple)
    Args{_Func(first(args)), _Func(Base.tail(args))}
end
function _Func(::Tuple{})
    return Tail
end

function Base.show(io::IO, rf::ResultsFormula)
    print(io, "ResultsFormula $(rf.result_name) for table $(rf.table_name): ")
    print(io, rf.formula)
end
function (::Type{Op{F, A}})(d) where {F, A}
    args = A(d)
    return F.(args...)
end
function (::Type{Args{A1, A2}})(d) where {A1, A2}
    a1 = A1(d)
    rest = A2(d)
    return (a1, rest...)
end
function (::Type{Tail})(d)
    return ()
end

function (::Type{Var{V}})(d) where {V}
    return getproperty(d, V)
end
function (::Type{Num{N}})(d) where {N}
    return N
end

"""
    get_results_formulas(data)

Returns a dictionary mapping `(table_name, result_name)` to [`ResultsFormula`](@ref).

    get_results_formulas(data, table_name)

Returns only the results formulas corresponding to table `table_name`.
"""
function get_results_formulas(data)
    return data[:results_formulas]::OrderedDict{Tuple{Symbol, Symbol},ResultsFormula}
end
export get_results_formulas

function get_results_formulas(data, table_name::Symbol)
    results_formulas = get_results_formulas(data)
    return filter(results_formulas) do (k,v)
        k[1] == table_name
    end
end

"""
    get_results_formula(data, table_name, result_name) -> rf::ResultsFormula
"""
function get_results_formula(data, table_name::Symbol, result_name::Symbol)
    results_formulas = get_results_formulas(data)
    @assert haskey(results_formulas, (table_name, result_name)) "No result $result_name found for table $table_name"
    return results_formulas[table_name, result_name]::ResultsFormula
end
export get_results_formula

"""
    compute_result(data, table_name, result_name, idxs=(:), yr_idxs=(:), hr_idxs=(:))

Computes result `result_name` for table `table_name` for table indexes `idxs`, year indexes `yr_idxs` and hour indexes `hr_idxs`.  See [`add_results_formula!`](@ref) to add other results formulas for computing results.

Note that this will recursively compute results for any derived result, as needed.

If any result is computed to be `NaN`, returns `0.0` instead, so that the NaN does not "infect" other results.
"""
function compute_result(data, table_name, result_name, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    table = get_table(data, table_name)
    res_formula = get_results_formula(data, table_name, result_name)
    _idxs = get_row_idxs(table, idxs)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)

    isempty(_idxs) && return 0.0
    isempty(_yr_idxs) && return 0.0
    isempty(_hr_idxs) && return 0.0

    if res_formula.isderived === false
        fn = res_formula.fn
        return fn(data, table, _idxs, _yr_idxs, _hr_idxs)::Float64
    else
        # Recursive
        dep_cols = res_formula.dependent_columns
        fn = res_formula.fn

        d = DictWrapper(
            col=>compute_result(data, table_name, col, _idxs, _yr_idxs, _hr_idxs) for col in dep_cols
        )
        return fn(d)::Float64
    end
end
export compute_result

"""
    compute_results!(df, data, table_name, result_name, idx_sets, year_idx_sets, hour_idx_sets)

You rarely should call this method - it is used by the [`YearlyTable`](@ref) to efficiently compute results for specific index sets. 

Computes result `result_name` for table `table_name`, for each index set in `idx_sets`, for each year index set in `year_idx_sets` and each hour index set in `hour_idx_sets`, storing the results into df[!, result_name].  This will recursively call `compute_results!` to compute any dependencies.
"""
function compute_results!(df, data, table_name, result_name, idx_sets, year_idx_sets, hour_idx_sets)
    hasproperty(df, result_name) && return
    table = get_table(data, table_name)

    res_formula = get_results_formula(data, table_name, result_name)

    if res_formula.isderived === false
        fn = res_formula.fn
        res = [
            fn(data, table, idxs, yr_idxs, hr_idxs)::Float64
            for idxs in idx_sets for yr_idxs in year_idx_sets for hr_idxs in hour_idx_sets
        ]
        
        df[!,result_name] = res
        return
    else
        # Make sure to compute any dependent columns first
        dep_cols = res_formula.dependent_columns
        for col in dep_cols
            hasproperty(df, col) && continue
            compute_results!(df, data, table_name, col, idx_sets, year_idx_sets, hour_idx_sets)
        end

        fn = res_formula.fn
        res = fn(df)

        df[!, result_name] .= res
    end
    return nothing
end

"""
    DictWrapper(args...)

This just wraps a Dict{Symbol, Float64}, used inside compute_results
"""
struct DictWrapper
    d::Dict{Symbol, Float64}
    DictWrapper(args...) = new(Dict{Symbol, Float64}(args...))
end

Base.getproperty(d::DictWrapper, s::Symbol) = getfield(d, :d)[s]

function col_or_container(data, table, s::Symbol)
    hasproperty(table, s) && return table[!, s]
    haskey(data, s) && return data[s]
    error("table has no column $s and data has no variable $s")
end


@doc raw"""
    Sum(cols...) <: Function

Function used in results formulas.  Computes the sum of the product of the column for each index in idxs

```math
\sum_{i \in \text{idxs}} \prod_{c \in \text{cols}} \text{table}[i, c]
```
"""
struct Sum{N} <: Function
    cols::NTuple{N, Symbol}
end
Sum(cols::Symbol...) = Sum(cols)
export Sum

function (f::Sum{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    _sum(col_or_container(data, table, col1), idxs)
end
function (f::Sum{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    _sum(col_or_container(data, table, col1), col_or_container(data, table, col2), idxs)
end
function (f::Sum{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    _sum(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), idxs)
end


@doc raw"""
    MinYearly(cols...) <: Function

This function returns the minimum yearly value.

```math
\min_{y \in \text{yr\_idxs}} \sum_{i \in \text{idxs}, h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct MinYearly{N} <: Function
    cols::NTuple{N, Symbol}
end
MinYearly(cols::Symbol...) = MinYearly(cols)
export MinYearly

function (f::MinYearly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    minimum(_sum_yearly(v1, idxs, y, hr_idxs) for y in yr_idxs)
end

@doc raw"""
    MaxYearly(cols...) <: Function

This function returns the maximum yearly value.

```math
\max_{y \in \text{yr\_idxs}} \sum_{i \in \text{idxs}, h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct MaxYearly{N} <: Function
    cols::NTuple{N, Symbol}
end
MaxYearly(cols::Symbol...) = MaxYearly(cols)
export MaxYearly

function (f::MaxYearly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    maximum(_sum_yearly(v1, idxs, y, hr_idxs) for y in yr_idxs)
end

@doc raw"""
    AverageYearly(cols...) <: Function

Function used in results formulas.  Computes the sum of the products of the columns for each index in idxs for each year, divided by the number of years.

```math
\frac{\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y]}{\text{length(yr\_idxs)}}
```
"""
struct AverageYearly{N} <: Function
    cols::NTuple{N, Symbol}
end
AverageYearly(cols::Symbol...) = AverageYearly(cols)
export AverageYearly

function (f::AverageYearly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    _sum_yearly(col_or_container(data, table, col1), idxs, yr_idxs) / length(yr_idxs)
end

function (f::AverageYearly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    _sum_yearly(col_or_container(data, table, col1), col_or_container(data, table, col2), idxs, yr_idxs) / length(yr_idxs)
end

function (f::AverageYearly{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    _sum_yearly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), idxs, yr_idxs) / length(yr_idxs)
end

@doc raw"""
    SumYearly(cols...) <: Function

Function used in results formulas.  This is a function that adds up the product of each of the values given to it for each year given.

```math
\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y]
```
"""
struct SumYearly{N} <: Function
    cols::NTuple{N, Symbol}
end
SumYearly(cols::Symbol...) = SumYearly(cols)
export SumYearly

function (f::SumYearly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    _sum_yearly(col_or_container(data, table, col1), idxs, yr_idxs)
end
function (f::SumYearly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    _sum_yearly(col_or_container(data, table, col1), col_or_container(data, table, col2), idxs, yr_idxs)
end
function (f::SumYearly{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    _sum_yearly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), idxs, yr_idxs)
end

@doc raw"""
    MinHourly(cols...) <: Function

This function returns the minimum hourly value.

```math
\min_{y \in \text{yr\_idxs}, h \in \text{hr\_idxs}} \sum_{i \in \text{idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct MinHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
MinHourly(cols::Symbol...) = MinHourly(cols)
export MinHourly

function (f::MinHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    minimum(_sum_hourly(v1, idxs, y, h) for h in hr_idxs for y in yr_idxs)
end



@doc raw"""
    MaxHourly(cols...) <: Function

This function returns the maximum aggregated hourly value. Sums up all values for that hour over the given idxs, then takes the maximum. 
Suited for results like load where you want to know the maximum of the regional load. 

```math
\max_{y \in \text{yr\_idxs}, h \in \text{hr\_idxs}} \sum_{i \in \text{idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct MaxHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
MaxHourly(cols::Symbol...) = MaxHourly(cols)
export MaxHourly

function (f::MaxHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    maximum(_sum_hourly(v1, idxs, y, h) for h in hr_idxs for y in yr_idxs)
end

@doc raw"""
    SumMaxHourly(cols...) <: Function

This function returns the sum of each of the maximum hourly values. 

```math
\sum_{i \in \text{idxs}} \max_{y \in \text{yr\_idxs}, h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct SumMaxHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
SumMaxHourly(cols::Symbol...) = SumMaxHourly(cols)
export SumMaxHourly

function (f::SumMaxHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    return sum(maximum(_getindex(v1, i, y, h) for h in hr_idxs, y in yr_idxs) for i in idxs)
end

function (f::SumMaxHourly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1, col2 = f.cols
    v1 = col_or_container(data, table, col1)
    v2 = col_or_container(data, table, col2)
    return sum(maximum(_getindex(v1, i, y, h) * _getindex(v2, i, y, h) for h in hr_idxs, y in yr_idxs) for i in idxs)
end

@doc raw"""
    SumMinHourly(cols...) <: Function

This function returns the sum of each of the minimum hourly values. 

```math
\sum_{i \in \text{idxs}} \min_{y \in \text{yr\_idxs}, h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct SumMinHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
SumMinHourly(cols::Symbol...) = SumMinHourly(cols)
export SumMinHourly

function (f::SumMinHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    return sum(minimum(_getindex(v1, i, y, h) for h in hr_idxs, y in yr_idxs) for i in idxs)
end

function (f::SumMinHourly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1, col2 = f.cols
    v1 = col_or_container(data, table, col1)
    v2 = col_or_container(data, table, col2)
    return sum(minimum(_getindex(v1, i, y, h) * _getindex(v2, i, y, h) for h in hr_idxs, y in yr_idxs) for i in idxs)
end

"""
    MaxValue()

This function returns the maximum hourly value from all hours for all of the given idxs. These values are not weighted hourly and are not aggregated. 
This is suited for results like capacity factor and things that are characteristics of an hour that should not be summed. 
"""
struct MaxValue{N} <: Function
    cols::NTuple{N, Symbol}
end
MaxValue(cols::Symbol...) = MaxValue(cols)
export MaxValue

function (f::MaxValue{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    maximum(_iterator_hourly(v1, idxs, yr_idxs, hr_idxs))
end

"""
    MinValue()

This function returns the minimum hourly value from all hours for all of the given idxs. These values are not weighted hourly and are not aggregated. 
This is suited for results like capacity factor and things that are characteristics of an hour that should not be summed. 
"""
struct MinValue{N} <: Function
    cols::NTuple{N, Symbol}
end
MinValue(cols::Symbol...) = MinValue(cols)
export MaxValue

function (f::MinValue{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    v1 = col_or_container(data, table, col1)
    minimum(_iterator_hourly(v1, idxs, yr_idxs, hr_idxs))
end


@doc raw"""
    SumHourly(cols...) <: Function

This is a function that adds up the product of each of the values given to it for each of the years and hours given.

```math
\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \sum_{h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct SumHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
SumHourly(cols::Symbol...) = SumHourly(cols)
export SumHourly

function (f::SumHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    _sum_hourly(col_or_container(data, table, col1), idxs, yr_idxs, hr_idxs)
end
function (f::SumHourly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), idxs, yr_idxs, hr_idxs)
end
function (f::SumHourly{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), idxs, yr_idxs, hr_idxs)
end

# function (f::SumHourly{4})(data, table, idxs, yr_idxs, hr_idxs)
#     col1,col2,col3,col4 = f.cols
#     _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), col_or_container(data, table, col4), idxs, yr_idxs, hr_idxs)
# end


@doc raw"""
    SumHourlyWeighted(cols...) <: Function

This is a function that adds up the product of each of the values given to it times the hour weight for each of the years and hours given.

```math
\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \sum_{h \in \text{hr\_idxs}} w_{h} \prod_{c \in \text{cols}} \text{table}[i, c][y, h]
```
"""
struct SumHourlyWeighted{N} <: Function
    cols::NTuple{N, Symbol}
end
SumHourlyWeighted(cols::Symbol...) = SumHourlyWeighted(cols)
export SumHourlyWeighted

function get_hours_container(data)
    return data[:hours_container]::HoursContainer
end

function (f::SumHourlyWeighted{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), hc, idxs, yr_idxs, hr_idxs)
end
function (f::SumHourlyWeighted{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), hc, idxs, yr_idxs, hr_idxs)
end
function (f::SumHourlyWeighted{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), hc, idxs, yr_idxs, hr_idxs)
end


@doc raw"""
    AverageHourly(cols...) <: Function

Function used in results formulas.  Computes the sum of the products of the columns for each index in idxs for each year and hour, divided by the number of hours.

```math
\frac{\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y]}{\sum_{y \in \text{yr\_idxs}, h \in \text{hr\_idxs}} w_{h}}
```
"""
struct AverageHourly{N} <: Function
    cols::NTuple{N, Symbol}
end
AverageHourly(cols::Symbol...) = AverageHourly(cols)
export AverageHourly

function (f::AverageHourly{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    hour_weights = get_hour_weights(data)
    _sum_hourly(col_or_container(data, table, col1), idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end

function (f::AverageHourly{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    hour_weights = get_hour_weights(data)
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end

function (f::AverageHourly{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    hour_weights = get_hour_weights(data)
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end



@doc raw"""
    AverageHourlyWeighted(cols...) <: Function

Function used in results formulas.  Computes the sum of the products of the columns for each index in idxs for each year and hour weighted by the number of hours, divided by the total number of hours.

```math
\frac{\sum_{i \in \text{idxs}} \sum_{y \in \text{yr\_idxs}} \sum_{h \in \text{hr\_idxs}} \prod_{c \in \text{cols}} \text{table}[i, c][y]}{\sum_{y \in \text{yr\_idxs}}\sum{h \in \text{hr\_idxs}} w_{h}}
```
"""
struct AverageHourlyWeighted{N} <: Function
    cols::NTuple{N, Symbol}
end
AverageHourlyWeighted(cols::Symbol...) = AverageHourlyWeighted(cols)
export AverageHourlyWeighted

function (f::AverageHourlyWeighted{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols
    hour_weights = get_hour_weights(data)
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), hc, idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end

function (f::AverageHourlyWeighted{2})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2 = f.cols
    hour_weights = get_hour_weights(data)
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), hc, idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end

function (f::AverageHourlyWeighted{3})(data, table, idxs, yr_idxs, hr_idxs)
    col1,col2,col3 = f.cols
    hour_weights = get_hour_weights(data)
    hc = get_hours_container(data)::HoursContainer
    _sum_hourly(col_or_container(data, table, col1), col_or_container(data, table, col2), col_or_container(data, table, col3), hc, idxs, yr_idxs, hr_idxs) / sum(hour_weights[hr_idx] for hr_idx in hr_idxs, yr_idx in yr_idxs)
end

"""
    PercentWeightedHoursNonZero{N} <: Function

Returns the percent of weighted hours (as a decimal) where the column value is non-zero. 
This is done by creating a boolean matrix of whether the column value is non zero at that index. Then the average is taken over all of the specified indices. 

This is useful in finding the percent of time that a constraint is binding. To do this, you first need to add a column containing the shadow price of the constraint to the relevant table in data (ie. gen table if it is a constraint on generators)
"""
struct PercentWeightedHoursNonZero{N} <: Function 
    cols::NTuple{N, Symbol}
end
PercentWeightedHoursNonZero(cols::Symbol...) = PercentWeightedHoursNonZero(cols)
export(PercentWeightedHoursNonZero)

function (f::PercentWeightedHoursNonZero{1})(data, table, idxs, yr_idxs, hr_idxs)
    col1, = f.cols  
    
    _PercentWeightedHoursNonZero(col_or_container(data, table, col1), get_hour_weights(data), idxs, yr_idxs, hr_idxs)

end

function _PercentWeightedHoursNonZero(v1, hour_weights, idxs, yr_idxs, hr_idxs)
    count = 0.0
    tolerance = 0.00001*mean(mean(v1))
    for i in idxs, y in yr_idxs, h in hr_idxs
        isapprox(v1[i][y, h],0.0, atol = tolerance) || (count += hour_weights[h])
    end

    res = count / (length(idxs)*length(yr_idxs)*sum(hour_weights[hr_idxs]))
    return res
end



"""
    CostOfServiceRebate(table_name) <: Function

This is a special function that computes the sum of the net total revenue times the regulatory factor `reg_factor`.  This only works for the gen table and storage table.
"""
struct CostOfServiceRebate <: Function
    table_name::Symbol
end
function (f::CostOfServiceRebate)(data, table, idxs, yr_idxs, hr_idxs)
    reg_factor = table.reg_factor::Vector{Float64}
    res = 0.0
    for i in idxs
        rf = reg_factor[i]
        rev_prelim = compute_result(data, f.table_name, :net_total_revenue_prelim, i, yr_idxs, hr_idxs)
        prod = rf * rev_prelim
        res += prod
    end
    return res
    # return sum0(reg_factor[i] * compute_result(data, f.table_name, :net_total_revenue_prelim, i, yr_idxs, hr_idxs) for i in idxs)
end
export CostOfServiceRebate


function _sum(v1, idxs)
    res = 0.0
    for i in idxs
        x1 = _getindex(v1, i)
        p = x1
        res += p
    end
    return res
    # sum(_getindex(v1,i) for i in idxs)
end
function _sum(v1, v2, idxs)
    res = 0.0
    for i in idxs
        x1 = _getindex(v1, i)
        x2 = _getindex(v2, i)
        p = x1 * x2
        res += p
    end
    return res
    # sum(_getindex(v1,i)*_getindex(v2,i) for i in idxs)
end
function _sum(v1, v2, v3, idxs)
    res = 0.0
    for i in idxs
        x1 = _getindex(v1, i)
        x2 = _getindex(v2, i)
        x3 = _getindex(v3, i)
        p = x1 * x2 * x3
        res += p
    end
    return res
    # sum(_getindex(v1,i)*_getindex(v2,i)*_getindex(v3,i) for i in idxs)
end
function _sum_yearly(v1, idxs, yr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs
        x1 = _getindex(v1, i, y)
        p = x1
        res += p
    end
    return res
    # sum(_getindex(v1, i, y) for i in idxs, y in yr_idxs)
end
function _sum_yearly(v1, v2, idxs, yr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs
        x1 = _getindex(v1, i, y)
        x2 = _getindex(v2, i, y)
        p = x1 * x2
        res += p
    end
    return res
    # sum(_getindex(v1, i, y)*_getindex(v2, i, y) for i in idxs, y in yr_idxs)
end
function _sum_yearly(v1, v2, v3, idxs, yr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs
        x1 = _getindex(v1, i, y)
        x2 = _getindex(v2, i, y)
        x3 = _getindex(v3, i, y)
        p = x1 * x2 * x3
        res += p
    end
    return res
    # sum(_getindex(v1, i, y)*_getindex(v2, i, y)*_getindex(v3, i, y) for i in idxs, y in yr_idxs)
end

function _sum_hourly(v1, idxs, yr_idxs, hr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs, h in hr_idxs
        x1 = _getindex(v1, i, y, h)
        p = x1
        res += p
    end
    return res
    # sum(_getindex(v1, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end
function _sum_hourly(v1, v2, idxs, yr_idxs, hr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs, h in hr_idxs
        x1 = _getindex(v1, i, y, h)
        x2 = _getindex(v2, i, y, h)
        p = x1 * x2
        res += p
    end
    return res
    # sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end
function _sum_hourly(v1, v2, v3, idxs, yr_idxs, hr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs, h in hr_idxs
        x1 = _getindex(v1, i, y, h)
        x2 = _getindex(v2, i, y, h)
        x3 = _getindex(v3, i, y, h)
        p = x1 * x2 * x3
        res += p
    end
    return res
    # sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h)*_getindex(v3, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end
function _sum_hourly(v1, v2, v3, v4, idxs, yr_idxs, hr_idxs)
    res = 0.0
    for i in idxs, y in yr_idxs, h in hr_idxs
        x1 = _getindex(v1, i, y, h)
        x2 = _getindex(v2, i, y, h)
        x3 = _getindex(v3, i, y, h)
        x4 = _getindex(v4, i, y, h)
        p = x1 * x2 * x3 * x4
        res += p
    end
    return res
    # sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h)*_getindex(v3, i, y, h)*_getindex(v4, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end

function _iterator_hourly(v1, idxs, yr_idxs, hr_idxs)
    return (_getindex(v1, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end



