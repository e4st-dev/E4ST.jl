"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`
"""
function load_data(config)
    data = OrderedDict()

    # Load in tables
    data[:gen]    = load_gen_table(config)
    data[:bus]    = load_bus_table(config)
    data[:branch] = load_branch_table(config)
    data[:time]   = load_time(config)

    return data
end

"""
    load_gen_table(config) -> gen

Load the generator from the `:gen_file` specified in the `config`
"""
function load_gen_table(config)
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
    return gen
end

"""
    load_bus_table(config) -> bus

Load the bus table from the `:bus_file` specified in the `config`
"""
function load_bus_table(config)
    bus = load_table(config[:bus_file])
    force_table_types!(bus, :bus,
        :ref_bus=>Bool,
        :pd=>Float64,
    )
    # force_table_types!(bus, :bus,
    #     :capex=>Float64,
    #     optional=true
    # )
    return bus
end

"""
    load_branch_table(config) -> branch

Load the branch table from the `:branch_file` specified in the `config`
"""
function load_branch_table(config)
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
    return branch
end

"""
    load_time(config) -> rep_time

Load the representative time `rep_time` from the `:time_file` specified in the `config`
"""
function load_time(config)
    rep_time = load_table(config[:time_file])
    force_table_types!(rep_time, :rep_time,
        :hours=>Float64,
        :day=>Int64,
    )
    return rep_time
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
    get_availability_factor(data, gen_idx, year_idx, time_idx) -> af

Retrieves the availability factor for 
"""
function get_availability_factor(data, gen_idx, year_idx, time_idx)
    haskey(data, :af_hourly) || return 1.0
    af = data[:af_hourly]
    g = get_generator(data, gen_idx)
    return _get_availability_factor(af, g, year_idx, time_idx)
end

function _get_availability_factor(af::Number, g, year_idx, time_idx)
    return af
end

function _get_availability_factor(af::AbstractDict, g, year_idx, time_idx)
    for (cond,v) in af
        cond(g) && return _getindex(v, time_idx)
    end
    return 1.0
end

function _getindex(v::Vector, idx)
    v[idx]
end

function _getindex(v::Number, idx)
    v
end


export get_availability_factor

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



"""
    UpdateAvailabilityFactors(;filename)

Update the availability factors according to a table stored in `filename`

TODO ECR: Document how those should be stored!!
"""
struct UpdateAvailabilityFactors <: Modification
    filename::String
    hourly::DataFrame
end

function UpdateAvailabilityFactors(;filename::String="")
    af = load_table(filename)
    force_table_types!(af, :af,
        :area=>String,
        :subarea=>String,
        :genfuel=>String,
        :gentype=>String,
        :joint=>Int64,
        :status=>Bool,
        ("h_$n"=>Float64 for n in 1:(ncol(af)-6))...
    )
    UpdateAvailabilityFactors(filename, af)
end

fieldnames_for_yaml(::Type{UpdateAvailabilityFactors}) = (:filename,)

function initialize!(sym, mod::UpdateAvailabilityFactors, config, data)
    df = mod.hourly
    
    # List of conditions mapping to the hourly availability factor
    af_hourly = get!(data, :af_hourly, OrderedDict{Function, Any}())

    hr_idx = findfirst(s->s=="h_1",names(df))
    af_mat = Matrix(df[:, hr_idx:end])
    if size(af_mat,2) != get_num_rep_hours(data)
        error("The number of representative hours given in UpdateAvailabilityFactors($(mod.filename))  ($(size(af_mat,2))) is different than the hours in the time representation ($(get_num_rep_hours(data))).")
    end

    for i = nrow(df):-1:1
        row = df[i, :]
        if row.status==false
            continue
        end

        cond = (gen)->true

        # Add the area-subarea pair to the condition
        if ~isnothing(row.area) && ~isnothing(row.subarea)
            tmp = cond
            area = row.area
            subarea = row.subarea
            cond = gen->(tmp(gen) && get_bus(data, gen.bus_idx)[area]==subarea)
        end

        # Add the genfuel to the condition
        if ~isnothing(row.genfuel)
            tmp = cond
            genfuel = row.genfuel
            @show typeof(genfuel)
            cond = gen->begin
                @show gen
                @show tmp
                tmp(gen) && return true
                return (gen.genfuel == genfuel)
            end
        end

        # # Add the gentype to the condition
        # if ~isnothing(row.gentype)
        #     tmp = cond
        #     gentype = row.gentype
        #     cond = gen->(tmp(gen) && gen.gentype == gentype)
        # end
        af_hourly[cond] = af_mat[i,:]
    end
end
export UpdateAvailabilityFactors