"""
    read_sample_config_file() -> s

Reads in a test config file as a string.
"""
function read_sample_config_file()
    read(joinpath(@__DIR__,"../../test/config/config_3bus_examplepol.yml"), String)
end


function table2markdown(df::DataFrame)
    io = IOBuffer()
    print(io, "|")
    for n in names(df)
        print(io, " ", n, " |")
    end
    println(io)
    print(io, "|")
    foreach(x->print(io, " :-- |"), 1:ncol(df))
    println(io)
    for row in eachrow(df)
        print(io, "|")
        foreach(x->print(io, " ", table_element(x), " |"), row)
        println(io)
    end
    return String(take!(io))
end
export table2markdown

table_element(x) = x
table_element(x::Symbol) = "`$x`"

@doc """
    summarize_config() -> summary::DataFrame

Summarizes the `config`, with columns for:
* `name` - the property name, i.e. key
* `required` - whether or not the property is required
* `default` - default value of this property
* `description`

$(table2markdown(summarize_config()))
"""
function summarize_config()
    df = DataFrame("name"=>Symbol[], "required"=>Bool[], "default"=>[], "description"=>String[])
    push!(df, 
        # Required
        (:base_out_path, true, nothing, "The path (relative or absolute) to the desired output folder.  This folder doesn't necessarily need to exist.  The code will make it for you if it doesn't exist yet.  E4ST will make a timestamped folder within `base_out_path`, and store that new path into `config[out_path]`.  This is to prevent processes from overwriting one another."),
        (:gen_file, true, nothing, "The filepath (relative or absolute) to the generator table.  See [`summarize_table(::Val{:gen})`](@ref)."),
        (:bus_file, true, nothing, "The filepath (relative or absolute) to the bus table.  See [`summarize_table(::Val{:bus})`](@ref)."),
        (:branch_file, true, nothing, "The filepath (relative or absolute) to the branch table.  See [`summarize_table(::Val{:branch})`](@ref)."),
        (:hours_file, true, nothing, "The filepath (relative or absolute) to the hours table.  See [`summarize_table(::Val{:hours})`](@ref)."),
        (:nominal_load_file, true, nothing, "The filepath (relative or absolute) to the time representation.  See [`summarize_table(::Val{:nominal_load})`](@ref)"),
        (:years, true, nothing, "a list of years to run in the simulation specified as a string.  I.e. `\"y2030\"`"),
        (:optimizer, true, nothing, "The optimizer type and attributes to use in solving the linear program.  The `type` field should be always be given, (i.e. `type: HiGHS`) as well as each of the solver options you wish to set.  E4ST is a BYOS (Bring Your Own Solver :smile:) library, with default attributes for HiGHS and Gurobi.  For all other solvers, you're on your own to provide a reasonable set of attributes.  To see a full list of solvers with work with JuMP.jl, see [here](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers)."),
        (:mods, false, OrderedDict{Symbol, Modification}(), "A list of `Modification`s specifying changes for how E4ST runs.  See the [`Modification`](@ref) for information on what they are, how to add them to a config file."),
        
        ## Optional Fields:
        (:out_path, false, nothing, "the path to output to.  If this is not provided, an output path will be created [`make_out_path!`](@ref)."),
        (:other_config_files, false, nothing, "A list of other config files to read.  Note that the options in the parent file will be honored."),
        (:af_file, false, nothing, "The filepath (relative or absolute) to the availability factor table.  See [`summarize_table(::Val{:af_table})`](@ref)"),
        (:iter, false, RunOnce(), "The [`Iterable`](@ref) object to specify the way the sim should iterate.  If nothing specified, defaults to run a single time via [`RunOnce`](@ref).  Specify the `Iterable` type, and all keyword arguments."),
        (:load_shape_file, false, nothing, "a file for specifying the hourly shape of load elements.  See [`summarize_table(::Val{:load_shape})`](@ref)"),
        (:load_match_file, false, nothing, "a file for specifying annual load energy to match for sets.  See [`summarize_table(::Val{:load_match})`](@ref)"),
        (:load_add_file, false, nothing, "a file for specifying additional load energy, after matching.  See [`summarize_table(::Val{:load_add})`](@ref)"),
        (:load_add_file, false, nothing, "a file for specifying additional load energy, after matching.  See [`summarize_table(::Val{:load_add})`](@ref)"),
        (:build_gen_file, false, nothing, "a file for specifying generators that could get built.  See [`summarize_table(::Val{:build_gen})`](@ref)"),
        (:gentype_genfuel_file, false, nothing, "a file for storing gentype-genfuel pairings.  See [`summarize_table(::Val{:genfuel})`](@ref)"),
        (:summary_table_file, false, nothing, "a file for giving information about additional columns not specified in [`summarize_table`](@ref)"),
        (:save_data, false, true, "A boolean specifying whether or not to save the loaded data to file for later use (i.e. by specifying a `data_file` for future simulations)."),
        (:data_file, false, nothing, "The filepath (relative or absolute) to the data file (a serialized julia object).  If this is provided, it will use this instead of loading data from all the other files."),
        (:save_model_presolve, false, false, "A boolean specifying whether or not to save the model before solving it, for later use (i.e. by specifying a `model_presolve_file` for future sims). Defaults to `false`"),
        (:model_presolve_file, false, nothing, "The filepath (relative or absolute) to the unsolved model.  If this is provided, it will use this instead of creating a new model."),
        (:save_data_parsed, false, true, "A boolean specifying whether or not to save the raw results after solving the model.  This could be useful for calling [`process_results!(config)`](@ref) in the future. Defaults to `true`"),
        (:save_data_processed, false, true, "A boolean specifying whether or not to save the processed results after solving the model.  Defaults to `true`."),
        (:objective_scalar, false, 1e6, "This is specifies how much to scale the objective by for the sake of the solver.  Does not impact any user-created expressions or shadow prices from the raw results, as they get scaled back.  (Defaults to 1e6)"),
        (:gen_pcap_threshold, false, 1e-6, "This is the minimum `pcap` threshold (in MW) for new generators to be kept.  Defaults to 1e-6 (i.e. 1W).  See also [`save_updated_gen_table`](@ref)"),
        (:voll, false, 5000, "This is the assumed value of lost load for which the objective function will be penalized for every MWh of curtailed load."),
        (:logging, false, true, "This specifies whether or not E4ST will log to [`get_out_path(config, \"E4ST.log\")`](@ref). Options include `true`, `false`, or `\"debug\"`.  See [`start_logging!`](@ref) for more info."),
        (:eor_leakage_rate, false, 0.5, "The assumed rate (between 0 and 1) at which CO₂ stored in Enhanced Oil Recovery (EOR) leaks back into the atmosphere."),
        (:line_loss_rate, false, 0.1, "The assumed electrical loss rate from generation to consumption, given as a ratio between 0 and 1.  Default is 0.1, or 10% energy loss"),
        (:line_loss_type, false, "plserv", "The term in the power balancing equation that gets penalized with line losses.  Can be \"pflow\" or \"plserv\". Using \"pflow\" is more accurate in that it accounts for only losses on power coming from somewhere else, at the expense of a larger problem size and greater solve time.  Default is `plserv` due to increased runtime with `pflow`"),
    )
    return df
