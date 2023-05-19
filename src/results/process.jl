
function summarize_table(::Val{:results_formulas})
    df = TableSummary()
    push!(df, (:table_name, Symbol, NA, true, "The name of the table that the result is for."))
    push!(df, (:result_name, Symbol, NA, true, "The name of the result that the formula is for."))
    push!(df, (:formula, String, NA, true, "The string representing the formula for the table.  See [`add_results_formula!`](@ref) for more info on this."))
    push!(df, (:unit, Type{<:Unit}, NA, true, "The unit for the result."))
    push!(df, (:description, String, NA, true, "A description of the result."))
    return df
end

function ResultsFormulas()
    return DataFrame(;
        table_name=Symbol[],
        result_name=Symbol[],
        formula=String[],
        unit=Type{<:Unit}[],
        description=String[],
        dependent_columns=Vector{Symbol}[],
        fn=Function[],
    )
end
export ResultsFormulas

"""
    add_results_formula!(data, table_name::Symbol, result_name::Symbol, formula::String, unit::Type{<:Unit}, description::String)

Arguments:
* `data`
* `table_name` - the name of the table that the result is calculated from, either directly or as a combination of other results
* `result_name` - the name of the result being calculated.  Cannot be a column name within the table.
* `formula` - `formula` can take two different forms.
  * it can be a sum of products of columns directly from `table_name`.  I.e. `sum(egen)` or `sum(vom * egen)`.
  * it can also be a combination of other results. I.e. `(vom_cost + fuel_cost) / egen_total`.
* `unit` - the [`Unit`](@ref) of the resulting number
* `description` - a short description of the calculation.
"""
function add_results_formula!(data, table_name::Symbol, result_name::Symbol, formula::String, unit::Type{<:Unit}, description::String)
    table = get_table(data, table_name)
    if hasproperty(table, result_name)
        error("Cannot have a result name $result_name that matches a colum name in the $table_name table")
    end

    # results_formulas_table = get_table(data, :results_formulas_table)
    results_formulas = data[:results_formulas]::OrderedDict{Tuple{Symbol, Symbol},Any}

    if startswith(formula, r"[\w]+\(")
        formula_stripped = match(r"\([^\)]+\)", formula).match
        dependent_columns = ((Symbol(m.match) for m in eachmatch(r"(\w+)", formula_stripped))...,)

        fn_string = match(r"([\w]+)\(",formula).captures[1]
    
        # # TODO: Use this logic when getting ready to compute results
        # for col_name in dependent_columns
        #     if ~hasproperty(table, col_name)
        #         @error "Table $table_name has no column $col_name, needed for results formula $result_name:\n  $formula\nOmitting this results formula"
        #         return
        #     end
        # end
    
        isderived = false
        fn = eval(Meta.parse(fn_string))
    else
        dependent_columns = ((Symbol(m.match) for m in eachmatch(r"(\w+)", formula))...,)

        # # TODO: Use this logic when getting ready to compute results
        # for col_name in dependent_columns
        #     if ~haskey(results_formulas, (table_name, col_name))
        #         @error "`results_formulas` has no result named $col_name, needed for results formula $result_name:\n  $formula\nOmitting this results formula"
        #         return
        #     end
        # end

        isderived = true
        fn_string = string("row->", replace(formula, r"(\w+)"=>s"row.\1", r"([^\.])([\+\*\/\-])"=>s"\1.\2"))
        fn = eval(Meta.parse(fn_string))::Function
    end

    # push!(results_formulas_table, (;table_name, result_name, formula, unit, description, dependent_columns, fn))
    results_formulas[table_name, result_name] = (;table_name, result_name, formula, unit, description, isderived, dependent_columns, fn)
end

function get_results_formulas(data)
    return data[:results_formulas]::OrderedDict{Tuple{Symbol, Symbol},Any}
end

