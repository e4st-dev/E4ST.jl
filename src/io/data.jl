"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`.

For more information about the data to be found in each of the files, see the following functions:
* [`summarize_bus_table()`](@ref)
* [`summarize_branch_table()`](@ref)
* [`summarize_gen_table()`](@ref)
* [`summarize_hours_table()`](@ref)
* [`summarize_af_table()`](@ref)
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

Load the generator from the `:gen_file` specified in the `config`
"""
function load_gen_table!(config, data)
    gen = load_table(config[:gen_file])
    force_table_types!(gen, :gen, summarize_gen_table())
    data[:gen] = gen
    return
end

"""
    load_bus_table!(config, data)

Load the bus table from the `:bus_file` specified in the `config`
"""
function load_bus_table!(config, data)
    bus = load_table(config[:bus_file])
    force_table_types!(bus, :bus, summarize_bus_table())
    data[:bus] = bus
    return
end

"""
    load_branch_table!(config, data)

Load the branch table from the `:branch_file` specified in the `config`
"""
function load_branch_table!(config, data)
    branch = load_table(config[:branch_file])
    force_table_types!(branch, :branch, summarize_branch_table())
    data[:branch] = branch
    return
end

"""
    load_hours_table!(config, data) -> rep_time

Load the representative time `rep_time` from the `:hours_file` specified in the `config`
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

"""
    load_af_table!(config, data)

Load the hourly availability factors, pulling them in from file, as needed.
"""
function load_af_table!(config, data)
    # Fill in gen table with default af of 1.0 for every hour
    gens = get_gen_table(data)
    default_af = ByNothing(1.0)
    default_hourly_af = fill(1.0, get_num_hours(data))
    gens.af = Container[default_af for _ in 1:nrow(gens)]
    
    # TODO: Add in yearly AF adjustments
    # default_yearly_af = ones(get_num_years(data))
    # gens.af_yearly = fill(default_yearly_af, nrow(gens))

    # Return if there is no af_file
    if ~haskey(config, :af_file) 
        @warn "No field :af_file in config"
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

"""
    load_demand_table!(config, data)
"""
function load_demand_table!(config, data)
    # load in the table and force its types
    demand = load_table(config[:demand_file])
    force_table_types!(demand, :demand, summarize_demand_table())

    ar = [demand.pd[i] for i in 1:nrow(demand), j in 1:get_num_years(data), k in 1:get_num_hours(data)] # ndemand * nyr * nhr
    data[:demand_table] = demand
    data[:demand_array] = ar

    # Modify the demand by shaping, matching, and adding
    haskey(config, :demand_shape_file) && shape_demand!(config, data)
    haskey(config, :demand_match_file) && match_demand!(config, data)
    haskey(config, :demand_add_file)   && add_demand!(config, data)

    # Grab views of the demand for the pd column of the bus table
    demand.pd = map(i->view(ar, i, :, :), 1:nrow(demand))

    bus = get_bus_table(data)
    bus.pd = [DemandContainer() for _ in 1:nrow(bus)]

    for row in eachrow(demand)
        bus_idx = row.bus_idx::Int64
        c = bus[bus_idx, :pd]
        _add_view!(c, row.pd)
    end
end  


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
        if ~(ET <: T)
            hasmethod(T, Tuple{ET}) || error("Column $name[$col] cannot be forced into type $T")
            df[!, col] = T.(df[!,col])
        end
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
end


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

function summarize_bus_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:ref_bus, Bool, "n/a", true, "Whether or not the bus is a reference bus.  There should be a single reference bus for each island."),
    )
    return df
end
export summarize_bus_table

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

function summarize_hours_table()
    df = DataFrame("Column Name"=>Symbol[], "Data Type"=>Type[], "Unit"=>String[], "Required"=>Bool[], "Description"=>String[])
    push!(df, 
        (:hours, Float64, "hours", true, "The number of hours spent in each representative hour over the course of a year (must sum to 8760)"),
    )
    return df
end
export summarize_hours_table


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
function get_pd(data, gen_idx, year_idx, hour_idx)
    return get_bus_value(data, :pd, gen_idx, year_idx, hour_idx)
end
export get_pd

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

Returns the number of hours in a year spent at each representative hour
""" 
function get_hour_weights(data)
    hours_table = get_hours_table(data)
    return hours_table.hours
end

"""
    get_hour_weight(data, hour_idx)

Returns the number of hours in a year spent at the `hour_idx` representative hour
"""
function get_hour_weight(data, hour_idx)
    return get_hours_table(data)[hour_idx, :hours]
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
function Base.getindex(n::Number, year_idx, hour_idx)
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