end
export summarize_config

@doc """
    read_config(filename; kwargs...) -> config::OrderedDict{Symbol,Any}

    read_config(filenames; kwargs...) -> config::OrderedDict{Symbol,Any}

    read_config(path; kwargs...) -> config::OrderedDict{Symbol, Any}

Load the config file from `filename`, inferring any necessary settings as needed.  If `path` given, checks for `joinpath(path, "config.yml")`.  This can be used with the `out_path` returned by [`run_e4st`](@ref)  See [`read_data`](@ref) to see how the `config` is used.  If multiple filenames given, (in a vector, or separated by commas) merges them, preserving the settings found in the last file, when there are conflicts, appending the list of [`Modification`](@ref)s.  Uses [`summarize_config`](@ref) to infer defaults, when applicable.  Any specified `kwargs` are added to the config, over-writing anything except the list of [`Modification`](@ref)s.  Note

The Config File is a file that fully specifies all the necessary information.  Note that when filenames are given as a relative path, they are assumed to be relative to the location of the config file.

$(table2markdown(summarize_config()))

## Example Config File
```yaml
$(read_sample_config_file())
```
"""
function read_config(filenames...; kwargs...)
    config = _read_config(filenames; kwargs...)
    check_config!(config)
    check_years!(config)
    make_out_path!(config)
    convert_mods!(config)
    sort_mods_by_rank!(config)
    convert_iter!(config)
    return config
