"""
    should_iterate(config, data, model) -> 
    
Returns whether or not the model should iterate.
"""
function should_iterate(config, data, model)
    return true
end

"""
    iterate!(config, data, model) -> nothing

Change any necessary things for the next iteration.
"""
function iterate!(config, data, model)
    return nothing
end