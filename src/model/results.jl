"""
    parse_results(config, data, model) -> results

Retrieves results from the model, including:
* Raw results (anything you could possibly need from the model like decision variable values and shadow prices)
* Area/Annual results (?)
* Raw policy results (?)
* Welfare 
"""
function parse_results(config, data, model)

    results = Dict()
    # TODO: any general results gathering
    
    for mod in getmods(config)
        results!(mod, config, data, model, results)
    end

    return nothing
end

"""
    process!(config, results)

Process the `results` according to the instructions in `config`
"""
function process!(config, results)
    # TODO: Implement this
    return nothing
end