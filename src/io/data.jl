"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`.

Calls the following functions:
* [`load_data_files!(config, data)`](@ref) - load in the data from files
* [`modify_raw_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the raw data before the data gets setup.
* [`setup_data!(config, data)`](@ref) - Sets up the data, modifying/adding to the tables as needed.
* [`modify_setup_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the setup data before the model is built.
"""
function load_data(config)
    log_header("LOADING DATA")
    data = OrderedDict{Symbol, Any}()
    data[:years] = config[:years]

    load_data_files!(config, data)
    modify_raw_data!(config, data)
    setup_data!(config, data)
    modify_setup_data!(config, data)

    return data
end

"""
    load_data_files!(config, data)

Loads in the data files presented in the `config`.  Calls the following functions:
* [`load_bus_table!`](@ref) - from `config[:bus_file] -> data[:bus]`
* [`load_branch_table!`](@ref) - from `config[:branch_file] -> data[:branch]`
* [`load_gen_table!`](@ref) - from `config[:gen_file] -> data[:gen]`
* [`load_hours_table!`](@ref) - from `config[:hours_file] -> data[:hours_table]`
* [`load_voll!`](@ref) - from `config[:voll] -> data[:voll]`
* [`load_af_table!`](@ref) - from `config[:af_file] -> data[:af_table]`
* [`load_demand_table!(config, data)`](@ref) - from `config[:demand_file] -> data[:demand_table]`
* [`load_demand_shape_table!(config, data)`](@ref)  - from `config[:demand_shape_file] -> data[:demand_shape_table]` (if `config[:demand_shape_file]` provided)
* [`load_demand_match_table!(config, data)`](@ref)  - from `config[:demand_match_file] -> data[:demand_match_table]` (if `config[:demand_match_file]` provided)
* [`load_demand_add_table!(config, data)`](@ref)  - from `config[:demand_add_file] -> data[:demand_add_table]` (if `config[:demand_add_file]` provided)
"""
function load_data_files!(config, data)
    load_bus_table!(config, data)
    load_branch_table!(config, data)
    load_gen_table!(config, data)
    load_hours_table!(config, data)
    load_voll!(config, data)
    load_af_table!(config, data)
    load_demand_table!(config, data)
    haskey(config, :demand_shape_file) && load_demand_shape_table!(config, data)
    haskey(config, :demand_match_file) && load_demand_match_table!(config, data)
    haskey(config, :demand_add_file) && load_demand_add_table!(config, data)
end
export load_data_files!

"""
    modify_raw_data!(config, data)

Allows [`Modification`](@ref)s to modify the raw data - calls [`modify_raw_data!(mod, config, data)`](@ref)
"""
function modify_raw_data!(config, data)    
    for (sym, mod) in getmods(config)
        modify_raw_data!(mod, config, data)
    end
    return nothing
end

"""
    modify_setup_data!(config, data)

Allows [`Modification`](@ref)s to modify the raw data - calls [`modify_setup_data!(mod, config, data)`](@ref)
"""
function modify_setup_data!(config, data)    
    for (sym, mod) in getmods(config)
        modify_setup_data!(mod, config, data)
    end
    return nothing
end

"""
    setup_data!(config, data)

Sets up the data, modifying, adding to, or combining the tables as needed.
"""
function setup_data!(config, data)
    setup_bus_table!(config, data)
    setup_branch_table!(config, data)
    setup_gen_table!(config, data)
    setup_hours_table!(config, data)
    setup_af!(config, data)
    setup_demand!(config, data)
end
export setup_data!


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
    setup_gen_table!(config, data)

Sets up the generator table.
"""
function setup_gen_table!(config, data)
end
export setup_gen_table!

"""
    load_bus_table!(config, data)

Load the bus table from the `config[:bus_file]` into `data[:bus]`.  See [`summarize_bus_table()`](@ref).

Table representing all existing buses (also sometimes referred to as nodes or subs/substations) to be modeled.
"""
function load_bus_table!(config, data)
    @info "Loading the bus table from:  $(config[:bus_file])"
    bus = load_table(config[:bus_file])
    force_table_types!(bus, :bus, summarize_bus_table())
    data[:bus] = bus
    return
end
export load_bus_table!

"""
    setup_bus_table!(config, data)

Sets up the bus table.  
* Makes a `:bus_idx` to track row numbers.
"""
function setup_bus_table!(config, data)
    bus = get_bus_table(data)
    bus.bus_idx = 1:nrow(bus)
    return
end
export setup_bus_table!

"""
    load_branch_table!(config, data)

Load the branch table from `config[:branch_file]` into `data[:branch]`.  See [`summarize_branch_table()`](@ref).
"""
function load_branch_table!(config, data)
    @info "Loading the branch table from:  $(config[:branch_file])"
    branch = load_table(config[:branch_file])
    force_table_types!(branch, :branch, summarize_branch_table())
    data[:branch] = branch
    return
end
export load_branch_table!

"""
    setup_branch_table!(config, data)

Sets up the branch table.
* Makes bus[:connected_branch_idxs] which contains a vector of the signed index of each branch leaving that bus. (`+` for `f_bus_idx`, `-` for `to_bus_idx`). 
"""
function setup_branch_table!(config, data)
    branch = get_branch_table(data)
    bus = get_bus_table(data)

    # Add connected branches, connected buses.
    bus.connected_branch_idxs = [Int64[] for _ in 1:nrow(bus)]
    for (br_idx, br) in enumerate(eachrow(branch))
        f_bus_idx = br.f_bus_idx::Int64
        t_bus_idx = br.t_bus_idx::Int64
        push!(bus[f_bus_idx, :connected_branch_idxs], br_idx)
        push!(bus[t_bus_idx, :connected_branch_idxs], -br_idx)
    end
    return
end
export setup_branch_table!

"""
    load_hours_table!(config, data)

Load the hours representation table from `config[:hours_file]` into `data[:hours]`.  See [`summarize_hours_table()`](@ref).

E4ST assumes that each year is broken up into a set of representative hours.  Each representative hour may have different parameters (i.e. load, availability factor, etc.) depending on the time of year, time of day, etc. Thus, we index many of the decision variables by representative hour.  For example, the variable for power generated (`pg`), is indexed by generator, year, and hour, meaning that for each generator, there is a different solved value of generation for each year in each representative hour.  The hours can contain any number of representative hours, but the number of hours spent at each representative hour (the `hours` column) generally should sum to 8760 (the number of hours in a year).
"""
function load_hours_table!(config, data)
    @info "Loading the hours table from:  $(config[:hours_file])"
    hours = load_table(config[:hours_file])
    force_table_types!(hours, :rep_time, summarize_hours_table())
    data[:hours] = hours
    return
end
export load_hours_table!

"""
    setup_hours_table!(config, data)

Doesn't do anything yet.
"""
function setup_hours_table!(config, data)
    return
end
export setup_hours_table!

@doc raw"""
    load_af_table!(config, data)

Load the hourly availability factors from `config[:af_file]` into `data[:af_table]`, if provided. 

See also [`summarize_af_table()`](@ref), [`setup_af!(config, data)`](@ref)
"""
function load_af_table!(config, data)
    # Return if there is no af_file
    if ~haskey(config, :af_file) 
        return
    end

    @info "Loading the availability factor table from:  $(config[:af_file])"

    # Load in the af file
    df = load_table(config[:af_file])
    force_table_types!(df, :af, summarize_af_table())
    force_table_types!(df, :af, ("h$n"=>Float64 for n in 2:get_num_hours(data))...)

    data[:af_table] = df

    return
end
export load_af_table!

@doc raw"""
    setup_af!(config, data)

Populates the `af` column of the `gen_table`.  

Updates the generator table with the availability factors provided.  By default assigns an availability factor of `1.0` for every generator.  See [`summarize_af_table()`](@ref).

Often, generators are unable to generate energy at their nameplate capacity over the course of any given representative hour.  This could depend on any number of things, such as how windy it is during a given representative hour, the time of year, the age of the generating unit, etc.  The ratio of available generation capacity to nameplate generation capacity is referred to as the availability factor (AF).

The availability factor table includes availability factors for groups of generators specified by any combination of area, genfuel, gentype, year, and hour.

```math
P_{G_{g,h,y}} \leq f_{\text{avail}_{g,h,y}} \cdot P_{C{g,y}} \qquad \forall \{g \in \text{generators}, h \in \text{hours}, y \in \text{years} \}
```
"""
function setup_af!(config, data)
    # Fill in gen table with default af of 1.0 for every hour
    gens = get_gen_table(data)
    default_af = ByNothing(1.0)
    default_hourly_af = fill(1.0, get_num_hours(data))
    gens.af = Container[default_af for _ in 1:nrow(gens)]
    
    # Return if there is no af_file
    if ~haskey(data, :af_table) 
        return
    end

    af_table = data[:af_table]

    hr_idx = findfirst(s->s=="h1",names(af_table))
    all_years = get_years(data)
    nyr = get_num_years(data)

    for i = 1:nrow(af_table)
        row = af_table[i, :]
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
        
        af = [row[i_hr] for i_hr in hr_idx:ncol(af_table)]
        foreach(eachrow(gens)) do gen
            gen.af = set_hourly(gen.af, af, yr_idx; default=default_hourly_af, nyr)
        end
    end
    return data
end
export setup_af!

"""
    load_voll!(config, data)

Return the marginal cost of load curtailment / VOLL as a variable in data
"""
function load_voll!(config, data)
    default_voll = 5000.0;
    haskey(config, :voll) ? data[:voll] = config[:voll] : data[:voll] = default_voll
    hasmethod(Float64, Tuple{typeof(data[:voll])}) || error("data[:voll] cannot be converted to a Float64")
    data[:voll] = Float64.(data[:voll]) 
end
export load_voll!

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
    scale_hourly!(demand_arr, shape, row_idx, yr_idx)
    
Scales the hourly demand in `demand_arr` by `shape` for `row_idx` and `yr_idx`.
"""
function scale_hourly!(demand_arr, shape, row_idxs, yr_idxs)
    for yr_idx in yr_idxs, row_idx in row_idxs
        scale_hourly!(demand_arr, shape, row_idx, yr_idx)
    end
    return nothing
end
function scale_hourly!(ars::AbstractArray{<:AbstractArray}, shape, yr_idxs)
    for ar in ars, yr_idx in yr_idxs
        scale_hourly!(ar, shape, yr_idx)
    end
    return nothing
end
function scale_hourly!(ar::AbstractArray{Float64}, shape, yr_idxs)
    for yr_idx in yr_idxs
        scale_hourly!(ar, shape, yr_idx)
    end
    return nothing
end
function scale_hourly!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, idxs::Int64...)
    view(ar, idxs..., :) .+= shape
    return nothing
end

"""
    add_hourly!(ar, shape, row_idx, yr_idx)

    add_hourly!(ar, shape, row_idxs, yr_idxs)
    
adds to the hourly demand in `ar` by `shape` for `row_idx` and `yr_idx`.
"""
function add_hourly!(ar, shape, row_idxs, yr_idxs; kwargs...)
    for yr_idx in yr_idxs, row_idx in row_idxs
        add_hourly!(ar, shape, row_idx, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ars::AbstractArray{<:AbstractArray}, shape, yr_idxs; kwargs...)
    for ar in ars, yr_idx in yr_idxs
        add_hourly!(ar, shape, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ar::AbstractArray{Float64}, shape, yr_idxs; kwargs...)
    for yr_idx in yr_idxs
        add_hourly!(ar, shape, yr_idx; kwargs...)
    end
    return nothing
end
function add_hourly!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, idxs::Int64...)
    view(ar, idxs..., :) .+= shape
    return nothing
end

"""
    add_hourly_scaled!(ar, v::AbstractVector{Float64}, s::Float64, idx1, idx2)

Adds `v.*s` to `ar[idx1, idx2, :]`, without allocating.
"""
function add_hourly_scaled!(ar::AbstractArray{Float64}, shape::AbstractVector{Float64}, s::Float64, idx1::Int64, idx2::Int64)
    view(ar, idx1, idx2, :) .+= shape .* s
    return nothing
end
function add_hourly_scaled!(ar, shape, s, idxs1, idxs2)
    for idx1 in idxs1, idx2 in idxs2
        add_hourly_scaled!(ar, shape, s, idx1, idx2)
    end
    return nothing
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



# Table Summaries
################################################################################

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
        (:pcap0, Float64, "MW", true, "Starting nameplate power generation capacity for the generator"),
        (:pcap_min, Float64, "MW", true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, "MW", true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, "\$/MWh", true, "Variable operation and maintenance cost per MWh of generation"),
        (:fuel_cost, Float64, "\$/MWh", false, "Fuel cost per MWh of generation"),
        (:fom, Float64, "\$/MW", true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, "\$/MW", false, "Hourly capital expenditures for a MW of generation capacity"),
        (:cf_min, Float64, "ratio", false, "The minimum operable ratio of power generation to capacity for the generator to operate.  Take care to ensure this is not above the hourly availability factor in any of the hours, or else the model may be infeasible."),
        (:cf_max, Float64, "ratio", false, "The maximum operable ratio of power generation to capacity for the generator to operate"),
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
        (:pflow_max, Float64, "MW", true, "Maximum power flowing through the branch")
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
    get_pdem(data, bus_idx, year_idx, hour_idx) -> pdem

Retrieves the demanded power for a bus at a year and a time.
"""
function get_pdem(data, gen_idx, year_idx, hour_idx)
    return get_bus_value(data, :pdem, gen_idx, year_idx, hour_idx)
end
export get_pdem

"""
    get_edem(data, bus_idx, year_idx, hour_idx) -> ed::Float64 (MWh)

    get_edem(data, bus_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

Retrieve the total energy demanded for a bus at a given year and hour(s).
"""
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idx::Int64)
    return get_hour_weight(data, hour_idx) * get_pdem(data, bus_idx, year_idx, hour_idx)
