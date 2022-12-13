"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`.

For more information about the data to be found in each of the files, see the following functions:
* [`load_bus_table!`](@ref)
* [`load_gen_table!`](@ref)
* [`load_branch_table!`](@ref)
* [`load_hours_table!`](@ref)
* [`load_af_table!`](@ref)
* [`load_demand_table!`](@ref)
"""
function load_data(config)
    data = OrderedDict{Symbol, Any}()

    data[:years] = config[:years]

    # Load in tables
    load_bus_table!(config, data)
    load_gen_table!(config, data)
    load_branch_table!(config, data)
    load_hours_table!(config, data)
    load_af_table!(config, data)
    load_demand_table!(config, data)

    return data
end

"""
    load_gen_table!(config, data)

Load the generator from the `config[:gen_file]`.  See [`summarize_gen_table()`](@ref).
"""
function load_gen_table!(config, data)
    gen = load_table(config[:gen_file])
    force_table_types!(gen, :gen, summarize_gen_table())
    data[:gen] = gen
    return
end
export load_gen_table!

"""
    load_bus_table!(config, data)

Load the bus table from the `config[:bus_file]` into `data[:bus]`.  See [`summarize_bus_table()`](@ref).

Table representing all existing buses (also sometimes referred to as nodes or subs/substations) to be modeled.
"""
function load_bus_table!(config, data)
    bus = load_table(config[:bus_file])
    force_table_types!(bus, :bus, summarize_bus_table())
    bus.bus_idx = 1:nrow(bus)
    data[:bus] = bus
    return
end
export load_bus_table!

"""
    load_branch_table!(config, data)

Load the branch table from `config[:branch_file]` into `data[:branch]`.  See [`summarize_branch_table()`](@ref).
"""
function load_branch_table!(config, data)
    branch = load_table(config[:branch_file])
    force_table_types!(branch, :branch, summarize_branch_table())
    data[:branch] = branch
    return
end
export load_branch_table!

"""
    load_hours_table!(config, data)

Load the hours representation table from `config[:hours_file]` into `data[:hours]`.  See [`summarize_hours_table()`](@ref).

E4ST assumes that each year is broken up into a set of representative hours.  Each representative hour may have different parameters (i.e. load, availability factor, etc.) depending on the time of year, time of day, etc. Thus, we index many of the decision variables by representative hour.  For example, the variable for power generated (`pg`), is indexed by generator, year, and hour, meaning that for each generator, there is a different solved value of generation for each year in each representative hour.  The hours can contain any number of representative hours, but the number of hours spent at each representative hour (the `hours` column) generally should sum to 8760 (the number of hours in a year).
"""
function load_hours_table!(config, data)
    hours = load_table(config[:hours_file])
    force_table_types!(hours, :rep_time, summarize_hours_table())
    if sum(hours.hours) != 8760
        s = sum(hours.hours)
        sf = 8760/s
        @warn "hours column of hours table sums to $s, scaling by $sf to reach 8760 hours per year"
        hours.hours .*= sf
    end
    data[:hours] = hours
    return
end
export load_hours_table!

@doc raw"""
    load_af_table!(config, data)

Load the hourly availability factors from `config[:af_file]` into `data[:af_table]`, if provided, and populates the `af` column of the `gen_table`.  

Updates the generator table with the availability factors provided.  By default assigns an availability factor of `1.0` for every generator.  See [`summarize_af_table()`](@ref).

Often, generators are unable to generate energy at their nameplate capacity over the course of any given representative hour.  This could depend on any number of things, such as how windy it is during a given representative hour, the time of year, the age of the generating unit, etc.  The ratio of available generation capacity to nameplate generation capacity is referred to as the availability factor (AF).

The availability factor table includes availability factors for groups of generators specified by any combination of area, genfuel, gentype, year, and hour.