end

function _read_config(filename::AbstractString)
    if contains(filename, ".yml")
        config = YAML.load_file(filename, dicttype=OrderedDict{Symbol, Any})
        get!(config, :config_file, filename)
        make_paths_absolute!(config)
        if haskey(config, :other_config_files)
            other_files = pop!(config, :other_config_files)
            other_config = _read_config(other_files)
            _merge_config!(other_config, config)
            other_config[:config_file] = config[:config_file]
            return other_config
        end
    elseif isdir(filename)
        filename_new = joinpath(filename, "config.yml")
        isfile(filename_new) || error("No config file found at the following location:\n  $filename_new")
        return _read_config(filename_new)
    else
        error("Cannot load config from: $filename")
    end
    return config
end

function _read_config(filenames; kwargs...)
    config = _read_config(first(filenames))
    for i in 2:length(filenames)
        _read_config!(config, filenames[i])
    end
    _merge_config!(config, kwargs)
    return config
end

function _read_config!(config::OrderedDict, filename::AbstractString)
    config_new = _read_config(filename)
    _merge_config!(config, config_new)
end

function _merge_config!(config::OrderedDict, config_new)
    config_file = config[:config_file]

    mods = get(config, :mods, OrderedDict{Symbol, Any}())
    haskey(config_new, :mods) && merge!(mods, config_new[:mods])

    merge!(config, config_new)
    config[:config_file] = config_file
    config[:mods] = mods

    # Filter anything that is set to nothing
    filter!(p->!isnothing(p.second), config)
    return nothing
end


"""
    save_config(config) -> nothing
    
saves the config to the output folder specified inside the config file
"""
function save_config(config)

    # create output folder, though this should be done already.
    mkpath(config[:out_path])
    
    # remove config filepath 
    config_file = pop!(config, :config_file)

    YAML.write_file(get_out_path(config, "config.yml"), config)

    config[:config_file] = config_file
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
    logging = config[:logging]
    if logging === false
        logger = Base.NullLogger()
    else
        if logging == "debug"
            minlevel = Logging.Debug
        else
            minlevel = Logging.Info
        end
        # logger = Base.SimpleLogger(open(abspath(config[:out_path], "E4ST.log"),"w"), log_level)
        io = open(get_out_path(config, "E4ST.log"),"w")
        format = "{[{timestamp}] - {level} - :func}{@ {module} {filepath}:{line:cyan}:light_green}\n{message}"
        logger = MiniLogger(;io, minlevel, format, message_mode=:notransformations)
    end

    old_logger = Logging.global_logger(logger)
    config[:logger] = logger
    config[:old_logger] = old_logger
    log_start(config)
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
        "Output Path:\n",
        config[:out_path],
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
export header_string

"""
    time_string() -> s

Returns a time string in the format "yymmdd_HHMMSS"
"""
function time_string()
    format(now(), dateformat"yymmdd_HHMMSSsss")
end
export time_string

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

function closestream(logger::AbstractLogger)
end

function closestream(logger::MiniLogger)
    close(logger.io)
end


