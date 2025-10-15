
"""
    RetailPrice(;file, name, col_sort=:initial_order) <: Modification

This is a mod that outputs computed results, given a `file` representing the template of the things to be aggregated.  `name` is simply the name of the modification, and will be used as the root for the filename that the aggregated information is saved to.  This can be used for computing results or welfare.

## Keyword Arguments
* `file` - the file pointing to a table specifying which results to calculate
* `name` - the name of the mod, do not need to specify in a config file
* `col_sort` - the column(s) to sort by.  Defaults to the order in which they were originally specified.
* `cross_table` - indicates that the result is pulling results from multiple tables. Defaults to false.

The `file` should represent a csv table with the following columns:
* `table_name` - the name of the table being aggregated.  i.e. `gen`, `bus`, etc.  If you leave it empty, it will call `compute_welfare` instead of `compute_result`
* `result_name` - the name of the column in the table being aggregated.  Note that the column must have a Unit accessible via [`get_table_col_unit`](@ref).
* `filter_` - the filtering conditions for the rows of the table. I.e. `filter1`.  See [`parse_comparisons`](@ref) for information on what types of filters could be provided.
* `filter_years` - the filtering conditions for the years to be aggregated.  See [`parse_year_idxs`](@ref) for information on the year filters.
* `filter_hours` - the filtering conditions for the hours to be aggregated.  See [`parse_hour_idxs`](@ref) for information on the hour filters.

Note that, for the `filter_` or `filter_hours` columns, if a column name of the data table (or hours table) is given, new rows will be created for each unique value of that column.  I.e. if a value of `gentype` is given, there will be made a new row for `gentype=>coal`, `gentype=>ng`, etc.
"""

struct RetailPrice <: Modification
    file::String
    name::Symbol
    table::DataFrame
    calibrator_file::String
    cal_table:: Bool
    cal:: Bool
    col_sort
    function RetailPrice(;file, name, calibrator_file="", cal_table=false, cal=true, col_sort=:initial_order)
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
        return new(file, name, table, calibrator_file, cal_table, cal, col_sort)
    end
end

export RetailPrice


mod_rank(::Type{<:RetailPrice}) = 5.0

fieldnames_for_yaml(::Type{RetailPrice}) = (:file,)


function modify_results!(m::RetailPrice, config, data)
    table = copy(m.table)
    table.initial_order = 1:nrow(table)

    filter_cols = setdiff(propertynames(table), [:table_name, :result_name])

    # for any rows that are not a pair, separate into multiple rows
    not_pair_idx = findfirst(not_a_full_filter, eachrow(table))
    while not_pair_idx !== nothing
        row = table[not_pair_idx, :]
        filter_col_idx = findfirst(filter_col->not_a_full_filter(row[filter_col]), filter_cols)
        col_to_expand = filter_cols[filter_col_idx]
        table_name = row[:table_name]
        result_name = row[:result_name]

        if col_to_expand == :filter_hours
            area = row.filter_hours
            hours_table_col = get_table_col(data, :hours, area)
            subareas = Base.sort!(String.(string.(unique(hours_table_col))), by=hours_sortby)
        elseif col_to_expand == :filter_years &&  row[col_to_expand] == ":"
            area = :years
            subareas = data[area]
        else
            area = row[col_to_expand]
            table_names = get_cross_table(data, table_name)[result_name]
            all(hasproperty(get_table(data, t), area) for (t, _) in table_names) || error("Some tables are missing property $(area)")
            data_table_col = get_table_col(data, first(keys(table_names)), area)
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

    @info "Calculating results for $(nrow(table)) rows in RetailPrice $(m.name)"
    results_formulas = get_results_formulas(data)
    cal_table = DataFrame(area = String[], subarea = [], year=[],  value = [])
    #to do: check that the each ref price has a corresponding retail rate or else provide warning
    # table.value = map(eachrow(table)) do row
    if !hasproperty(table, :value)
        table.value = Vector{Union{Missing, Float64}}(missing, nrow(table))
    end
    for i in 1:nrow(table)
        table_name = table[i, :table_name]
        result_name = table[i,:result_name]
        idxs = parse_comparisons(table[i,:])
        yr_idxs = parse_year_idxs(table[i,:filter_years])
        hr_idxs = parse_hour_idxs(table[i,:filter_hours])
        
        if hr_idxs !== Colon()
            @warn "Hourly retail price calculations are not set up."
            return 0.0
        else
            if m.cal_table == true 
                val, cal_row = compute_retail_price(data, result_name, m.calibrator_file, idxs, yr_idxs, hr_idxs)
                push!(cal_table, cal_row)
            elseif m.cal == true
                val = compute_retail_price(data, result_name, m.cal, m.calibrator_file, idxs, yr_idxs, hr_idxs)
            else
                val =  compute_retail_price(data, result_name, idxs, yr_idxs, hr_idxs)
            end
        end
        table.value[i]= val 
    end    
    sort!(table, m.col_sort)
    select!(table, Not(:initial_order))
    CSV.write(get_out_path(config, string(m.name, ".csv")), table)
    results = get_results(data)
    results[m.name] = table

    CSV.write(get_out_path(config, string(m.name, "_cals.csv")), cal_table)
    return
end


# function extract_results(m::RetailPrice, config, data)
#     results = get_results(data)
#     # haskey(results, m.name) || modify_results!(m, config, data)
#     modify_results!(m, config, data)
#     return get_result(data, m.name)
# end

# function combine_results(m::RetailPrice, post_config, post_data)
    
#     res = join_sim_tables(post_data, :value)

#     CSV.write(get_out_path(post_config, "$(m.name)_combined.csv"), res)
# end

