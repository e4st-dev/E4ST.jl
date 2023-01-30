
"""
    load_demand_table!(config, data)

Loads the `demand_table` from `config[:demand_file]` into `data[:demand_table]`.

The `demand_table` lets you specify a base demanded power for arbitrary buses.  Buses may have multiple demand elements (for example, a commercial demand, etc.).  See also [`summarize_demand_table`](@ref)
"""
function load_demand_table!(config, data)
    # load in the table and force its types
    demand = load_table(config[:demand_file])
    force_table_types!(demand, :demand, summarize_demand_table())
    data[:demand_table] = demand
    return nothing
end  
export load_demand_table!


"""
    load_demand_shape_table!(config, data)

Loads in `config[:demand_shape_file]` into `data[:demand_shape]`.

See also [`summarize_demand_shape_table()`](@ref), [`shape_demand!(config, data)`](@ref), [`get_demand_shape_table(data)`](@ref).
"""
function load_demand_shape_table!(config, data)
    demand_shape_table = load_table(config[:demand_shape_file])
    force_table_types!(demand_shape_table, :demand_shape, summarize_demand_shape_table())
    force_table_types!(demand_shape_table, :demand_shape, ("h$n"=>Float64 for n in 2:get_num_hours(data))...)
    data[:demand_shape] = demand_shape_table
end
export load_demand_shape_table!

"""
    load_demand_match_table!(config, data)

Loads in `config[:demand_match_file]` into `data[:demand_match]`.

See also [`summarize_demand_match_table()`](@ref), [`match_demand!(config, data)`](@ref), [`get_demand_match_table(data)`](@ref).
"""
function load_demand_match_table!(config, data)
    demand_match_table = load_table(config[:demand_match_file])
    force_table_types!(demand_match_table, :demand_match, summarize_demand_match_table())
    force_table_types!(demand_match_table, :demand_match, (y=>Float64 for y in get_years(data))...)
    data[:demand_match] = demand_match_table
end
export load_demand_match_table!

"""
    load_demand_add_table!(config, data)

Loads in `config[:demand_add_file]` into `data[:demand_add]`.

See also [`summarize_demand_add_table()`](@ref), [`add_demand!(config, data)`](@ref), [`get_demand_add_table(data)`](@ref).
"""
function load_demand_add_table!(config, data)
    demand_add_table = load_table(config[:demand_add_file])
    force_table_types!(demand_add_table, :demand_add, summarize_demand_add_table())
    force_table_types!(demand_add_table, :demand_add, ("h$n"=>Float64 for n in 2:get_num_hours(data))...)
    data[:demand_add] = demand_add_table
end
export load_demand_add_table!

"""
    setup_demand!(config, data)

Set up the demand table.

Also calls the following:
* [`shape_demand!(config, data)`](@ref) - scales hourly demanded power by an hourly demand profile by arbitrary region
* [`match_demand!(config, data)`](@ref) - matches annual demanded energy by arbitrary region
* [`add_demand!(config, data)`](@ref) - adds hourly demanded power by arbitrary region
"""
function setup_demand!(config, data)
    demand = get_table(data, :demand_table)
    ar = [demand.pdem0[i] for i in 1:nrow(demand), j in 1:get_num_years(data), k in 1:get_num_hours(data)] # ndemand * nyr * nhr
    data[:demand_array] = ar

    # Grab views of the demand for the pd column of the bus table
    demand.pdem = map(i->view(ar, i, :, :), 1:nrow(demand))

    bus = get_table(data, :bus)
    bus.pdem = [DemandContainer() for _ in 1:nrow(bus)]

    for row in eachrow(demand)
        bus_idx = row.bus_idx::Int64
        c = bus[bus_idx, :pdem]
        _add_view!(c, row.pdem)
    end

    # Modify the demand by shaping, matching, and adding
    haskey(config, :demand_shape_file) && shape_demand!(config, data)
    haskey(config, :demand_match_file) && match_demand!(config, data)
    haskey(config, :demand_add_file)   && add_demand!(config, data)
