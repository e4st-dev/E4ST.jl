"""
    load_config(filename) -> config::OrderedDict{Symbol,Any}

Load the config file from `filename`, inferring any necessary settings as needed
"""
function load_config(filename)
    if contains(filename, ".yml")
        config = YAML.load_file(filename, dicttype=OrderedDict{Symbol, Any})
    else
        error("No support for file $filename")
    end
    check_required_fields!(config)
    make_paths_absolute!(config, filename)
    convert_types!(config, :mods)
    return config
end

"""
    save_config!(config) -> nothing
    
saves the config to the output folder specified inside the config file
"""
function save_config!(config)
    # TODO: implement this
    return nothing
end

################################################################################
# Helper Functions
################################################################################
function required_fields()
    return (
        :gen_file,
        :branch_file,
        :bus_file,
        :out_path,
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
function make_paths_absolute!(config, filename; path_keys = (:gen_file, :bus_file, :branch_file, :out_path))
    path = dirname(filename)
    for key in path_keys
        fn = config[key]
        if ~isabspath(fn)
            config[key] = abspath(path, fn)
        end
    end
    return config
end

function convert_types!(config, sym::Symbol)
    config[sym] = map(Dict2Struct, config[sym])
end

"""
    Dict2Struct(d::OrderedDict{Symbol}) -> thing

Converts a dictionary `d` into a struct, where the type `T` is specified as a string or symbol by `d[:type]`.  The type is then instantiated with the other keys of `d` as kwargs.
"""
function Dict2Struct(d::OrderedDict{Symbol})
    T = get_type(d[:type])
    _discard_type(T; d...)
end
_discard_type(T; type=nothing, kwargs...) = T(;kwargs...)