```math
P_{G_{g,h,y}} \leq f_{\text{avail}_{g,h,y}} \cdot P_{C{g,y}} \qquad \forall \{g \in \text{generators}, h \in \text{hours}, y \in \text{years} \}
```
"""
function load_af_table!(config, data)
    # Fill in gen table with default af of 1.0 for every hour
    gens = get_gen_table(data)
    default_af = ByNothing(1.0)
    default_hourly_af = fill(1.0, get_num_hours(data))
    gens.af = Container[default_af for _ in 1:nrow(gens)]
    
    # Return if there is no af_file
    if ~haskey(config, :af_file) 
        return
    end

    # Load in the af file
    df = load_table(config[:af_file])
    force_table_types!(df, :af, summarize_af_table())
    force_table_types!(df, :af, ("h$n"=>Float64 for n in 2:get_num_hours(data))...)

    data[:af] = df

    # Pull the availability factors in as a matrix
    hr_idx = findfirst(s->s=="h1",names(df))
    af_mat = Matrix(df[:, hr_idx:end])
    if size(af_mat,2) != get_num_hours(data)
        error("The number of representative hours given in :af_file=$(config[:af_file])  ($(size(af_mat,2))) is different than the hours in the time representation ($(get_num_hours(data))).")
    end

    all_years = get_years(data)
    nyr = get_num_years(data)

    for i = 1:nrow(df)
        row = df[i, :]
        if get(row, :status, true) == false
            continue
        end

        if isempty(row.year)
            yr_idx = (:)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue
        end
        
        gens = get_gen_table(data)

        isempty(gens) && continue

        # Add the area-subarea pair to the condition
        if ~isempty(row.area) && ~isempty(row.subarea)
            area = row.area
            subarea = row.subarea
            gens = filter(gen->get_gen_subarea(data, gen, area)==subarea, gens, view=true)
        end

        isempty(gens) && continue

        # Add the genfuel to the condition
        if ~isempty(row.genfuel)
            genfuel = row.genfuel
            gens = filter(:genfuel=>==(genfuel), gens, view=true)
        end

        isempty(gens) && continue

        # Add the gentype to the condition
        if ~isempty(row.gentype)
            gentype = row.gentype
            gens = filter(:gentype=>==(gentype), gens, view=true)
        end

        isempty(gens) && continue
        
        af = [row[i_hr] for i_hr in hr_idx:ncol(df)]
        foreach(eachrow(gens)) do gen
            gen.af = set_hourly(gen.af, af, yr_idx; default=default_hourly_af, nyr)
        end
    end
    return data
end
export load_af_table!

"""
    load_demand_table!(config, data)

Loads the `demand_table` from `config[:demand_file]` into `data[:demand_table]`.

The `demand_table` lets you specify a base demanded power for arbitrary buses.  Buses may have multiple demand elements (for example, a commercial demand, etc.).  See also [`summarize_demand_table`](@ref)

Also calls the following:
* [`shape_demand!(config, data)`](@ref) - scales hourly demanded power by an hourly demand profile by arbitrary region
* [`match_demand!(config, data)`](@ref) - matches annual demanded energy by arbitrary region
"""
function load_demand_table!(config, data)
    # load in the table and force its types
    demand = load_table(config[:demand_file])
    force_table_types!(demand, :demand, summarize_demand_table())

    ar = [demand.pd[i] for i in 1:nrow(demand), j in 1:get_num_years(data), k in 1:get_num_hours(data)] # ndemand * nyr * nhr
    data[:demand_table] = demand
    data[:demand_array] = ar

    # Grab views of the demand for the pd column of the bus table
    demand.pd = map(i->view(ar, i, :, :), 1:nrow(demand))

    bus = get_bus_table(data)
    bus.pd = [DemandContainer() for _ in 1:nrow(bus)]

    for row in eachrow(demand)
        bus_idx = row.bus_idx::Int64
        c = bus[bus_idx, :pd]
        _add_view!(c, row.pd)
    end

    # Modify the demand by shaping, matching, and adding
    haskey(config, :demand_shape_file) && shape_demand!(config, data)
    haskey(config, :demand_match_file) && match_demand!(config, data)
    haskey(config, :demand_add_file)   && add_demand!(config, data)
    return nothing
end  
export load_demand_table!


# Helper Functions
################################################################################

"""
    load_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function load_table(filename::String)
    CSV.read(filename, DataFrame, missingstring="NA")
end
export load_table

"""
    force_table_types!(df::DataFrame, name, pairs...)

Forces `df` to have columns associated with column=>Type `pairs`.  The table's `name` is included for descriptive errors.
"""
function force_table_types!(df::DataFrame, name, pairs...; optional=false)
    for (col, T) in pairs
        if ~hasproperty(df, col)
            optional ? continue : error(":$name table missing column :$col")
        end
        ET = eltype(df[!,col])
        ET <: T && continue
        @show T, ET
        hasmethod(T, Tuple{ET}) || error("Column $name[$col] cannot be forced into type $T")
        df[!, col] = T.(df[!,col])
    end
