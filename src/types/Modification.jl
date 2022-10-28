"""
    abstract type Modification

Modification represents an abstract type for really anything that would make changes to a model.

Modifications can implement the following two interfaces:
* `initialize!(mod, config, data)` - initialize the data according to the `mod`, called in `initialize_data!`
* `apply!(mod, config, data, model)` - apply `mod` to the model, called in `setup_model`
* `results!(mod, config, data, model, results)` - gather the results from `mod` from the solved model, called in `parse_results`
"""
abstract type Modification end

"""
    initialize!(mod::Modification, config, data, model)

Initialize the data with `mod`.
"""
function initialize!(mod::Modification, config, data)
    @warn "No initialize! function defined for mod $mod, doing nothing"
end


"""
    apply!(mod::Modification, config, data, model)

Apply mod to the model, called in `setup_model`
"""
function apply!(mod::Modification, config, data, model)
    @warn "No apply! function defined for mod $mod, doing nothing"
end

"""
    results!(mod::Modification, config, data, model, results)

Gather the results from `mod` from the solved model, called in `parse_results`
"""
function results!(mod::Modification, config, data, model, results)
    @warn "No results! function defined for mod $mod, doing nothing"
end

"""
    fieldnames_for_yaml(::Type{M}) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldname_for_yaml(::Type{M}) where {M<:Modification}
    return fieldnames(M)
end


"""
    YAML._print(io::IO, mod::M) where {M<:Modificaiton}

prints the appropriate data from an IO for each type of Modification
"""

function YAML._print(io::IO, mod::M) where {M<:Modification}
    YAML._print(io::IO, OrderedDict(k=>getpropoerty(mod, k) for k in fieldnames_for_yaml(M)))
end