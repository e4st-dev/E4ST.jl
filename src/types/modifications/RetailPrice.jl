
"""
    RetailPrice(;file, name, col_sort=:initial_order) <: Modification

This is a mod that outputs retail prices, given a `file` that indicates for which regions and years the retail price should be calculated.  `name` is simply the name of the modification, and will be used as the root for the filename that the retail rates are saved to. 
The mod pulls values across different tables to calculate one retail rate. The specific terms that go into this cross-table calculation can be found in retail_price.jl. 

The mod will also adjust the retail price values through calibration based on the `cal_mode` argument. If `cal_mode` is set to `none`, the retail prices will be unadjusted. If `cal_mode` is `get_val_values` the mod will use the reference price values to get calibration
values. If `cal_mod` is set to `calibrate`, the calibrator values will be read in from the `calibrator_file` and used to adjust the calculated retail rates.

## Keyword Arguments
* `file` - the file pointing to a table specifying which retail prices to calculate
* `name` - the name of the mod, do not need to specify in a config file
* `cal_mode` - a string that indicates the calibration mode. Options are `none`, `get_cal_values`, and `calibrate`. Defaults to `none`.
* `calibrator_file` - the file pointing to a table that contains reference price values or calibration values, depending on `cal_mode`.
* `col_sort` - the column(s) to sort by.  Defaults to the order in which they were originally specified.

The `file` should represent a csv table with the following columns:
* `table_name` - the name of the table being aggregated.  i.e. `gen`, `bus`, etc.  If you leave it empty, it will call `compute_welfare` instead of `compute_result`
* `result_name` - the name of the column in the table being aggregated.  Note that the column must have a Unit accessible via [`get_table_col_unit`](@ref).
* `filter_` - the filtering conditions for the rows of the table. I.e. `filter1`.  See [`parse_comparisons`](@ref) for information on what types of filters could be provided.
* `filter_years` - the filtering conditions for the years to be aggregated.  See [`parse_year_idxs`](@ref) for information on the year filters.
* `filter_hours` - the filtering conditions for the hours to be aggregated.  See [`parse_hour_idxs`](@ref) for information on the hour filters. the retail rate mod is not set up to calculate hourly values.

Note that, for the `filter_` or `filter_hours` columns, if a column name of the data table (or hours table) is given, new rows will be created for each unique value of that column.  I.e. if a value of `gentype` is given, there will be made a new row for `gentype=>coal`, `gentype=>ng`, etc.
However, the filter must be present in each of tables in the cross-table calculation for retail price or it will error. Further, the calibration feature can only handle one filter_ column beyond filter_hours and filter_years (which will most likely designate the region of interest for the retail price calcualation).
"""

struct RetailPrice <: Modification
    file::String
    name::Symbol
    table::DataFrame
    cal_mode:: String
    ref_price_file::String
    calibrator_file::String
    col_sort
    function RetailPrice(;file, name, ref_price_file="", calibrator_file="", cal_mode="none", col_sort=:initial_order)
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
        # errors if no calibrator file is provided
        if cal_mode == "get_cal_values"
            isempty(ref_price_file) && error("Ref price file required when cal_mode is set to $(cal_mode).")
        elseif cal_mode == "calibrate"
            isempty(calibrator_file) && error("Calibrator file required when cal_mode is set to $(cal_mode).")
        end
        return new(file, name, table,  cal_mode, ref_price_file, calibrator_file, col_sort)
    end
end

export RetailPrice


mod_rank(::Type{<:RetailPrice}) = 5.0

fieldnames_for_yaml(::Type{RetailPrice}) = (:file,)


function summarize_table(::Val{:ref_price})
    df = TableSummary()
    push!(df,
        (:area, String, NA, true, "The area that the price applies for i.e. `nation`.  Leave blank if grid-wide"),
        (:subarea, String, NA, true, "The subarea that the price applies for i.e. `narnia`.  Leave blank if grid-wide"),
        (:year, String, NA, false, "Year of corresponding reference price. If no column, them same calibrator value will be applied in each year."),
        (:ref_price, Float64, DollarsPerMWhServed, true, "Reference price for retail rate in \$/MWh."),
    )
    return df
end


 function summarize_table(::Val{:retail_calibrator})
    df = TableSummary()
    push!(df,
        (:area, String, NA, true, "The area that the price applies for i.e. `nation`.  Leave blank if grid-wide"),
        (:subarea, String, NA, true, "The subarea that the price applies for i.e. `narnia`.  Leave blank if grid-wide"),
        (:year, String, NA, false, "Year of corresponding reference price. If no column, the same calibrator value is used in every year."),
        (:cal_value, Float64, DollarsPerMWhServed, true, "Calibrator value for retail rate in \$/MWh."),
    )
    return df
end


# function takes the table from file and expands the filter columns so there is a row for each calculated result
# eg if file has a filter_ with the value "state", the table will be expanded so that there is a row for each state
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

    # function that calculates retail price for each row in table
    get_retail_price(m, config, data, table)

    return
end

function extract_results(m::RetailPrice, config, data)
    results = get_results(data)
    # haskey(results, m.name) || modify_results!(m, config, data)
    modify_results!(m, config, data)
    return get_result(data, m.name)
end