end

function force_table_types!(df::DataFrame, name, summary::DataFrame; kwargs...) 
    for row in eachrow(summary)
        col = row["Column Name"]
        req = row["Required"]
        T = row["Data Type"]
        if ~hasproperty(df, col)
            req || continue
            error(":$name table missing column :$col")
        end
        ET = eltype(df[!,col])
        if ~(ET <: T)
            hasmethod(T, Tuple{ET}) || error("Column $name[$col] cannot be forced into type $T")
            df[!, col] = T.(df[!,col])
        end
    end
end

"""
    initialize_data!(config, data)

Initializes the data with any necessary Modifications in the config, calling `initialize!(mod, config, data)`
"""
function initialize_data!(config, data)
    # Initialize Modifications
    for (sym, mod) in getmods(config)
        initialize!(mod, config, data)
    end
    return nothing
end

"""
    shape_demand!(config, data)

Shapes the hourly demand to match profiles given in `config[:demand_shape_file]`.  See [`summarize_demand_shape_table`](@ref) for more details

Demanded power often changes on an hourly basis. The `demand_shape_table` allows the user to provide hourly demand profiles with which to scale the base demanded power for demand regions, types, or even specific demand elements.  Each row of the table represents a set of load elements, and the hourly demand profile with which to scale them.  For demand elements that fall in multiple sets, the hourly load will be scaled by each profile, in order.
"""
function shape_demand!(config, data)
    demand_shape_table = load_table(config[:demand_shape_file])
    bus_table = get_bus_table(data)
    force_table_types!(demand_shape_table, :demand_shape_table, summarize_demand_shape_table())
    force_table_types!(demand_shape_table, :demand_shape_table, ("h$n"=>Float64 for n in 2:get_num_hours(data))...)
    demand_table = data[:demand_table]
    demand_arr = data[:demand_array]
    
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

            shape = Float64[row[i_hr] for i_hr in hr_idx:length(row)]
            sdf = gdf[key]
            row_idx = getfield(sdf, :rows)
            _scale_hourly!(demand_arr, shape, row_idx, yr_idx)
            
            # Or use below to scale the views
            # _scale_hourly!(sdf.pd, shape, yr_idx)  
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
    demand_match_table = load_table(config[:demand_match_file])
    bus_table = get_bus_table(data)
    force_table_types!(demand_match_table, :demand_match_table, summarize_demand_match_table())
    force_table_types!(demand_match_table, :demand_match_table, (y=>Float64 for y in get_years(data))...)
    demand_table = data[:demand_table]
    demand_arr = data[:demand_array]

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
    grouping_variables = copy(all_areas)

    "load_type" in demand_table_names && push!(grouping_variables, "load_type")

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

        demand_table = get_demand_table(data, filters)
        
        isempty(demand_table) && continue

        row_idx = getfield(demand_table, :rows)

        for (yr_idx, match) in yr_idx_2_match
            _match_yearly!(demand_arr, match, row_idx, yr_idx, hr_weights)
        end
    end
    return data















    # Loop through each row in the demand_match_table
    for i in 1:nrow(demand_match_table)
        row = demand_match_table[i, :]

        get(row, :status, true) || continue
        yr_idx_2_match = Dict{Int64, Float64}()
        
        for (yr_idx, yr) in enumerate(get_years(data))
            isempty(row[yr]) && continue
            push!(yr_idx_2_match, yr_idx=>row[yr])
        end

        isempty(yr_idx_2_match) && continue
        
        # Pull out some data to use
        load_type = get(row, :load_type, "")
        area = get(row, :area, "")
        subarea = get(row, :subarea, "")

        # Loop through the sub-dataframes
        for key in eachindex(gdf)
            isempty(load_type) || load_type == key.load_type || continue
            isempty(area) || isempty(subarea) || subarea == key[area] || continue

            match = Float64[row[i_hr] for i_hr in hr_idx:length(row)]
            sdf = gdf[key]
            row_idx = getfield(sdf, :rows)

            for (yr_idx, match) in yr_idx_2_match
                _match_yearly!(demand_arr, match, row_idx, yr_idx, hr_weights)
            end
        end
    end
end
export match_demand!