end
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idxs)
    return sum(get_hour_weight(data, hour_idx) * get_pdem(data, bus_idx, year_idx, hour_idx) for hour_idx in hour_idxs)
end
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idxs::Colon)
    hour_weights = get_hour_weights(data)
    return sum(hour_weights[hour_idx] * get_pdem(data, bus_idx, year_idx, hour_idx) for hour_idx in eachindex(hour_weights))
end

"""
    get_edem_demand(data, demand_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

    get_edem_demand(data, demand_idxs, year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

    get_edem_demand(data, pair(s), year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

Return the energy demanded by demand elements corresponding to `demand_idx` or `demand_idxs`, for `year_idx` and `hour_idx`.  Note `year_idx` can be the index or the year string (i.e. "y2030").

If pair(s) are given, filters the demand elements by pair.  i.e. pairs = ("country"=>"narnia", "load_type"=>"residential").
"""
function get_edem_demand(data, demand_idxs::AbstractVector{Int64}, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, demand_idxs, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end
function get_edem_demand(data, ::Colon, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, :, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end

function get_edem_demand(data, pairs, year_idx::Int64, hour_idxs)
    demand_table = get_demand_table(data, pairs...)
    return get_edem_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end

function get_edem_demand(data, pair::Pair, year_idx::Int64, hour_idxs)
    demand_table = get_demand_table(data, pair)
    return get_edem_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end
function get_edem_demand(data, demand_idxs, y::String, hr_idx)
    year_idx = findfirst(==(y), get_years(data))
    return get_edem_demand(data, demand_idxs, year_idx, hr_idx)
end
export get_edem, get_edem_demand

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
    get_branch_value(data, var::Symbol, branch_idx, year_idx, hour_idx) -> val

Retrieve the `var` value for bus `bus_idx` in year `year_idx` at hour `hour_idx`
"""
function get_branch_value(data, name, branch_idx, year_idx, hour_idx)
    branch_table = get_branch_table(data)
    c = branch_table[branch_idx, name]
    return c[year_idx, hour_idx]::Float64
end
export get_branch_value

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
function Base.getindex(c::ByYearAndHour, year_idx, hour_idx::Colon)
    c_arr = c.v[year_idx]
    return c_arr
end
function Base.getindex(n::Number, year_idx::Int64, hour_idx::Int64)
    return n
end
function Base.getindex(n::Number, year_idx::Int64, hour_idx::Colon)
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



## Moved from dcopf, will organize later

### System mapping helper functions

"""
    get_bus_gens(data, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, bus_idx) 
    gen = get_gen_table(data)
    return findall(x -> x == bus_idx, gen.bus_idx)
end
export get_bus_gens

"""
    get_ref_bus_idxs(data)

Returns reference bus ids
"""
function get_ref_bus_idxs(data) 
    bus = get_bus_table(data)
    return findall(bus.ref_bus)
end
export get_ref_bus_idxs

### Constraint info functions (change name)

"""
    get_pcap_min(data, gen_idx, year_idx)

Returns min capacity for a generator
"""
function get_pcap_min(data, gen_idx, year_idx) 
    return get_gen_value(data, :pcap_min, gen_idx, year_idx, :)
end
export get_pcap_min


"""
    get_pcap_max(data, model, gen_idx, year_idx)

Returns max capacity for a generator
"""
function get_pcap_max(data, gen_idx, year_idx) 
    return get_gen_value(data, :pcap_max, gen_idx, year_idx, :)
end
export get_pcap_max


""" 
    get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)

Returns max power flow on a branch at a given time. 
"""
function get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) 
    return get_branch_value(data, :pflow_max, branch_idx, year_idx, hour_idx)
end
export get_pflow_branch_max


### Misc
"""
    get_pdem_bus(data, bus_idx, year_idx, hour_idx)

Returns the demanded load at a bus at a time. Load served (pserv) can be less than demanded when load is curtailed. 
"""
function get_pdem_bus(data, bus_idx, year_idx, hour_idx) 
    return get_bus_value(data, :pdem, bus_idx, year_idx, hour_idx)
end
export get_pdem_bus

"""
    get_voll(data, bus_idx, year_idx, hour_idx)

Returns the value of lost load at given bus and time
"""
function get_voll(data, bus_idx, year_idx, hour_idx) 
    # If we want voll to be by bus_idx this could be modified and load_voll() will need to be changed
    return data[:voll]
end
export get_voll


