"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`
"""
function load_data(config)
    data = OrderedDict{Symbol, Any}()

    data[:years] = config[:years]

    # Load in tables
    load_bus_table!(config, data)
    load_gen_table!(config, data)
    load_branch_table!(config, data)
    load_hours_table!(config, data)
    load_af!(config, data)
    load_voll!(config, data)

    return data
end

"""
    load_gen_table!(config, data)

Load the generator from the `:gen_file` specified in the `config`
"""
function load_gen_table!(config, data)
    gen = load_table(config[:gen_file])
    force_table_types!(gen, :gen,
        :bus_idx=>Int64,
        :status=>Bool,
        :genfuel=>String,
        :gentype=>String,
        :pcap0=>Float64,
        :pcap_min=>Float64,
        :pcap_max=>Float64,
        :fom=>Float64,
        :vom=>Float64,
    )
    # force_table_types!(gen, :gen,
    #     :capex=>Float64,
    #     optional=true
    # )
    data[:gen] = gen
    return
end

"""
    load_bus_table!(config, data)

Load the bus table from the `:bus_file` specified in the `config`
"""
function load_bus_table!(config, data)
    bus = load_table(config[:bus_file])
    force_table_types!(bus, :bus,
        :ref_bus=>Bool,
        :pd=>Float64,
    )
    # force_table_types!(bus, :bus,
    #     :capex=>Float64,
    #     optional=true
    # )
    data[:bus] = bus
    return
end

"""
    load_branch_table!(config, data)

Load the branch table from the `:branch_file` specified in the `config`
"""
function load_branch_table!(config, data)
    branch = load_table(config[:branch_file])
    force_table_types!(branch, :branch,
        :f_bus_idx=>Int64,
        :t_bus_idx=>Int64,
        :status=>Bool,
        :x=>Float64,
        :pf_max=>Float64,
    )
    # force_table_types!(branch, :branch,
    #     :capex=>Float64,
    #     optional=true
    # )
    data[:branch] = branch
    return
end

"""
    load_hours_table!(config, data) -> rep_time

Load the representative time `rep_time` from the `:hours_file` specified in the `config`
"""
function load_hours_table!(config, data)
    hours = load_table(config[:hours_file])
    force_table_types!(hours, :rep_time,
        :hours=>Float64,
        # :day=>Int64,
    )
    data[:hours] = hours
    return
end

"""
    load_af!(config, data)

Load the hourly availability factors, pulling them in from file, as needed.
"""
function load_af!(config, data)
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
    force_table_types!(df, :af,
        :area=>String,
        :subarea=>String,
        :genfuel=>String,
        :gentype=>String,
        # :joint=>Int64,
        :status=>Bool,
        :year=>String,
        ("h$n"=>Float64 for n in 1:get_num_hours(data))...
    )

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
        if row.status==false
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
    load_voll!(config, data)

Return the marginal cost of load curtailment / VOLL as a variable in data
"""
function load_voll!(config, data)
    default_voll = 5000.0;
    haskey(config, :voll) ? data[:voll] = config[:voll] : data[:voll] = default_voll
    hasmethod(Float64, Tuple{typeof(data[:voll])}) || error("data[:voll] cannot be converted to a Float64")
    Float64.(data[:voll]) 
end


# Helper Functions
################################################################################

"""
    load_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function load_table(filename::String)
    CSV.File(filename, missingstring="NA") |> DataFrame
end
export year2int

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


## Moved from dcopf, will organize later

### System mapping helper functions

"""
    get_branch_idx(data, f_bus_idx, t_bus_idx)

Returns a vector with the branch idx and the f_bus and t_bus indices for that branch (could be flipped from inputs). 
"""
function get_branch_idx(data, f_bus_idx, t_bus_idx) 
    branch = get_branch_table(data)
    for i in 1:nrow(branch)
        if branch.f_bus_idx == f_bus_idx && branch.t_bus_idx == t_bus_idx
            return i
        elseif branch.f_bus_idx == t_bus_idx && branch.t_bus_idx == f_bus_idx
            return -i
        else
            return 0
        end
    end
end
export get_branch_idx

"""
    get_connected_buses(data, bus_idx)

Returns vector of idxs for all buses connected to the specified buses. Returns whether it is the f_bus or the t_bus
"""
function get_connected_buses(data, bus_idx) 
    branch = get_branch_table(data)
    connected_bus_idxs = []
    for r in eachrow(branch)
        if r.f_bus_idx == bus_idx push!(connected_bus_idxs, r.t_bus_idx) end
        if r.t_bus_idx == bus_idx push!(connected_bus_idxs, r.f_bus_idx) end
    end
    unique!(connected_bus_idxs) #removes duplicates
    return connected_bus_idxs
end
export get_connected_buses

"""
    get_bus_gens(data, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, bus_idx) 
    gen = get_gen_table(data)
    findall(x -> x == bus_idx, gen.bus_idx)
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
    get_pf_branch_max(data, branch_idx, year_idx, hour_idx)

Returns max power flow on a branch at a given time. 
"""
function get_pf_branch_max(data, branch_idx, year_idx, hour_idx) 
    return get_branch_value(data, :pf_max, branch_idx, year_idx, hour_idx)
end
export get_pf_branch_max


### Misc
"""
    get_dl(data, bus_idx, year_idx, hour_idx)

Returns the demanded load at a bus at a time. Load served (pl) can be less than demanded when load is curtailed. 
"""
function get_dl(data, bus_idx, year_idx, hour_idx) 
    return get_bus_value(data, :pd, bus_idx, year_idx, hour_idx)
end
export get_dl

"""
    get_voll(data, bus_idx, year_idx, hour_idx)

Returns the value of lost load at given bus and time
"""
function get_voll(data, bus_idx, year_idx, hour_idx) 
    # If we want voll to be by bus_idx this could be modified and load_voll() will need to be changed
    return data[:voll]
end
export get_voll