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
* `gen_file` - The filepath (relative or absolute) to the generator table.  See [`summarize_table(::Val{:gen})`](@ref).
* `bus_file` - The filepath (relative or absolute) to the bus table.  See [`summarize_table(::Val{:bus})`](@ref)
* `branch_file` - The filepath (relative or absolute) to the branch table.  See [`summarize_table(::Val{:branch})`](@ref)
* `hours_file` - The filepath (relative or absolute) to the hours table for the model's time representation.  See [`load_hours_table!`](@ref)
* `demand_file` - The filepath (relative or absolute) to the time representation.  See [`summarize_table(::Val{:demand_table})`](@ref)
* `years` - a list of years to run in the simulation specified as a string.  I.e. `"y2030"`
* `optimizer` - The optimizer type and attributes to use in solving the linear program.  The `type` field should be always be given, (i.e. `type: HiGHS`) as well as each of the solver options you wish to set.  E4ST is a BYOS (Bring Your Own Solver :smile:) library, with default attributes for HiGHS and Gurobi.  For all other solvers, you're on your own to provide a reasonable set of attributes.  To see a full list of solvers with work with JuMP.jl, see [here](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers).
* `mods` - A list of `Modification`s specifying changes for how E4ST runs.  See the [`Modification`](@ref) for information on what they are, how to add them to a config file.

## Optional Fields:
* `af_file` - The filepath (relative or absolute) to the availability factor table.  See [`summarize_table(::Val{:af_tabls})`](@ref)
* `iter` - The [`Iterable`](@ref) object to specify the way the sim should iterate.  If nothing specified, defaults to run a single time.  Specify the `Iterable` type, and all keyword arguments.
* `demand_shape_file` - a file for specifying the hourly shape of demand elements.  See [`summarize_table(::Val{:demand_shape})`](@ref)
* `demand_match_file` - a file for specifying annual demanded energy to match for sets  See [`summarize_table(::Val{:demand_match})`](@ref)
* `demand_add_file` - a file for specifying additional demanded energy, after matching.  See [`summarize_table(::Val{:demand_add})`](@ref)
* `summary_table_file` - a file for giving information about additional columns not specified in [`summarize_table`](@ref)
* `save_data` - A boolean specifying whether or not to save the loaded data to file for later use (i.e. by specifying a `data_file` for future simulations).  Defaults to `true`
* `data_file` - The filepath (relative or absolute) to the data file (a serialized julia object).  If this is provided, it will use this instead of loading data from all the other files.
* `save_model_presolve` - A boolean specifying whether or not to save the model before solving it, for later use (i.e. by specifying a `model_presolve_file` for future sims). Defaults to `false`
* `model_presolve_file` - The filepath (relative or absolute) to the unsolved model.  If this is provided, it will use this instead of creating a new model.
* `save_results_raw` - A boolean specifying whether or not to save the raw results after solving the model.  This could be useful for calling [`process_results(config)`](@ref) in the future.
* `results_raw_file` - The filepath (relative or absolute) to the raw results.  This is helpful for calling [`process_results(config)`](@ref) to generate user results without having to re-run E4ST.

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
    make_out_path!(config)
    convert_mods!(config)
    convert_iter!(config)
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


"""
    start_logging!(config)

Starts logging according to `config[:logging]`.  Possible options for `config[:logging]`:
* `true` (default): logs `@info`, `@warning`, and `@error` messages to `config[:out_path]/E4ST.log`
* `"debug"` - logs `@debug`, `@info`, `@warning`, and `@error` messages to `config[:out_path]/E4ST.log`
* `false` - no logging

To log things, you can use `@info`, `@warn`, or `@debug` as defined in Logging.jl.  Or you can use a convenience method for logging a header, [`log_header`](@ref)

To stop the logger and close its io stream, see [`stop_logging!(config)`](@ref)
"""
function start_logging!(config)
    logging = get(config, :logging, true)
    if logging === false
        logger = Base.NullLogger()
    else
        if logging == "debug"
            minlevel = Logging.Debug
        else
            minlevel = Logging.Info
        end
        # logger = Base.SimpleLogger(open(abspath(config[:out_path], "E4ST.log"),"w"), log_level)
        io = open(abspath(config[:out_path], "E4ST.log"),"w")
        format = "{[{timestamp}] - {level} - :func}{@ {module} {filepath}:{line:cyan}:light_green}\n{message}"
        logger = MiniLogger(;io, minlevel, format, message_mode=:notransformations)
    end

    old_logger = Logging.global_logger(logger)
    config[:logger] = logger
    config[:old_logger] = old_logger
    return
