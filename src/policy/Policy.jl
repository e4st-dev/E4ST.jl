"""
    abstract type Policy

Policy represents an abstract type for really anything that would make changes to a model.

Policies can implement the following two interfaces:
* `apply!(policy, config, data, model)` - apply policy to the model, called in `setup_model`
* `results!(policy, config, data, model, results)` - gather the results from `policy` from the solved model, called in `get_results`
"""
abstract type Policy end

"""
    apply!(policy::Policy, config, data, model)

Apply policy to the model, called in `setup_model`
"""
function apply!(policy::Policy, config, data, model)
    @warn "No apply! function defined for policy $policy, doing nothing"
end

"""
    results!(policy::Policy, config, data, model, results)

Gather the results from `policy` from the solved model, called in `get_results`
"""
function results!(policy::Policy, config, data, model, results)
    @warn "No results! function defined for policy $policy, doing nothing"
end