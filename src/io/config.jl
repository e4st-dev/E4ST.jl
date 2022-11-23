"""
    load_config(filename) -> config::OrderedDict{Symbol,Any}

Load the config file from `filename`, inferring any necessary settings as needed
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
function make_paths_absolute!(config, filename; path_keys = (:gen_file, :bus_file, :branch_file, :hours_file, :out_path, :af_file))
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
    config[sym] = OrderedDict(key=>Modification(val) for (key,val) in config[sym])
    return
end
