"""
    read_sample_config_file() -> s

Reads in a test config file as a string.
"""
function read_sample_config_file()
    read(joinpath(@__DIR__,"../../test/config/config_3bus_examplepol.yml"), String)
end

@doc """
    load_config(filename) -> config::OrderedDict{Symbol,Any}

Load the config file from `filename`, inferring any necessary settings as needed.  See [`load_data`](@ref) to see how the `config` is used.

The Config File is a file that fully specifies all the necessary information.  Note that when filenames are given as a relative path, they are assumed to be relative to the location of the config file.

## Required Fields:
* `out_path` - The path (relative or absolute) to the desired output folder.  This folder doesn't necessarily need to exist.  The code should make it for you if it doesn't exist yet.  If there are already results living in the output path, E4ST will back them up to a folder called `backup_yymmddhhmmss`
* `gen_file` - The filepath (relative or absolute) to the generator table.  See [`load_gen_table!`](@ref).
* `bus_file` - The filepath (relative or absolute) to the bus table.  See [`load_bus_table!`](@ref)
* `branch_file` - The filepath (relative or absolute) to the branch table.  See [`load_branch_table!`](@ref)
* `hours_file` - The filepath (relative or absolute) to the hours table for the model's time representation.  See [`load_hours_table!`](@ref)
* `demand_file` - The filepath (relative or absolute) to the time representation.  See [`load_demand_table!`](@ref)
* `years` - a list of years to run in the simulation specified as a string.  I.e. `"y2030"`
* `optimizer` - The optimizer type and attributes to use in solving the linear program.  The `type` field should be always be given, (i.e. `type: HiGHS`) as well as each of the solver options you wish to set.  E4ST is a BYOS (Bring Your Own Solver :smile:) library, with default attributes for HiGHS and Gurobi.  For all other solvers, you're on your own to provide a reasonable set of attributes.  To see a full list of solvers with work with JuMP.jl, see [here](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers).
* `mods` - A list of `Modification`s specifying changes for how E4ST runs.  See the [`Modification`](@ref) for information on what they are, how to add them to a config file.

## Optional Fields:
* `af_file` - The filepath (relative or absolute) to the availability factor table.  See [`load_af_table!`](@ref)

## Example Config File
```yaml
$(read_sample_config_file())
```
"""
function load_config(filename)
    if contains(filename, ".yml")
        config = YAML.load_file(filename, dicttype=OrderedDict{Symbol, Any})
        get!(config, :config_file, filename)
    else
        error("No support for file $filename")
    end
    check_required_fields!(config)
    make_paths_absolute!(config, filename)
    convert_types!(config, :mods)
    return config
end

"""
    save_config(config) -> nothing
    
saves the config to the output folder specified inside the config file
"""
function save_config(config)

    # create output folder
    mkpath(config[:out_path])

    # create out path 
    io = open(joinpath(config[:out_path],basename(config[:config_file])), "w")
    
    # remove config filepath 
    config_file = pop!(config, :config_file)

    YAML.write(io, config)

    config[:config_file] = config_file

    close(io)
end

# Accessor Functions
################################################################################
function getmods(config)
    config[:mods]
end

# Helper Functions
################################################################################
function required_fields()
    return (
        :gen_file,
        :branch_file,
        :bus_file,
        :hours_file,
        :out_path,
        :optimizer,
        :mods
    )
end

function check_required_fields!(config)
    return all(f->haskey(config, f), required_fields())
end

"""
    make_paths_absolute!(config, filename; path_keys = (:gen_file, :bus_file, :branch_file))

Make all the paths in `config` absolute, corresponding to the keys given in `path_keys`.

Relative paths are relative to the location of the config file at `filename`
"""
function make_paths_absolute!(config, filename; path_keys = (:gen_file, :bus_file, :branch_file, :hours_file, :out_path, :af_file, :demand_file))
    path = dirname(filename)
    for key in path_keys
        haskey(config, key) || continue
        fn = config[key]
        if ~isabspath(fn)
            config[key] = abspath(path, fn)
        end
    end
    return config
end

function convert_types!(config, sym::Symbol)
    if isnothing(config[sym])
        config[sym] = OrderedDict{Symbol, Modification}()
        return
    end
    config[sym] = OrderedDict(key=>Modification(key=>val) for (key,val) in config[sym])
    return
end
