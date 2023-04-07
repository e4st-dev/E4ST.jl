"""
    process_results!(config::OrderedDict, data::OrderedDict) -> data

Calls [`modify_results!(mod, config, data)`](@ref) for each `Modification` in `config`.  Stores the results into `get_out_path(config, "data_processed.jls")` if `config[:save_data_processed]` is `true` (default).
"""
function process_results!(config::OrderedDict, data::OrderedDict)
    log_header("PROCESSING RESULTS")

    for (name, mod) in get_mods(config)
        modify_results!(mod, config, data)
    end

    if get(config, :save_data_processed, true)
        serialize(get_out_path(config,"data_processed.jls"), data)
    end

    return data
end

"""
    process_results!(config; processed=true) -> data

This loads `data` in, then calls [`process_results!(config, data)`](@ref).  
* `processed=false` - loads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - loads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(config; processed=true)
    if processed
        data = read_processed_results(config)
    else
        data = read_parsed_results(config)
    end
    return process_results!(config, data)
end
export process_results!

"""
    process_results!(mod_file::String, out_path::String; processed=true) -> data

Processes the results the [`Modification`](@ref)s found in `mod_file`, a .yml file similar to a `config` file (see [`read_config`](@ref)), only requiring the `mods` field.
* `processed=false` - loads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - loads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(mod_file::String, out_path::String; processed=true)

    # Load the config, and the modifications
    config = read_config(out_path)
    mods = _read_config(mod_file)
    convert_mods!(mods)

    # Merge the mods into config, overwriting anything in config
    merge!(config, mods)

    # Make sure we are using the right out_path.
    config[:out_path] = out_path

    # Now call process_results!
    process_results!(config; processed)
end
export process_results!
