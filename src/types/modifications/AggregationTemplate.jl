
"""
    AggregationTemplate(;file, name) <: Modification

This is a mod that outputs aggregated results, given a `file` representing the template of the things to be aggregated.  `name` is simply the name of the modification, and will be used as the root for the filename that the aggregated information is saved to.

The `file` should represent a csv table with the following columns:
* `operation` - choose between "total", "average", "minimum", and "maximum"
* `table_name` - the name of the table being aggregated.  i.e. `gen`, `bus`, etc.
* `column_name` - the name of the column in the table being aggregated.  Note that the column must have a Unit accessible via [`get_table_col_unit`](@ref).
* `filter_` - the filtering conditions for the rows of the table. I.e. `filter1`.  See [`parse_comparisons`](@ref) for information on what types of filters could be provided.
* `filter_years` - the filtering conditions for the years to be aggregated.  See [`parse_year_idxs`](@ref) for information on the year filters.
* `filter_hours` - the filtering conditions for the hours to be aggregated.  See [`parse_hour_idxs`](@ref) for information on the hour filters.
"""
struct AggregationTemplate <: Modification
    file::String
    name::Symbol
    table::DataFrame
    function AggregationTemplate(;file, name)
        table = read_table(file)
        force_table_types!(table, name, 
            :operation=>Aggregation,
            :table_name=>Symbol,
            :column_name=>Symbol,
            :filter_years=>String,
            :filter_hours=>String,
        )
        for i in 1:1000
            col_name = "filter$i"
            hasproperty(table, col_name) || continue
            force_table_types!(table, name, col_name=>String)
        end
        return new(file, name, table)
    end
end

export AggregationTemplate


fieldnames_for_yaml(::Type{AggregationTemplate}) = (:file,)
function modify_results!(mod::AggregationTemplate, config, data)
    table = mod.table
    table.value = map(eachrow(table)) do row
        op = row.operation
        table_name = row.table_name
        col_name = row.column_name
        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row.filter_years)
        hr_idxs = parse_hour_idxs(row.filter_hours)
        return aggregate_result(op, data, table_name, col_name, idxs, yr_idxs, hr_idxs)
    end    
    CSV.write(get_out_path(config, string(mod.name, ".csv")), table)
    results = get_results(data)
    results[mod.name] = table
    return
end

struct Aggregation end
function Aggregation(s::AbstractString)
    s == "total" && return total
    s == "average" && return average
    s == "maximum" && return maximum
    s == "minimum" && return minimum
    error("Cannot aggregate with operation $s")
end