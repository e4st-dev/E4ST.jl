"""
    abstract type Modification

Modification represents an abstract type for really anything that would make changes to a model.

Modifications can implement the following two interfaces:
* `initialize!(sym, mod, config, data)` - initialize the data according to the `mod` named `sym`, called in `initialize_data!`
* `apply!(sym, mod, config, data, model)` - apply the `mod` named `sym` to the model, called in `setup_model`
* `results!(sym, mod, config, data, model, results)` - gather the results from the `mod` named `sym` from the solved model, called in `parse_results`
"""
abstract type Modification end

"""
    initialize!(sym, mod::Modification, config, data, model)

Initialize the data with `mod`.
"""
function initialize!(sym, mod::Modification, config, data)
    @warn "No initialize! function defined for mod $sym: $mod, doing nothing"
end


"""
    apply!(sym, mod::Modification, config, data, model)

Apply mod to the model, called in `setup_model`
"""
function apply!(sym, mod::Modification, config, data, model)
    @warn "No apply! function defined for mod $sym: $mod, doing nothing"
end

"""
    results!(sym, mod::Modification, config, data, model, results)

Gather the results from `mod` from the solved model, called in `parse_results`
"""
function results!(sym, mod::Modification, config, data, model, results)
    @warn "No results! function defined for mod $sym: $mod, doing nothing"
end
