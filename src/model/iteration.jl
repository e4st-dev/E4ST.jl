"""
    abstract type Iterable

Represents how [`run_e4st`](@ref) should iterate through multiple optimizations.  This structure could be used for any number of things, such as:
* Running a sequence of years
* Iterating to find the optimal price for natural gas to meet some demand criterion.
* Running the first simulation for capacity/retirement, then run the next sim to find generation with a higher temporal resolution.

## Interfaces
* [`should_iterate(iter, config, data, model, results)`](@ref) - return whether or not the simulation should continue for another iteration.
* [`iterate!(iter, config, data, model, results)`](@ref) - Makes any changes to any of the structures between iterations. 
* [`should_reload_data(iter)`](@ref) - Returns whether or not to reload the data when iterating. 
* [`fieldnames_for_yaml(::Type{I})`](@ref) - (optional) return the fieldnames to print to yaml file in [`save_config`](@ref)
"""
abstract type Iterable end

function Iterable(d::AbstractDict)
    T = get_type(d[:type])
    iter = _discard_type(T; d...)
    return iter
end

"""    
    should_iterate(iter, config, data, model, results) -> Bool
    
Returns whether or not the model should iterate.
"""
function should_iterate end

"""
    fieldnames_for_yaml(::Type{I}) where {I<:Iterable}

returns the fieldnames in a yaml, used for printing, modified for different types of iterables. 
"""
function fieldnames_for_yaml(::Type{I}) where {I<:Iterable}
    return fieldnames(I)
end

"""
    should_reload_data(iter::Iterable) -> ::Bool

Return whether or not the data should be reloaded when iterating.
"""
function should_reload_data end


"""
    iterate!(iter::Iterable, config, data, model, results)

Make any necessary modifications to the `config` or `data` based on `iter`.
"""
function iterate! end


"""
    function YAML._print(io::IO, iter::I, level::Int=0, ignore_level::Bool=false) where {I<:Iterable}

Prints the field determined in fieldnames_for_yaml from the Modification. 
"""
function YAML._print(io::IO, iter::I, level::Int=0, ignore_level::Bool=false) where {I<:Iterable}
    println(io)
    iter_dict = OrderedDict(:type => string(typeof(iter)), (k=>getproperty(iter, k) for k in fieldnames_for_yaml(I))...)
    YAML._print(io::IO, iter_dict, level, ignore_level)
end

struct RunOnce end

function should_iterate(::RunOnce, args...)
    return false
end