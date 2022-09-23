"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`
"""
function load_data(config)
    # TODO: implement this
    return Dict()
end

"""
    initialize_data!(config, data)

Initializes the data with any necessary Modifications in the config
"""
function initialize_data!(config, data)
    for mod in getmods(config)
        initialize!(mod, config, data)
    end
end