end
export start_logging!

"""
    stop_logging!(config)

Stops logging to console, closes the io stream of the current logger.
"""
function stop_logging!(config)
    haskey(config, :logger) || return
    logger = config[:logger]
    closestream(logger)
    global_logger(config[:old_logger])
    return
end
export stop_logging!

"""
    log_start(config)

Logs any necessary info at the beginning of a run of E4ST
"""
function log_start(config)
    @info string(
        header_string("STARTING E4ST"), 
        "\n\n",
        version_info_string(),
        "\nE4ST Info:\n",
        package_status_string(),
    )
end
export log_start

"""
    log_header(header)

Logs a 3-line header string by calling `@info` [`header_string(header)`](@ref)
"""
function log_header(header)
    @info header_string(header)
end
export log_header

"""
    header_string(header) -> s

Returns a 3-line header string
"""
function header_string(header)
    string("#"^80, "\n",header,"\n","#"^80)
end

"""
    time_string() -> s

Returns a time string in the format "yymmdd_HHMMSS"
"""
function time_string()
    format(now(), dateformat"yymmdd_HHMMSS")
end

"""
    date_string() -> s
    
Returns a date string in the format "yymmdd"
"""
function date_string()
    format(now(), dateformat"yymmdd")
end
export date_string
export time_string

function version_info_string()
    io = IOBuffer()
    versioninfo(io)
    s = String(take!(io))
    close(io)
    return s
end

"""
    package_status_string() -> s

Returns the output of Pkg.status() in a string
"""
function package_status_string()
    io = IOBuffer()
    Pkg.status(;io)
    s = String(take!(io))
    close(io)
    return s
end

"""
    closestream(logger)

Closes the logger's io stream, if applicable.
"""
function closestream(logger::SimpleLogger)
    close(logger.stream)
end

function closestream(logger::NullLogger)
end

function closestream(logger::MiniLogger)
    close(logger.io)
end


# Accessor Functions
################################################################################
function getmods(config)
    config[:mods]
end

function get_iterator(config)
    return get(config, :iter, RunOnce())
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
    make_paths_absolute!(config, filename)

Make all the paths in `config` absolute, corresponding to the keys given in `path_keys`.

Relative paths are relative to the location of the config file at `filename`
"""
function make_paths_absolute!(config, filename)
    # Get a list of path keys to make absolute
    path_keys = filter(contains_file_or_path, keys(config))

    path = dirname(filename)
    for key in path_keys
        fn = config[key]
        if ~isabspath(fn)
            config[key] = abspath(path, fn)
        end
    end
    for (k,v) in config
        if v isa OrderedDict
            make_paths_absolute!(v, filename)
        end
    end
    return config
end

"""
    contains_file_or_path(s) -> Bool

Returns true if `s` contains "_file" or "_path".
"""
function contains_file_or_path(s::AbstractString)
    return contains(s, "_file") || contains(s, "_path")
end
contains_file_or_path(s::Symbol) = contains_file_or_path(string(s))

function make_out_path!(config)
    out_path = config[:out_path]
    @info "Making output path at $out_path"
    if isdir(out_path)
        # Check to see if we need to move the contents to backup
        isempty(readdir(out_path)) && return
        backup_path = string(out_path, "_backup_", time_string())
        while isdir(backup_path)
            backup_path = string(out_path, "_backup_", time_string())
        end
        # Call the garbage collector to remove any things that may be locking a resource
        GC.gc()

        # Now move the out_path to backup
        mv(out_path, backup_path)
        @info "out_path already contains data, moving data from: \n$out_path\nto:\n$backup_path"
    end
    mkpath(config[:out_path])
end

"""
    out_path(config, filename) -> path

Returns `joinpath(config[:out_path], filename)`
"""
function out_path(config, filename::String)
    joinpath(config[:out_path], filename)
end
export out_path

function convert_mods!(config)
    if ~haskey(config, :mods) || isnothing(config[:mods])
        config[:mods] = OrderedDict{Symbol, Modification}()
        return
    end
    config[:mods] = OrderedDict{Symbol, Modification}(key=>Modification(key=>val) for (key,val) in config[:mods])
    return
end

function convert_iter!(config)
    haskey(config, :iter) || return
    config[:iter] = Iterable(config[:iter])
    return
end