"""
    _scale_hourly!(demand_arr, shape, row_idx, yr_idx)
    
Scales the hourly demand in `demand_arr` by `shape` for `row_idx` and `yr_idx`.
"""
function _scale_hourly!(demand_arr, shape, row_idxs, yr_idxs)
    foreach(yr_idx->_scale_hourly!(demand_arr, shape, row_idxs, yr_idx), yr_idxs)
end
function _scale_hourly!(demand_arr, shape, row_idxs, yr_idx::Int64)
    foreach(row_idx->_scale_hourly!(demand_arr, shape, row_idx, yr_idx), row_idxs)
end
function _scale_hourly!(demand_arr, shape, row_idx::Int64, yr_idx::Int64)
    demand_arr[row_idx, yr_idx, :] .*= shape
end


function _scale_hourly!(pds::AbstractArray{<:AbstractArray}, shape, yr_idxs)
    foreach(pd->_scale_hourly!(pd, shape, yr_idxs), pds)
end
function _scale_hourly!(pd::SubArray{Float64}, shape, yr_idxs)
    foreach(yr_idx->_scale_hourly!(pd, shape, yr_idx), yr_idxs)
end
function _scale_hourly!(pd::SubArray{Float64}, shape, yr_idx::Int64)
    pd[yr_idx, :] .*= shape
end

"""
    _match_yearly!(demand_arr, match, row_idxs, yr_idx, hr_weights)

Match the yearly demand represented by `demand_arr[row_idxs, yr_idx, :]` to `match`, with hourly weights `hr_weights`.
"""
function _match_yearly!(demand_arr::Array{Float64, 3}, match::Float64, row_idxs, yr_idx::Int64, hr_weights)
    # Select the portion of the demand_arr to match
    _match_yearly!(view(demand_arr, row_idxs, yr_idx, :), match, hr_weights)
end
function _match_yearly!(demand_mat::SubArray{Float64, 2}, match::Float64, hr_weights)
    # The demand_mat is now a 2d matrix indexed by [row_idx, hr_idx]
    s = _sum_product(demand_mat, hr_weights)
    scale_factor = match / s
    demand_mat .*= scale_factor
end

"""
    _sum_product(M, v) -> s

Computes the sum of M*v
"""
function _sum_product(M::AbstractMatrix, v::AbstractVector)
    @inbounds sum(M[row_idx, hr_idx]*v[hr_idx] for row_idx in 1:size(M,1), hr_idx in 1:size(M,2))
end

"""
    summarize_gen_table() -> summary
"""
function summarize_gen_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[],  "Required"=>Bool[],"Description"=>String[])
    push!(df, 
        (:bus_idx, Int64, "n/a", true, "The index of the `bus` table that the generator corresponds to"),
        (:status, Bool, "n/a", false, "Whether or not the generator is in service"),
        (:genfuel, String, "n/a", true, "The fuel type that the generator uses"),
        (:gentype, String, "n/a", true, "The generation technology type that the generator uses"),
        (:pcap_min, Float64, "MW", true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, "MW", true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, "\$/MWh", true, "Variable operation and maintenance cost per MWh of generation"),
        (:fom, Float64, "\$/MW", true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, "\$/MW", false, "Hourly capital expenditures for a MW of generation capacity"),
    )
    return df
end
export summarize_gen_table


"""
    summarize_bus_table() -> summary
"""
function summarize_bus_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:ref_bus, Bool, "n/a", true, "Whether or not the bus is a reference bus.  There should be a single reference bus for each island."),
    )
    return df
end
export summarize_bus_table

"""
    summarize_branch_table() -> summary
"""
function summarize_branch_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:f_bus_idx, Int64, "n/a", true, "The index of the `bus` table that the branch originates **f**rom"),
        (:t_bus_idx, Int64, "n/a", true, "The index of the `bus` table that the branch goes **t**o"),
        (:status, Bool, "n/a", false, "Whether or not the branch is in service"),
        (:x, Float64, "p.u.", true, "Per-unit reactance of the line (resistance assumed to be 0 for DC-OPF)"),
        (:pf_max, Float64, "MW", true, "Maximum power flowing through the branch")
    )
    return df
end
export summarize_branch_table

"""
    summarize_hours_table() -> summary
"""
function summarize_hours_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:hours, Float64, "hours", true, "The number of hours spent in each representative hour over the course of a year (must sum to 8760)"),
    )
    return df
end
export summarize_hours_table

