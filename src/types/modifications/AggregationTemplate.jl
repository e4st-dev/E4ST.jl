
"""
    AggregationTemplate(;file, name) <: Modification

This is a mod that outputs aggregated results, given a `file` representing the template of the things to be aggregated.  `name` is simply the name of the modification, and will be used as the root for the filename that the aggregated information is saved to.

The `file` should represent a csv table with the following columns:
* `table_name` - the name of the table being aggregated.  i.e. `gen`, `bus`, etc.
* `result_name` - the name of the column in the table being aggregated.  Note that the column must have a Unit accessible via [`get_table_col_unit`](@ref).
* `filter_` - the filtering conditions for the rows of the table. I.e. `filter1`.  See [`parse_comparisons`](@ref) for information on what types of filters could be provided.
* `filter_years` - the filtering conditions for the years to be aggregated.  See [`parse_year_idxs`](@ref) for information on the year filters.
* `filter_hours` - the filtering conditions for the hours to be aggregated.  See [`parse_hour_idxs`](@ref) for information on the hour filters.

Note that, for the `filter_` or `filter_hours` columns, if a column name of the data table (or hours table) is given, new rows will be created for each unique value of that column.  I.e. if a value of `gentype` is given, there will be made a new row for `gentype=>coal`, `gentype=>ng`, etc.
"""
struct AggregationTemplate <: Modification
    file::String
    name::Symbol
    table::DataFrame
    function AggregationTemplate(;file, name)
        table = read_table(file)
        force_table_types!(table, name, 
            :table_name=>Symbol,
            :result_name=>Symbol,
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

mod_rank(::Type{<:AggregationTemplate}) = 5.0

fieldnames_for_yaml(::Type{AggregationTemplate}) = (:file,)
function modify_results!(mod::AggregationTemplate, config, data)
    table = mod.table

    filter_cols = setdiff(propertynames(table), [:table_name, :result_name])

    # for any rows that are not a pair, separate into multiple rows
    not_pair_idx = findfirst(not_a_full_filter, eachrow(table))
    while not_pair_idx !== nothing
        row = table[not_pair_idx, :]
        filter_col_idx = findfirst(filter_col->not_a_full_filter(row[filter_col]), filter_cols)
        col_to_expand = filter_cols[filter_col_idx]

        if col_to_expand == :filter_hours
            area = row.filter_hours
            hours_table_col = get_table_col(data, :hours, area)
            subareas = sort!(unique(hours_table_col))
        else
            area = row[col_to_expand]
            data_table_col = get_table_col(data, row.table_name, area)
            subareas = sort!(unique(data_table_col))
        end

        
        row_dict = Dict(pairs(row))
        for subarea in subareas
            # Add a row right after the original row
            row_dict[col_to_expand] = "$area=>$subarea"
            insert!(table, not_pair_idx+1, row_dict)
        end

        deleteat!(table, not_pair_idx)

        # Find the next index that is not a pair, to be expanded
        not_pair_idx = findfirst(not_a_full_filter, eachrow(table))
    end

    table.value = map(eachrow(table)) do row
        table_name = row.table_name
        result_name = row.result_name
        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row.filter_years)
        hr_idxs = parse_hour_idxs(row.filter_hours)
        return compute_result(data, table_name, result_name, idxs, yr_idxs, hr_idxs)
    end    
    CSV.write(get_out_path(config, string(mod.name, ".csv")), table)
    results = get_results(data)
    results[mod.name] = table
    return
end

function extract_results(m::AggregationTemplate, config, data)
    results = get_results(data)
    haskey(results, m.name) || modify_results!(m, config, data)
    return get_result(data, m.name)
end

function combine_results(m::AggregationTemplate, post_config, post_data)
    
    res = join_sim_tables(post_data, :value)

    CSV.write(get_out_path(post_config, "$(m.name)_combined.csv"), res)
end

function not_a_full_filter(row::DataFrameRow)
    not_a_full_filter(row.filter_years) && return true
    not_a_full_filter(row.filter_hours) && return true
    for i in 1:1000
        col_name = "filter$i"
        hasproperty(row, col_name) || break
        not_a_full_filter(row[col_name]) && return true
    end
    return false
end

function not_a_full_filter(s::AbstractString)
    isempty(s) && return false
    all(isnumeric, s) && return false
    contains(s, "=>") && return false
    startswith(s, "[") && return false
    startswith(s, "y2") && return false
    return true
end