end
export setup_demand!

"""
    shape_demand!(config, data)

Shapes the hourly demand to match profiles given in `config[:demand_shape_file]`.  See [`summarize_demand_shape_table`](@ref) for more details

Demanded power often changes on an hourly basis. The `demand_shape_table` allows the user to provide hourly demand profiles with which to scale the base demanded power for demand regions, types, or even specific demand elements.  Each row of the table represents a set of load elements, and the hourly demand profile with which to scale them.  For demand elements that fall in multiple sets, the hourly load will be scaled by each profile, in order.
"""
function shape_demand!(config, data)
    demand_shape_table = data[:demand_shape]
    bus_table = get_table(data, :bus)
    demand_table = data[:demand_table]
    demand_arr = get_demand_array(data)
    
    # Grab the hour index for later use
    hr_idx = findfirst(s->s=="h1",names(demand_shape_table))

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)


    # Add columns to the demand_table so we can group more easily
    all_areas = unique(demand_shape_table.area)
    filter!(!isempty, all_areas)
    demand_table_names = names(demand_table)
    areas_to_join = setdiff(all_areas, demand_table_names)
    bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
    leftjoin!(demand_table, bus_view, on=:bus_idx)
    dropmissing!(demand_table, areas_to_join)
    grouping_variables = copy(all_areas)

    "load_type" in demand_table_names && push!(grouping_variables, "load_type")

    gdf = groupby(demand_table, grouping_variables)

    # Loop through each row in the demand_shape_table
    for i in 1:nrow(demand_shape_table)
        row = demand_shape_table[i, :]
        shape = Float64[row[i_hr] for i_hr in hr_idx:length(row)]


        get(row, :status, true) || continue

        if isempty(row.year)
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
            scale_hourly!(demand_arr, shape, row_idx, yr_idx)
            
            # Or use below to scale the views
            # scale_hourly!(sdf.pd, shape, yr_idx)  
        end
    end
end
export shape_demand!

"""
    match_demand!(config, data)

Match the yearly demand by area given in `config[:demand_match_file]`, updates the `pd` field of the `data[:bus]`.  See [`summarize_demand_match_table`](@ref) for more details.

Often, we want to force the total energy demanded for a set of demand elements over a year to match load projections from a data source.  The `demand_match_table` allows the user to provide yearly energy demanded targets, in \$MWh\$, to match.  The matching weights each hourly demand by the number of hours spent at each of the representative hours, as provided in [`load_hours_table!`](@ref), converting from \$MW\$ power demanded over the representative hour, into \$MWh\$.
"""
function match_demand!(config, data) 
    demand_match_table = data[:demand_match]
    bus_table = get_table(data, :bus)
    demand_table = data[:demand_table]
    demand_arr = get_demand_array(data)

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)


    # Add columns to the demand_table so we can group more easily
    all_areas = unique(demand_match_table.area)
    filter!(!isempty, all_areas)
    demand_table_names = names(demand_table)
    areas_to_join = setdiff(all_areas, demand_table_names)
    
    if ~isempty(areas_to_join)
        bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
        leftjoin!(demand_table, bus_view, on=:bus_idx)
        dropmissing!(demand_table, areas_to_join)
    end

    hr_weights = get_hour_weights(data)
    
    for i = 1:nrow(demand_match_table)
        row = demand_match_table[i, :]
        if get(row, :status, true) == false
            continue
        end

        # Get the year indices to match
        yr_idx_2_match = Dict{Int64, Float64}()
        
        for (yr_idx, yr) in enumerate(get_years(data))
            row[yr] == -Inf && continue
            push!(yr_idx_2_match, yr_idx=>row[yr])
        end
        filters = Pair[]
        
        haskey(row, :load_type) && ~isempty(row.load_type) && push!(filters, :load_type=>row.load_type)
        ~isempty(row.area) && ~isempty(row.subarea) && push!(filters, row.area=>row.subarea)

        demand_table = get_table(data, :demand_table, filters)
        
        isempty(demand_table) && continue

        row_idx = getfield(demand_table, :rows)

        for (yr_idx, match) in yr_idx_2_match
            _match_yearly!(demand_arr, match, row_idx, yr_idx, hr_weights)
        end
    end
    return data
