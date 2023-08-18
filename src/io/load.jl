"""
    setup_table!(config, data, ::Val{:nominal_load})

Set up the load table.

Also calls the following:
* [`shape_nominal_load!(config, data)`](@ref) - scales hourly load power by an hourly load profile by arbitrary region
* [`match_nominal_load!(config, data)`](@ref) - matches annual load energy by arbitrary region
* [`add_nominal_load!(config, data)`](@ref) - adds hourly load power by arbitrary region
"""
function setup_table!(config, data, ::Val{:nominal_load})
    load = get_table(data, :nominal_load)
    ar = [load.plnom0[i] for i in 1:nrow(load), j in 1:get_num_years(data), k in 1:get_num_hours(data)] # nload * nyr * nhr
    data[:load_array] = ar

    # Grab views of the load for the pd column of the bus table
    plnom = map(i->view(ar, i, :, :), 1:nrow(load))

    add_table_col!(data, :nominal_load, :plnom, plnom, MWLoad, "Load power by the load element")
    bus = get_table(data, :bus)
    plnom_bus = [LoadContainer() for _ in 1:nrow(bus)]

    add_table_col!(data, :bus, :plnom, plnom_bus, MWLoad, "Average MW of power load")
    for row in eachrow(load)
        bus_idx = row.bus_idx::Int64
        c = bus[bus_idx, :plnom]
        _add_view!(c, row.plnom)
    end

    # Modify the load by shaping, matching, and adding
    haskey(config, :load_shape_file) && shape_nominal_load!(config, data)
    haskey(config, :load_match_file) && match_nominal_load!(config, data)
    haskey(config, :load_add_file)   && add_nominal_load!(config, data)
end

"""
    shape_nominal_load!(config, data)

Shapes the hourly load to match profiles given in `config[:load_shape_file]`.  See [`summarize_table(::Val{:load_shape})`](@ref) for more details

Load power often changes on an hourly basis. The `load_shape_table` allows the user to provide hourly load profiles with which to scale the base load power for load regions, types, or even specific load elements.  Each row of the table represents a set of load elements, and the hourly load profile with which to scale them.  For load elements that fall in multiple sets, the hourly load will be scaled by each profile, in order.
"""
function shape_nominal_load!(config, data)
    load_shape_table = get_table(data, :load_shape)
    bus_table = get_table(data, :bus)
    nominal_load = get_table(data, :nominal_load)
    load_arr = get_load_array(data)
    
    # Grab the hour index for later use
    hr_idx = findfirst(s->s=="h1",names(load_shape_table))

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)


    # Add columns to the nominal_load so we can group more easily
    all_areas = unique(load_shape_table.area)
    filter!(!isempty, all_areas)
    nominal_load_names = names(nominal_load)
    areas_to_join = setdiff(all_areas, nominal_load_names)
    bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
    leftjoin!(nominal_load, bus_view, on=:bus_idx)
    
    # Document in the summary table
    for col in areas_to_join
        add_table_col!(data, :nominal_load, Symbol(col), nominal_load[!,Symbol(col)], get_table_col_unit(data, :bus, col), get_table_col_description(data, :bus, col); warn_overwrite = false)
    end
    
    dropmissing!(nominal_load, areas_to_join)
    grouping_variables = copy(all_areas)

    "load_type" in nominal_load_names && push!(grouping_variables, "load_type")

    gdf = groupby(nominal_load, grouping_variables)

    # Loop through each row in the load_shape_table
    for (i, row) in enumerate(eachrow(load_shape_table))
        get(row, :status, true) || continue

        shape = Float64[row[i_hr] for i_hr in hr_idx:(hr_idx + nhr - 1)]

        if !hasproperty(row, :year) || isempty(row.year)
            yr_idx = 1:get_num_years(data)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue # This row is for a year that we aren't simulating now
        end
        
        # Pull out some data to use
        load_type = get(row, :load_type, "")
        area = get(row, :area, "")
        subarea = get(row, :subarea, "")

        # Loop through the sub-dataframes
        for key in eachindex(gdf)
            isempty(load_type) || load_type == key.load_type || continue
            isempty(area) || isempty(subarea) || subarea == key[area] || continue

            sdf = gdf[key]
            row_idx = getfield(sdf, :rows)
            scale_hourly!(load_arr, shape, row_idx, yr_idx)
            
            # Or use below to scale the views
            # scale_hourly!(sdf.pd, shape, yr_idx)  
        end
    end
end
export shape_nominal_load!

