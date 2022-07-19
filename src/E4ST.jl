module E4ST

using E4STUtil

"""
    load_config(path) -> config

Load the config file from `path`, inferring any necessary settings as needed
"""
function load_config(path)
    # TODO: implement this
    return Dict()
end

"""
    save_config!(config) -> nothing
    
saves the config to the output folder specified inside the config file
"""
function save_config!(config)
    # TODO: implement this
    return nothing
end

"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`
"""
function load_data(config)
    # TODO: implement this
    return Dict()
end

"""
    setup_model(config, data) -> model
"""
function setup_model(config, data)
    # TODO: implement this
    return nothing
end

"""
    solve!(config, data, model) -> results
"""
function solve!(config, data, model)
    # TODO: implement this
    return nothing
end

"""
    save_results!(config, results) -> nothing

Save the results to the location listed in `config`.
"""
function save_results!(config, results)
    # TODO: implement this
    return nothing
end

"""
    load_results(config) -> results

Load and return the `results` in from the `config`.  Assumes the `config` has been run as-is.
"""
function load_results(config)
    # TODO: implement this
    return Dict()
end

"""
    postprocess!(config, results)

Postprocess the `results` according to the instructions in `config`
"""
function postprocess!(config, results)
    # TODO: Implement this
    return nothing
end

function run_e4st(path::String)
    run_e4st(load_config(path))
end


"""
    run_e4st(config) -> results

    run_e4st(filename) -> run_e4st(load_config(filename))

Top-level file for running E4ST
"""
function run_e4st(config)
    save_config!(config)
    data = load_data(config)
    model = setup_model(config, data)
    results = solve!(config, data, model)
    save_results!(config, results)
    postprocess!(config, results)
    return results
end

end # module