"""
    summarize_af_table() -> summary
"""
function summarize_af_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:area, String, "n/a", true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, "n/a", true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:genfuel, String, "n/a", true, "The fuel type that the generator uses. Leave blank to not filter by genfuel."),
        (:gentype, String, "n/a", true, "The generation technology type that the generator uses. Leave blank to not filter by gentype."),
        (:year, String, "year", true, "The year to apply the AF's to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, "n/a", false, "Whether or not to use this AF adjustment"),
        (:h1, Float64, "ratio", true, "Availability factor of hour 1.  Include 1 column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end
export summarize_af_table

"""
    summarize_demand_table() -> summary
"""
function summarize_demand_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:bus_idx, Int64, "MW", true, "The demanded power of the load element"),
        (:pd, Float64, "MW", true, "The baseline demanded power of the load element"),
        (:load_type, String, "n/a", false, "The type of load represented by this load element."),
    )
    return df
end
export summarize_demand_table

"""
    summarize_demand_shape_table() -> summary
"""
function summarize_demand_shape_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:area, String, "n/a", true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, "n/a", true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, "n/a", false, "The type of load represented for this load shape."),
        (:year, String, "year", true, "The year to apply the demand profile to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, "n/a", false, "Whether or not to use this AF adjustment"),
        (:h1, Float64, "ratio", true, "Demand scaling factor of hour 1.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end
export summarize_demand_shape_table

"""
    summarize_demand_match_table() -> summary
"""
function summarize_demand_match_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:area, String, "n/a", true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, String, "n/a", true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:load_type, String, "n/a", false, "The type of load represented for this load shape."),
        (:status, Bool, "n/a", false, "Whether or not to use this AF adjustment"),
        (:y2020, Float64, "MWh", false, "The annual demanded energy to match for the weighted demand of all load elements in the loads specified.  Include 1 column for each year being simulated.  I.e. \"y2030\", \"y2035\", ... To not match a specific year, make it -Inf"),
    )
    return df
end
export summarize_demand_match_table

# Accessor Functions
################################################################################

"""
    get_gen_table(data)

Returns gen data table
"""
function get_gen_table(data) 
    return data[:gen]::DataFrame
end

"""
    get_branch_table(data)

Returns table of the transmission lines (branches) from data. 
"""
function get_branch_table(data) 
    return data[:branch]::DataFrame
end

"""
    get_bus_table(data)

Returns the bus data table
"""
function get_bus_table(data)
    data[:bus]::DataFrame
end

"""
    get_hours_table(data)

Returns the representative hours data table
"""
function get_hours_table(data)
    data[:hours]::DataFrame
end

"""
    get_demand_table(data)

Returns the demand table
"""
function get_demand_table(data)
    return data[:demand_table]::DataFrame
end
function get_demand_table(data, args...)
    return filter_view_table(get_demand_table(data), args...)
end
export get_demand_table

"""
    get_demand_array(data)

Returns the demand array, a 3d array of demand indexed by [demand_idx, yr_idx, hr_idx]
"""
function get_demand_array(data)
    return data[:demand_array]::Array{Float64,3}
end
export get_demand_array

"""
    get_af_table(data)

Returns the availiability factor table
"""
function get_af_table(data)
    return data[:af_table]::DataFrame
end
export get_af_table



"""
    get_generator(data, gen_idx) -> row

Returns the row of the gen table corresponding to `gen_idx`
"""
function get_generator(data, gen_idx)
    return get_gen_table(data)[gen_idx,:]
end

"""
    get_bus(data, bus_idx) -> row

Returns the row of the bus table corresponding to `bus_idx`
"""
function get_bus(data, bus_idx)
    return get_bus_table(data)[bus_idx,:]
end

"""
    get_branch(data, branch_idx) -> row

Returns the row of the branch table corresponding to `branch_idx`
"""
function get_branch(data, branch_idx)
    return get_branch_table(data)[branch_idx,:]
end

"""
    get_bus_from_generator_idx(data, gen_idx) -> bus

Returns the bus associated with `gen_idx`
"""
function get_bus_from_generator_idx(data, gen_idx)
    return get_bus(data, get_generator(data, gen_idx).bus_idx)
end

export get_gen_table, get_bus_table, get_branch_table, get_hours_table
export get_generator, get_bus, get_branch
export get_bus_from_generator_idx

"""
    get_af(data, gen_idx, year_idx, hour_idx) -> af

Retrieves the availability factor for a generator at a year and a time.
"""
function get_af(data, gen_idx, year_idx, hour_idx)
    return get_gen_value(data, :af, gen_idx, year_idx, hour_idx)