"""
    match_nominal_load!(config, data)

Match the yearly load by area given in `config[:load_match_file]`, updates the `pd` field of the `data[:bus]`.  See [`summarize_table(::Val{:load_match})`](@ref) for more details.

Often, we want to force the total energy load for a set of load elements over a year to match load projections from a data source.  The `load_match_table` allows the user to provide yearly energy load targets, in \$MWh\$, to match.  The matching weights each hourly load by the number of hours spent at each of the representative hours, as provided in the `hours` table, converting from \$MW\$ power load over the representative hour, into \$MWh\$.
"""
function match_nominal_load!(config, data) 
    load_match_table = data[:load_match]
    bus_table = get_table(data, :bus)
    nominal_load = data[:nominal_load]
    load_arr = get_load_array(data)

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)


    # Add columns to the nominal_load so we can group more easily
    all_areas = unique(load_match_table.area)
    filter!(!isempty, all_areas)
    nominal_load_names = names(nominal_load)
    areas_to_join = setdiff(all_areas, nominal_load_names)
    
    if ~isempty(areas_to_join)
        bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
        leftjoin!(nominal_load, bus_view, on=:bus_idx)
        dropmissing!(nominal_load, areas_to_join)
    end

    # Document in the summary table
    for col in areas_to_join
        add_table_col!(data, :nominal_load, Symbol(col), nominal_load[!,Symbol(col)], get_table_col_unit(data, :bus, col), get_table_col_description(data, :bus, col); warn_overwrite = false)
    end

    hr_weights = get_hour_weights(data)
    
    for i = 1:nrow(load_match_table)
        row = load_match_table[i, :]
        if get(row, :status, true) == false
            continue
        end

        # Get the year indices to match
        yr_idx_2_match = Dict{Int64, Float64}()
        
        for (yr_idx, yr) in enumerate(get_years(data))
            row[yr] == -Inf && continue
            push!(yr_idx_2_match, yr_idx=>row[yr])
        end
        filters = parse_comparisons(row)

        nominal_load = get_table(data, :nominal_load, filters)
        
        isempty(nominal_load) && continue

        row_idx = getfield(nominal_load, :rows)

        for (yr_idx, match) in yr_idx_2_match
            _match_yearly!(load_arr, match, row_idx, yr_idx, hr_weights)
        end
    end
    return data
end
export match_nominal_load!

"""
    add_nominal_load!(config, data)

Add load power in `config[:load_add_file]` to load elements after the annual match in [`match_nominal_load!`](@ref)

We may wish to provide additional load after the match so that we can compare the difference.
"""
function add_nominal_load!(config, data)
    load_add_table = data[:load_add]
    bus_table = get_table(data, :bus)
    nominal_load = data[:nominal_load]
    load_arr = get_load_array(data)

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)


    # Grab the hour index for later use
    hr_idx = findfirst(s->s=="h1",names(load_add_table))

    # Add columns to the nominal_load so we can group more easily
    all_areas = unique(load_add_table.area)
    filter!(!isempty, all_areas)
    nominal_load_names = names(nominal_load)
    areas_to_join = setdiff(all_areas, nominal_load_names)
    
    if ~isempty(areas_to_join)
        bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
        leftjoin!(nominal_load, bus_view, on=:bus_idx)
        dropmissing!(nominal_load, areas_to_join)
    end

    # Document in the summary table
    for col in areas_to_join
        add_table_col!(data, :nominal_load, Symbol(col), nominal_load[!,Symbol(col)], get_table_col_unit(data, :bus, col), get_table_col_description(data, :bus, col); warn_overwrite = false)
    end

    # Loop through each row in the load_shape_table
    for i in 1:nrow(load_add_table)
        row = load_add_table[i, :]

        get(row, :status, true) || continue
        shape = Float64[row[i_hr] for i_hr in hr_idx:(hr_idx + nhr - 1)]

        if !hasproperty(row, :year) || isempty(row.year)
            yr_idx = 1:get_num_years(data)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue # This row is for a year that we aren't simulating now
        end

        filters = parse_comparisons(row)

        sdf = get_table(data, :nominal_load, filters)
        
        isempty(sdf) && continue

        row_idxs = getfield(sdf, :rows)

        
        # we need to find the amount of power to add to each load element, where it is weighted by their relative weights.
        plnom0_total = sum(sdf.plnom0)

        for (i,row_idx) in enumerate(row_idxs)
            plnom0 = sdf[i, :plnom0]::Float64
            s = plnom0/plnom0_total
            add_hourly_scaled!(load_arr, shape, s, row_idx, yr_idx)
        end
    end
    return data
end
export add_nominal_load!


# Table Summaries
################################################################################

@doc """
    summarize_table(::Val{:nominal_load})

$(table2markdown(summarize_table(Val(:nominal_load))))
"""
function summarize_table(::Val{:nominal_load})
    df = TableSummary()
    push!(df, 
        (:bus_idx, Int64, NA, true, "The bus index of the load element"),
        (:plnom0, Float64, MWLoad, true, "The nominal load power of the load element"),
        (:load_type, String, NA, false, "The type of load represented by this load element."),
    )
    return df
end

@doc """
    summarize_table(::Val{:load_shape})

$(table2markdown(summarize_table(Val(:load_shape))))
"""
function summarize_table(::Val{:load_shape})
    df = TableSummary()
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load shape.  Leave blank to not filter by type."),
        (:year, String, Year, false, "The year to apply the load profile to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this shape adjustment"),
        (:h_, Float64, Ratio, true, "Load scaling factor of hour 1.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end

@doc """
    summarize_table(::Val{:load_match})

$(table2markdown(summarize_table(Val(:load_match))))
"""
function summarize_table(::Val{:load_match})
    df = TableSummary()
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load match.  Leave blank to not filter by type."),
        (:status, Bool, NA, false, "Whether or not to use this match"),
        (:y_, Float64, MWhLoad, true, "The annual load energy to match for the weighted load of all load elements in the loads specified.  Include 1 column for each year being simulated.  I.e. \"y2030\", \"y2035\", ... To not match a specific year, make it -Inf"),
    )
    return df
end


@doc """
    summarize_table(::Val{:load_add})

$(table2markdown(summarize_table(Val(:load_add))))
"""
function summarize_table(::Val{:load_add})
    df = TableSummary()
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load add.  Leave blank to not filter by type."),
        (:year, String, Year, false, "The year to apply the load profile to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this addition"),
        (:h_, Float64, MWLoad, true, "Amount of load power to add in hour _.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end
export summarize_table