function combine_results(m::RetailPrice, post_config, post_data)
    res = join_sim_tables(post_data, :value)
    CSV.write(get_out_path(post_config, "$(m.name)_combined.csv"), res)
end

# wrapper function that will dispatch a different get_retail_price method based on cal_mode arg
function get_retail_price(m::RetailPrice, config, data, table)
    @info "Calculating results for $(nrow(table)) rows in RetailPrice $(m.name)"
    get_retail_price((Val(Symbol(m.cal_mode))), m, config, data, table)
end

# specialized method for retail rates with no cal_mode none
function get_retail_price(::Val{:none}, m, config, data, table)

    if !hasproperty(table, :value)
        table.value = Vector{Union{Missing, Float64}}(missing, nrow(table))
    end
    
    
    for row in eachrow(table)
        table_name = row[:table_name]
        result_name = row[:result_name]

        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row[:filter_years])
        hr_idxs = parse_hour_idxs(row[:filter_hours])

        @assert hr_idxs == Colon() "Retail price mod is not set up to handle hourly retail rates."

        val =  compute_retail_price(m, data, result_name, idxs, yr_idxs, hr_idxs)

        row[:value] = val
    end
    sort!(table, m.col_sort)
    select!(table, Not(:initial_order))
    CSV.write(get_out_path(config, string(m.name, ".csv")), table)
    results = get_results(data)
    results[m.name] = table
end

# specialized method for retail rates with no cal_mode get_cal_values
function get_retail_price(::Val{:get_cal_values}, m::RetailPrice, config, data, table)
    # set up table that will contain calibrator values
    cal_table = DataFrame(
    area         = String[],
    subarea      = Union{String, Int}[],
    year         = String[],
    ref_price    = Float64[],
    retail_price = Float64[],
    cal_value    = Float64[],
    elserv_total = Float64[],
    elserv_ratio = Float64[]
    )

    # add value column to results table if it doesn't exist
    if !hasproperty(table, :value)
        table.value = Vector{Union{Missing, Float64}}(missing, nrow(table))
    end
    
    for row in eachrow(table)
        table_name = row[:table_name]
        result_name = row[:result_name]

        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row[:filter_years])
        hr_idxs = parse_hour_idxs(row[:filter_hours])

        @assert yr_idxs != Any[] "Retail price calibrator is not set up to handle average retail rate across years."
        @assert hr_idxs == Colon() "Retail price mod is not set up to handle hourly retail rates."

        val, cal_row = compute_retail_price(m, data, result_name, idxs, yr_idxs, hr_idxs)

        !isempty(cal_row) && push!(cal_table, cal_row)
        row[:value] = val
    end

    sort!(table, m.col_sort)
    select!(table, Not(:initial_order))
    CSV.write(get_out_path(config, string(m.name, ".csv")), table)
    results = get_results(data)
    results[m.name] = table

    # second calibrator adjustment to calibrate with full region
    full_cal!(m, data, table, cal_table)
    select!(cal_table, 
    [c for c in (:area, :subarea, :year, :cal_value) if any(!ismissing, cal_table[!, c]) && any(x -> x != "" && !ismissing(x), cal_table[!, c])])
    CSV.write(get_out_path(config, string(m.name, "_cals.csv")), cal_table)
    results[:calibrator_values] = cal_table

end

function get_retail_price(::Val{:calibrate}, m, config, data, table)

    # add value column to results table if it doesn't exist
    if !hasproperty(table, :value)
        table.value = Vector{Union{Missing, Float64}}(missing, nrow(table))
    end
    
    for row in eachrow(table)
        table_name = row[:table_name]
        result_name = row[:result_name]

        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row[:filter_years])
        hr_idxs = parse_hour_idxs(row[:filter_hours])

        @assert yr_idxs != Any[] "Retail price calibrator is not set up to handle average retail rate across years."
        @assert hr_idxs == Colon() "Retail price mod is not set up to handle hourly retail rates."

        val = compute_retail_price(m, data, result_name, idxs, yr_idxs, hr_idxs)

        row[:value] = val
    end

    sort!(table, m.col_sort)
    select!(table, Not(:initial_order))
    CSV.write(get_out_path(config, string(m.name, ".csv")), table)
    results = get_results(data)
    results[m.name] = table    
end

# final calibration value for full model
# example: for a state level model, ensure that the weighted average prices of all states are calibrated to the national average price
function full_cal!(m, data, table, cal_table)

    ref_price_table = read_table(m.ref_price_file)

    # get the weighted average retail price acorss all areas
    avg_price = sum(cal_table.ref_price .* cal_table.elserv_ratio)
    
    subset = filter(row -> row.area == "" && row.subarea == "", ref_price_table)

    # get the average reference price
    if nrow(subset) == 0
        avg_price_ref = avg_price # set refrence price to the calculated average price so that the calibrator value will be 0
    else
        avg_price_ref = subset[1, :ref_price]
    end
    
    # calculate and add the final cal value to existing cal values
    for row in eachrow(cal_table[(cal_table.area .!= "") .& (cal_table.subarea .!= ""), :])
        # average calibrator value is the differnce between the reference price minus the calculated price weighted by load
        cal = (avg_price_ref - avg_price) * row[:elserv_ratio]
        row[:cal_value] += cal
    end

    return cal_table
end