end
export match_demand!

"""
    add_demand!(config, data)

Add demanded power in `config[:demand_add_file]` to demand elements after the annual match in [`match_demand!`](@ref)

We may wish to provide additional demand after the match so that we can compare the difference.
"""
function add_demand!(config, data)
    demand_add_table = data[:demand_add]
    bus_table = get_table(data, :bus)
    demand_table = data[:demand_table]
    demand_arr = get_demand_array(data)

    # Pull out year info that will be needed
    all_years = get_years(data)
    nyr = get_num_years(data)


    # Grab the hour index for later use
    hr_idx = findfirst(s->s=="h1",names(demand_add_table))

    # Add columns to the demand_table so we can group more easily
    all_areas = unique(demand_add_table.area)
    filter!(!isempty, all_areas)
    demand_table_names = names(demand_table)
    areas_to_join = setdiff(all_areas, demand_table_names)
    
    if ~isempty(areas_to_join)
        bus_view = view(bus_table, :, ["bus_idx", areas_to_join...])
        leftjoin!(demand_table, bus_view, on=:bus_idx)
        dropmissing!(demand_table, areas_to_join)
    end

    # Loop through each row in the demand_shape_table
    for i in 1:nrow(demand_add_table)
        row = demand_add_table[i, :]

        get(row, :status, true) || continue
        shape = Float64[row[i_hr] for i_hr in hr_idx:length(row)]

        if isempty(row.year)
            yr_idx = 1:get_num_years(data)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue # This row is for a year that we aren't simulating now
        end

        filters = Pair[]
        
        haskey(row, :load_type) && ~isempty(row.load_type) && push!(filters, :load_type=>row.load_type)
        ~isempty(row.area) && ~isempty(row.subarea) && push!(filters, row.area=>row.subarea)

        sdf = get_table(data, :demand_table, filters)
        
        isempty(sdf) && continue

        row_idxs = getfield(sdf, :rows)

        
        # we need to find the amount of power to add to each demand element, where it is weighted by their relative weights.
        pdem0_total = sum(sdf.pdem0)

        for (i,row_idx) in enumerate(row_idxs)
            pdem0 = sdf[i, :pdem0]::Float64
            s = pdem0/pdem0_total
            add_hourly_scaled!(demand_arr, shape, s, row_idx, yr_idx)
        end
    end
    return data
end
export add_demand!


# Table Summaries
################################################################################

"""
    summarize_demand_table() -> summary
"""
function summarize_demand_table()
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:bus_idx, Int64, NA, true, "The bus index of the load element"),
        (:pdem0, Float64, MWDemanded, true, "The baseline demanded power of the load element"),
        (:load_type, String, NA, false, "The type of load represented by this load element."),
    )
    return df
end
export summarize_demand_table

"""
    summarize_demand_shape_table() -> summary
"""
function summarize_demand_shape_table()
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load shape.  Leave blank to not filter by type."),
        (:year, String, Year, true, "The year to apply the demand profile to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this shape adjustment"),
        (:h_, Float64, Ratio, true, "Demand scaling factor of hour 1.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end
export summarize_demand_shape_table

"""
    summarize_demand_match_table() -> summary
"""
function summarize_demand_match_table()
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
export summarize_demand_match_table


"""
    summarize_demand_add_table() -> summary
"""
function summarize_demand_add_table()
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:area, String, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, NA, false, "The type of load represented for this load add.  Leave blank to not filter by type."),
        (:year, String, Year, true, "The year to apply the demand profile to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this addition"),
        (:h_, Float64, MWDemanded, true, "Amount of demanded power to add in hour _.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end
export summarize_demand_add_table
