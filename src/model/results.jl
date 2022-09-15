"""
    get_results(config, data, model) -> results
"""
function get_results(config, data, model)

    results = Dict()
    # TODO: any general results gathering
    
    for policy in getpolicies(data)
        results!(policy, config, data, model, results)
    end

    return nothing
end