function compute_result(data, table_name, result_name, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    table = get_table(data, table_name)
    results_formulas = get_results_formulas(data)
    @assert haskey(results_formulas, (table_name, result_name)) "No result $result_name found for table $table_name"
    _idxs = get_row_idxs(table, idxs)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)

    isempty(_idxs) && return 0.0
    isempty(_yr_idxs) && return 0.0
    isempty(_hr_idxs) && return 0.0

    res_formula = results_formulas[table_name, result_name]

    if res_formula.isderived === false
        dep_cols = res_formula.dependent_columns
        fn = res_formula.fn
        return fn(data, table, dep_cols..., _idxs, _yr_idxs, _hr_idxs)::Float64
    else
        # Recursive
        dep_cols = res_formula.dependent_columns
        fn = res_formula.fn

        d = NamedTuple{dep_cols}(
            compute_result(data, table_name, col, _idxs, _yr_idxs, _hr_idxs) for col in dep_cols
        )
        return fn(d)::Float64
    end
end
export compute_result

function average_yearly(data, table::DataFrame, col1::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], idxs, yr_idxs) / length(yr_idxs)
end
function average_yearly(data, table::DataFrame, col1::Symbol, col2::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], table[!, col2], idxs, yr_idxs) / length(yr_idxs)
end
function average_yearly(data, table::DataFrame, col1::Symbol, col2::Symbol, col3::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], table[!, col2], table[!, col3], idxs, yr_idxs) / length(yr_idxs)
end

