"""
    struct ModWrapper{T} <: Modification

This is a structure used to store both a mod, and a dictionary used to represent it.  Note that it is parameterized by the type of the mod that it wraps.

Constructor:

    ModWrapper(name, d::OrderedDict{Symbol, Any})
"""
struct ModWrapper{T, S} <: Modification
    name::Symbol
    dict::OrderedDict{Symbol, Any}
    mod::T
    function ModWrapper(name::Symbol, d::OrderedDict{Symbol, Any})
        T = get_type(d[:type])
        mod = _discard_type(T; d...)
        return new{T, name}(name, d, mod)
    end
end

function _discard_type(T; type=nothing, kwargs...) 
    T(;kwargs...)
end

initialize!(mod::ModWrapper, config, data) = initialize!(mod.mod, config, data)
apply!(mod::ModWrapper, config, data, model) = initialize!(mod.mod, config, data)
results!(mod::ModWrapper, config, data, model, results) = initialize!(mod.mod, config, data)