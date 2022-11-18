"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`
"""
function load_data(config)
    data = OrderedDict()

    # Load in tables
    load_gen_table!(config, data)
    load_bus_table!(config, data)
    load_branch_table!(config, data)
    load_time!(config, data)
    load_af!(config, data)

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
    load_time!(config, data) -> rep_time

Load the representative time `rep_time` from the `:time_file` specified in the `config`
"""
function load_time!(config, data)
    rep_time = load_table(config[:time_file])
    force_table_types!(rep_time, :rep_time,
        :hours=>Float64,
        :day=>Int64,
    )
    data[:time] = rep_time
    return
end

"""
    load_af!(config, data)

Load the hourly availability factors, pulling them in from file, as needed.
"""
function load_af!(config, data)

    # Fill in gen table with default af of 1.0 for every hour
    gens = get_gen_table(data)
    default_hourly_af = ones(get_num_rep_hours(data))
    gens.af_hourly = fill(default_hourly_af, nrow(gens))
    
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
        :joint=>Int64,
        :status=>Bool,
        ("h_$n"=>Float64 for n in 1:get_num_rep_hours(data))...
    )

    data[:af] = df

    # Pull the availability factors in as a matrix
    hr_idx = findfirst(s->s=="h_1",names(df))
    af_mat = Matrix(df[:, hr_idx:end])
    if size(af_mat,2) != get_num_rep_hours(data)
        error("The number of representative hours given in :af_file=$(config[:af_file])  ($(size(af_mat,2))) is different than the hours in the time representation ($(get_num_rep_hours(data))).")
    end

    for i = 1:nrow(df)
        row = df[i, :]
        if row.status==false
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
            tmp = cond
            gentype = row.gentype
            gens = filter(:gentype=>==(gentype), gens, view=true)
        end

        isempty(gens) && continue
        
        af = [row[i_hr] for i_hr in hr_idx:ncol(df)]
        foreach(gen->gen.af_hourly = af, eachrow(gens))
    end
    return data
end

"""
    load_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function load_table(filename::String)
    CSV.File(filename, missingstring="NA") |> DataFrame
end

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
        initialize!(sym, mod, config, data)
    end
end


# Accessor Functions
################################################################################
"""
    get_gen_table(data)

Returns gen data table
"""
function get_gen_table(data) 
    return data[:gen]
end

"""
    get_branch_table(data)

Returns table of the transmission lines (branches) from data. 
"""
function get_branch_table(data) 
    return data[:branch]
end

"""
    get_bus_table(data)

Returns the bus data table
"""
function get_bus_table(data)
    data[:bus]
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

export get_gen_table, get_bus_table, get_branch_table
export get_generator, get_bus, get_branch
export get_bus_from_generator_idx

"""
    get_af(data, gen_idx, year_idx, time_idx) -> af

Retrieves the availability factor for a generator at a year and a time.
"""
function get_af(data, gen_idx, year_idx, time_idx)
    gen = get_generator(data, gen_idx)
    return gen.af_hourly[time_idx]
end

export get_af

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
    get_num_rep_hours(data) -> nh

Returns the number of representative hours in a year
"""
function get_num_rep_hours(data)
    time = get_rep_time(data)
    return length(time)
end

"""
    get_rep_time(data)

Returns the array of representative time chunks (hours)
""" 
function get_rep_time(data) 
    return data[:time].hours
end

export get_num_rep_hours, get_rep_time