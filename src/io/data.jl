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
    )
    return rep_time
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
    load_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function load_table(filename::String)
    CSV.File(filename) |> DataFrame
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