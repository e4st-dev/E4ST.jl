"""
    load_config(filename) -> config::OrderedDict{Symbol,Any}

Load the config file from `filename`, inferring any necessary settings as needed
"""
function load_config(filename)
    if contains(filename, ".yml")
        config = YAML.load_file(filename, dicttype=OrderedDict{Symbol, Any})
        merge!(config, OrderedDict{Symbol, Any}("configfilename" => filename)) #maybe add a run name or date once that is part of e4st
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
function save_config(config)
    # create new ordered dict with just the necessary outputs for each Mod
    configout = OrderedDict{Symbol, Any}() # could probably just modify config directly if done using it elsewhere
    for (i,j) in config
        if i === :mods
            configout[i] = save_format_mods(config[:mods])
        else
            configout[i] = config[i]
        end
    end

    # write out configout
    YAML.write_file(string(configout[:out_path],config[:configfilename], "_out"), configout)
    # may need to change file path depending on where this gets run
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
    config[sym] = OrderedDict(key=>ModWrapper(key, val) for (key,val) in config[sym])
end

"""
save_format_mods(mods::OrderedDict)

takes the :mods dict for the config dict and pulls out only the required fields for saving into the output yml config file
returns a :mods ordered dict with only select information 

"""
function save_format_mods(mods::OrderedDict)
    for m in mods
        #add relevant parts of the mod to configout
        tmpmod = OrderedDict{Symbol, Any}()
        for f in fieldname_for_yaml(m)
            tmpmod[f] = m[f]
        end
        mods[m] = tmpmod
    end
    return mods
end
