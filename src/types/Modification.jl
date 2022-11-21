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
    function Modification(d::OrderedDict)

Constructs a Modification of type `d[:type]` with keyword arguments for all the other key value pairs in `d`.
"""
function Modification(d::OrderedDict)
    T = get_type(d[:type])
    mod = _discard_type(T; d...)
    return mod
end

"""
    function _discard_type(T; type=nothing, kwargs...)

Makes sure type doesn't get passed in as a keyword argument. 
"""
function _discard_type(T; type=nothing, kwargs...) 
    T(;kwargs...)
end


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

"""
    fieldnames_for_yaml(::Type{M}) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(::Type{M}) where {M<:Modification}
    return fieldnames(M)
end


"""
    function YAML._print(io::IO, mod::M, level::Int=0, ignore_level::Bool=false) where {M<:Modification}

Prints the field determined in fieldnames_for_yaml from the Modification. 
"""
function YAML._print(io::IO, mod::M, level::Int=0, ignore_level::Bool=false) where {M<:Modification}
    println(io)
    moddict = OrderedDict(:type => string(typeof(mod)), (k=>getproperty(mod, k) for k in fieldnames_for_yaml(M))...)
    YAML._print(io::IO, moddict, level, ignore_level)
end

"""
    function Base.getindex(mod::M, key) where {M<:Modification}

Returns value of the Modification for the given key (not index)
"""
function Base.getindex(mod::M, key::Symbol) where {M<:Modification}
    return getproperty(mod, key)
end