# Accessor Functions
################################################################################
function get_mods(config)
    config[:mods]
end
export get_mods

function get_iterator(config)
    return config[:iter]::Iterable
end
export get_iterator

# Helper Functions
################################################################################

"""
    check_years!(config::OrderedDict)

Enforces that `config[:years]` is a vector of year strings.
"""
function check_years!(config)
    config[:years] = check_years(config[:years])
end
"""
    check_years(years) -> years_corrected

Returns a vector of year strings.  I.e. `["y2020", "y2025"]`
"""
function check_years(years)
    _vec(_check_years(years))
end
function _check_years(y::Int)
    return "y$y"
end
function _check_years(y::String)
    return y
end
function _check_years(v::AbstractVector)
    _check_years.(v)
end
_vec(v::AbstractVector) = v
_vec(s::AbstractString) = [s]

"""
    check_config!(config)

Ensures that `config` has required fields listed in [`summarize_config`](@ref)
"""
function check_config!(config)
    summary = summarize_config()
    for row in eachrow(summary)
        name = row.name
        default = row.default
        if row.required === true
            @assert haskey(config, name) "config must have property $(name)"
        end
        if default !== nothing
            get!(config, name, default)
        end
    end
    return nothing
end
export check_config!

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
        k === :optimizer && continue
        if v isa OrderedDict
            make_paths_absolute!(v, filename)
        end
    end
    if haskey(config, :other_config_files)
        config[:other_config_files] = map(config[:other_config_files]) do fn
            isabspath(fn) && return fn
            abspath(path, fn)
        end
    end        
    return config
end
make_paths_absolute!(config) = make_paths_absolute!(config, config[:config_file])

"""
    contains_file_or_path(s) -> Bool

Returns true if `s` contains "_file" or "_path".
"""
function contains_file_or_path(s::AbstractString)
    return endswith(s, "file") || endswith(s, "path")
end
contains_file_or_path(s::Symbol) = contains_file_or_path(string(s))

"""
    latest_out_path(base_out_path) -> out_path

Returns the most recently created `out_path` from within `base_out_path`.
"""
function latest_out_path(base_out_path)
    dirs = readdir(base_out_path, join=true, sort=true)
    filter!(isdir, dirs)
    return last(dirs)
end
export latest_out_path

"""
    make_out_path!(config) -> nothing

If `config[:out_path]` provided, does nothing.  Otherwise, makes sure `config[:base_out_path]` exists, making it as needed.  Creates a new time-stamped folder via [`time_string`](@ref), stores it into `config[:out_path]`.  See [`get_out_path`](@ref) to create paths for output files. 
"""
function make_out_path!(config)
    haskey(config, :out_path) && return nothing
    base_out_path = config[:base_out_path]

    # Make out_path as necessary
    ~isdir(base_out_path) && mkpath(base_out_path)  
    
    out_path = joinpath(base_out_path, time_string())
    while isdir(out_path)
        out_path = joinpath(base_out_path, time_string())
    end
    
    mkpath(out_path)
    config[:out_path] = out_path

    return nothing
end
export make_out_path!

"""
    get_out_path(config, filename) -> path

Returns `joinpath(config[:out_path], filename)`
"""
function get_out_path(config, filename::String)
    joinpath(get_out_path(config), filename)
end
function get_out_path(config)
    config[:out_path]::String
end
export get_out_path

function convert_mods!(config)
    if ~haskey(config, :mods) || isnothing(config[:mods])
        config[:mods] = OrderedDict{Symbol, Modification}()
        return
    end
    config[:mods] = OrderedDict{Symbol, Modification}(key=>Modification(key=>val) for (key,val) in config[:mods])
    return
end

function sort_mods_by_rank!(config)
    mods = config[:mods]
    sort!(mods, by=mod_rank, byvalue=true)
end

function convert_iter!(config)
    config[:iter] isa RunOnce && return
    config[:iter] = Iterable(config[:iter])
    return
end