end

export get_af

"""
    get_pd(data, bus_idx, year_idx, hour_idx) -> pd

Retrieves the demanded power for a bus at a year and a time.
"""
function get_pd(data, bus_idx::Int64, year_idx::Int64, hour_idx::Int64)
    return get_bus_value(data, :pd, bus_idx, year_idx, hour_idx)
end
export get_pd


function get_ed(data, bus_idx::Int64, year_idx::Int64, hour_idx::Int64)
    return get_hour_weight(data, hour_idx) * get_bus_value(data, :pd, bus_idx, year_idx, hour_idx)
end

function get_ed_demand(data, demand_idxs::AbstractVector{Int64}, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, demand_idxs, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end
function get_ed_demand(data, ::Colon, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, :, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end

function get_ed_demand(data, pairs, year_idx::Int64, hour_idxs)
    demand_table = get_demand_table(data, pairs...)
    return get_ed_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end

function get_ed_demand(data, pair::Pair, year_idx::Int64, hour_idxs)
    demand_table = get_demand_table(data, pair)
    return get_ed_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end
function get_ed_demand(data, demand_idxs, y::String, hr_idx)
    year_idx = findfirst(==(y), get_years(data))
    return get_ed_demand(data, demand_idxs, year_idx, hr_idx)
end
export get_ed, get_ed_demand

"""
    get_gen_value(data, var::Symbol, gen_idx, year_idx, hour_idx) -> val

Retrieve the `var` value for generator `gen_idx` in year `year_idx` at hour `hour_idx`
"""
function get_gen_value(data, name, gen_idx, year_idx, hour_idx)
    gen_table = get_gen_table(data)
    c = gen_table[gen_idx, name]
    return c[year_idx, hour_idx]::Float64
end
export get_gen_value

"""
    get_bus_value(data, var::Symbol, bus_idx, year_idx, hour_idx) -> val

Retrieve the `var` value for bus `bus_idx` in year `year_idx` at hour `hour_idx`
"""
function get_bus_value(data, name, bus_idx, year_idx, hour_idx)
    bus_table = get_bus_table(data)
    c = bus_table[bus_idx, name]
    return c[year_idx, hour_idx]::Float64
end
export get_bus_value

"""
    get_gen_subarea(data, gen_idx::Int64, area::String) -> subarea

    get_gen_subarea(data, gen, area) -> subarea

Retrieves the `subarea` of the generator from the `area`
"""
function get_gen_subarea(data, gen_idx::Int64, area::String)
    gens = get_gen_table(data)
    bus = get_bus_table(data)
    return bus[gens[gen_idx, :bus_idx], area]
end
function get_gen_subarea(data, gen::DataFrameRow, area::String)
    bus = get_bus_table(data)
    return bus[gen.bus_idx, area]
end
export get_gen_subarea


"""
    get_num_hours(data) -> nhr

Returns the number of representative hours in a year
"""
function get_num_hours(data)
    return nrow(get_hours_table(data))
end

"""
    get_hour_weights(data) -> weights

    get_hour_weights(data, hour_idxs) -> weights (view)

Returns the number of hours in a year spent at each representative hour
""" 
function get_hour_weights(data)
    hours_table = get_hours_table(data)
    return hours_table.hours
end
function get_hour_weights(data, hour_idxs)
    return view(get_hour_weights(data), hour_idxs)
end
function get_hour_weights(data, ::Colon)
    return get_hour_weights(data)
end

"""
    get_hour_weight(data, hour_idx)

Returns the number of hours in a year spent at the `hour_idx` representative hour
"""
function get_hour_weight(data, hour_idx::Int64)
    return get_hour_weights(data)[hour_idx, :hours]
end
export get_num_hours, get_hour_weights, get_hour_weight

"""
    get_years(data) -> years

Returns the vector of years as strings (i.e. "y2022") that are being represented in the sim.
"""
function get_years(data)
    return data[:years]::Vector{String}
end

"""
    get_num_years(data) -> nyr

Returns the number of years in this simulation
"""
function get_num_years(data)
    return length(get_years(data))
end
export get_num_years, get_years


"""
    filter_view(table::DataFrame, pairs...) -> v::SubDataFrame

    filter_view(table::DataFrame, pairs...) -> v::SubDataFrame

Return a `SubDataFrame` containing each row of `table` such that for each `(field,value)` pair in `pairs`, `row.field==value`.
"""
function filter_view_table(table::DataFrame, pairs::Pair...)
    v = view(table,:,:)
    for (field, value) in pairs
        field isa AbstractString && isempty(field) && continue
        isempty(value) && continue
        v = filter(field=>==(value), v, view=true)
        isempty(v) && break
    end
    return v
end
function filter_view_table(table::DataFrame, pairs)
    v = view(table,:,:)
    for (field, value) in pairs
        field isa AbstractString && isempty(field) && continue
        isempty(value) && continue
        v = filter(field=>==(value), v, view=true)
        isempty(v) && break
    end
    return v
end

# Containers
################################################################################

"""
    abstract type Container

Abstract type for containers that can be indexed by year and time.
"""
abstract type Container end

mutable struct ByNothing <: Container 
    v::Float64
end
struct ByYear <: Container
    v::Vector{Float64}
end
struct ByHour <: Container
    v::Vector{Float64}
end
struct ByYearAndHour <: Container
    v::Vector{Vector{Float64}}
end

"""
    Base.getindex(c::Container, year_idx, hour_idx) -> val::Float64

Retrieve the value from `c` at `year_idx` and `hour_idx`
"""
function Base.getindex(c::ByNothing, year_idx, hour_idx)
    c.v::Float64
end
function Base.getindex(c::ByYear, year_idx, hour_idx)
    c.v[year_idx]::Float64
end
function Base.getindex(c::ByHour, year_idx, hour_idx)
    c.v[hour_idx]::Float64
end
function Base.getindex(c::ByYearAndHour, year_idx, hour_idx)
    c.v[year_idx][hour_idx]::Float64
end
function Base.getindex(n::Number, year_idx::Int64, hour_idx::Int64)
    return n
end

"""
    set_hourly(c::Container, v::Vector{Float64}, yr_idx; default, nyr)

Sets the hourly values for `c` (creating a new Container of a different type as needed) for `yr_idx` to be `v`.

If `yr_idx::Colon`, sets the hourly values for all years to be `v`.

# keyword arguments
* `default` - the default hourly values for years not specified, if they aren't already set.
* `nyr` - the total number of years.
"""
function set_hourly(c::ByNothing, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByNothing, v, yr_idx; default=nothing, nyr=nothing)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:); default, kwargs...)
    end
    @assert default !== nothing error("Attempting to set hourly values for year index $yr_idx, but no default provided!")
    vv = fill(default, nyr)
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByYear, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByYear, v, yr_idx; kwargs...)
    # Check to see if all the years are represented by yr_idx
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:); default, kwargs...)
    end

    # Set the default hourly values to be the original values
    vv = map(c.v) do yr_val
        fill(yr_val, nyr)
    end
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByHour, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByHour, v, yr_idx; nyr=nothing, kwargs...)
    @assert nyr !== nothing error("Attempting to set hourly values for year index $yr_idx, but no nyr provided!")
    if all(in(yr_idx), 1:nyr)
        return set_hourly(c, v, (:); default, kwargs...)
    end
    vv = fill(v, nyr)
    foreach(i->(vv[i] = v), yr_idx)
    return ByYearAndHour(vv)
end

function set_hourly(c::ByYearAndHour, v, yr_idx::Colon; kwargs...)
    return ByHour(v)
end
function set_hourly(c::ByYearAndHour, v, yr_idx; kwargs...)
    if all(in(yr_idx), 1:length(c.v))
        return set_hourly(c, v, (:); default, kwargs...)
    end
    foreach(i->(c.v[i] = v), yr_idx)
    return c
end

"""
    DemandContainer()

Contains a vector of views of the demand_array, so that it is possible to access by 
"""
struct DemandContainer <: Container
    v::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
end

_add_view!(c::DemandContainer, v) = push!(c.v, v)

DemandContainer() = DemandContainer(SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}[])
function Base.getindex(c::DemandContainer, year_idx, hour_idx)
    isempty(c.v) && return 0.0
    return sum(vv->vv[year_idx, hour_idx], c.v)::Float64
end

function Base.show(io::IO, c::DemandContainer)
    isempty(c.v) && return print(io, "empty DemandContainer")
    l,m = size(c.v[1])
    n = length(c.v)
    print(io, "$n-element DemandContainer of $(l)×$m Matrix")
end

