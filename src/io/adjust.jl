"""
    summarize_table(::Val{:adjust_hourly}) -> summary
"""
function summarize_table(::Val{:adjust_hourly})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:table_name, AbstractString, NA, true, "The name of the table to adjust.  Leave blank if this adjustment is intended for a variable in `data`"),
        (:variable_name, AbstractString, NA, true, "The name of the variable/column to adjust"),
        (:operation, String, NA, true, "The operation to perform.  Could be add, scale, or set."),
        (:filter_, String, NA, true, "There can be multiple filter conditions - `filter1`, `filter2`, etc.  It denotes a comparison used for selecting the table rows to apply the adjustment to.  See `comparison` for examples"),
        (:year, String, Year, true, "The year to adjust, expressed as a year string prepended with a \"y\".  I.e. \"y2022\".  Leave blank to adjust all years"),
        (:status, Bool, NA, false, "Whether or not to use this adjustment"),
        (:h_, Float64, Ratio, true, "Demand scaling factor of hour 1.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end

"""
    summarize_table(::Val{:adjust_yearly}) -> summary
"""
function summarize_table(::Val{:adjust_yearly})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load match.  Leave blank to not filter by type."),
        (:status, Bool, NA, false, "Whether or not to use this match"),
        (:y_, Float64, MWhDemanded, true, "The annual demanded energy to match for the weighted demand of all load elements in the loads specified.  Include 1 column for each year being simulated.  I.e. \"y2030\", \"y2035\", ... To not match a specific year, make it -Inf"),
    )
    return df
end



"""
    setup_table!(config, data, ::Val{:adjust_hourly})
"""
function setup_table!(config, data, ::Val{:adjust_hourly})
    adjust_table = get_table(config, :adjust_hourly)
    for row in eachrow(adjust_table)
        adjust_hourly!(config, data, row)
    end
end


"""
    adjust_hourly!(config, data, row)

Apply an hourly adjustment given `row` from the `adjust_hourly` table.
"""
function adjust_hourly!(config, data, row)
    table_name = row.table_name::AbstractString
    variable_name = row.variable_name::AbstractString
    oper = row.operation::AbstractString
    if isempty(table_name)
        # TODO: Fill this in
    end

    # Get the year to perform the adjustment on
    all_years = get_years(data)
    nyr = get_num_years(data)
    if isempty(row.year)
        yr_idx = (:)
    elseif row.year ∈ all_years
        yr_idx = findfirst(==(row.year), all_years)
    else
        return
    end

    # Get the filtered table with which to perform the adjustment
    pairs = parse_comparisons(row)
    table = get_table(data, table_name, pairs)
    isempty(table) && return
    hasproperty(table, variable_name) || error("Table $table_name has no column $variable_name to adjust in `adjust_hourly!`")


    # Perform the adjustment on each row of the table
    vals = [row["h$h"] for h in 1:get_num_hours(data)]
    for r in eachrow(table)
        oper == "add"   && (r[variable_name] = add_hourly(r[variable_name], vals, yr_idx; nyr))
        oper == "scale" && (r[variable_name] = scale_hourly(r[variable_name], vals, yr_idx; nyr))
        oper == "set"   && (r[variable_name] = set_hourly(r[variable_name], vals, yr_idx; nyr))
    end
    return
end


"""
    setup_table!(config, data, ::Val{:adjust_yearly})
"""
function setup_table!(config, data, ::Val{:adjust_yearly})
    
end