@doc raw"""
    function sum_yearly

This is a function that adds up the product of each of the values given to it for each year given.

```math

```
"""
function sum_yearly(data, table::DataFrame, col1::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], idxs, yr_idxs)
end
function sum_yearly(data, table::DataFrame, col1::Symbol, col2::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], table[!, col2], idxs, yr_idxs)
end
function sum_yearly(data, table::DataFrame, col1::Symbol, col2::Symbol, col3::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_yearly(table[!, col1], table[!, col2], table[!, col3], idxs, yr_idxs)
end

function _sum_yearly(v1, idxs, yr_idxs)
    sum(_getindex(v1, i, y) for i in idxs, y in yr_idxs)
end
function _sum_yearly(v1, v2, idxs, yr_idxs)
    sum(_getindex(v1, i, y)*_getindex(v2, i, y) for i in idxs, y in yr_idxs)
end
function _sum_yearly(v1, v2, v3, idxs, yr_idxs)
    sum(_getindex(v1, i, y)*_getindex(v2, i, y)*_getindex(v3, i, y) for i in idxs, y in yr_idxs)
end


function sum_hourly(data, table::DataFrame, col1::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_hourly(table[!, col1], idxs, yr_idxs, hr_idxs)
end
function sum_hourly(data, table::DataFrame, col1::Symbol, col2::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_hourly(table[!, col1], table[!, col2], idxs, yr_idxs, hr_idxs)
end
function sum_hourly(data, table::DataFrame, col1::Symbol, col2::Symbol, col3::Symbol, idxs, yr_idxs, hr_idxs)
    _sum_hourly(table[!, col1], table[!, col2], table[!, col3], idxs, yr_idxs, hr_idxs)
end

function _sum_hourly(v1, idxs, yr_idxs, hr_idxs)
    sum(_getindex(v1, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end
function _sum_hourly(v1, v2, idxs, yr_idxs, hr_idxs)
    sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end
function _sum_hourly(v1, v2, v3, idxs, yr_idxs, hr_idxs)
    sum(_getindex(v1, i, y, h)*_getindex(v2, i, y, h)*_getindex(v3, i, y, h) for i in idxs, y in yr_idxs, h in hr_idxs)
end


function setup_results_formulas!(config, data)
    data[:results_formulas] = OrderedDict{Tuple{Symbol, Symbol},Any}()
    
    results_formulas_file = get(config, :results_formulas_file) do
        joinpath(@__DIR__, "results_formulas.csv")
    end
        
    results_formulas_table = read_table(data, results_formulas_file, :results_formulas)

    for row in eachrow(results_formulas_table)
        add_results_formula!(data, row.table_name, row.result_name, row.formula, row.unit, row.description)
    end

    # add_results_formula!(data, :gen, :egen_total, "sum(egen)", MWhGenerated, "Total energy generated, in MWh")
    # add_results_formula!(data, :gen, :ecap_total, "sum(ecap)", MWhGenerated, "Total energy capacity, in MWh")

    # add_results_formula!(data, :gen, :vom_cost,      "sum(vom * egen)",         Dollars,                "Variable Operation and Maintenance paid, in dollars")
    # add_results_formula!(data, :gen, :vom_per_mwh,   "vom_cost / egen_total",   DollarsPerMWhGenerated, "Generation-weighted average of variable operation and maintenance costs")
    # add_results_formula!(data, :gen, :fom_cost,      "sum(fom * ecap)",         Dollars, "Fixed Operation and Maintenance paid, in dollars")
    # add_results_formula!(data, :gen, :fom_per_mwh,   "fom_cost / egen_total",   DollarsPerMWhGenerated, "Fixed Operation and Maintenance paid per MWh of energy generated")
    # add_results_formula!(data, :gen, :fom_cost,      "sum(capex * ecap)",       Dollars, "Fixed Operation and Maintenance paid, in dollars")
    # add_results_formula!(data, :gen, :capex_per_mwh, "capex_cost / egen_total", DollarsPerMWhGenerated, "Capital expenditures paid per MWh of energy generated")
    # add_results_formula!(data, :gen, :cf_avg,        "egen_total / ecap_total", MWhGeneratedPerMWhCapacity, "Average Capacity Factor")

    # add_results_formula!(data, :gen, :fuel_cost,  "sum(fuel_price * heat_rate * egen)", Dollars, "Total cost of fuel")
    # add_results_formula!(data, :gen, :fuel_price_per_mwh, "fuel_cost / egen_total", DollarsPerMWhGenerated, "Fuel price per MWh generated")
    # add_results_formula!(data, :gen, :variable_cost, "fuel_cost + vom_cost", Dollars, "Variable costs for operation.")
    # add_results_formula!(data, :gen, :variable_cost_per_mwh, "(fuel_cost + vom_cost) / egen_total", Dollars, "Variable costs for operation.")



end


"""
    process_results!(config::OrderedDict, data::OrderedDict) -> data

Calls [`modify_results!(mod, config, data)`](@ref) for each `Modification` in `config`.  Stores the results into `get_out_path(config, "data_processed.jls")` if `config[:save_data_processed]` is `true` (default).
"""
function process_results!(config::OrderedDict, data::OrderedDict)
    log_header("PROCESSING RESULTS")

    for (name, mod) in get_mods(config)
        modify_results!(mod, config, data)
    end

    if get(config, :save_data_processed, true)
        serialize(get_out_path(config,"data_processed.jls"), data)
    end

    return data
end

"""
    process_results!(config; processed=true) -> data

This reads `data` in, then calls [`process_results!(config, data)`](@ref).  
* `processed=false` - reads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - reads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(config; processed=true)
    if processed
        data = read_processed_results(config)
    else
        data = read_parsed_results(config)
    end
    return process_results!(config, data)
end
export process_results!

"""
    process_results!(mod_file::String, out_path::String; processed=true) -> data

Processes the results the [`Modification`](@ref)s found in `mod_file`, a .yml file similar to a `config` file (see [`read_config`](@ref)), only requiring the `mods` field.
* `processed=false` - reads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - reads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(mod_file::String, out_path::String; processed=true)

    # Load the config, and the modifications
    config = read_config(out_path)
    mods = _read_config(mod_file)
    convert_mods!(mods)

    # Merge the mods into config, overwriting anything in config
    merge!(config, mods)

    # Make sure we are using the right out_path.
    config[:out_path] = out_path

    # Now call process_results!
    process_results!(config; processed)
end
export process_results!
