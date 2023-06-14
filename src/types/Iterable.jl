"""
    abstract type Iterable

Sometimes, it may be desirable to run E4ST back-to-back with very similar sets of inputs, changing small things in the inputs between runs.  In order to do that, we have this custom interface!

The `Iterable` represents how [`run_e4st`](@ref) should iterate through multiple optimizations.  This structure could be used for any number of things, such as:
* Running a sequence of years
* Iterating to find the optimal price for natural gas to meet some load criterion.
* Running the first simulation for capacity/retirement, then run the next sim to find generation with a higher temporal resolution.

## Adding an Iterable to config
* Add the `Iterable` to the config, in the same way as you would add a `Modification` to the config file.  I.e.:
```yaml
# Inside config.yml
iter:
  type: MyIterType
  myfield: myval
```

## Interfaces
* [`init!(iter::Iterable, config)`](@ref) - (optional) Initialize `iter` with `config`, making any changes.
* [`issequential(iter)`](@ref) - (optional) returns whether or not the iterator will move forward in time sequentially.  Defaults to true so that the config can be reused for another simulation.
* [`should_iterate(iter, config, data)`](@ref) - return whether or not the simulation should continue for another iteration.
* [`iterate!(iter, config, data)`](@ref) - Makes any changes to any of the structures between iterations. 
* [`should_reread_data(iter)`](@ref) - Returns whether or not to reread the data when iterating. 
* [`fieldnames_for_yaml(::Type{<:Iterable})`](@ref) - (optional) return the fieldnames to print to yaml file in [`save_config`](@ref)
"""
abstract type Iterable end
export Iterable

function Iterable(d::AbstractDict)
    T = get_type(d[:type])
    iter = _discard_type(T; d...)
    return iter
end

"""
    init!(iter, config) -> nothing

Initialize `iter` with `config`, making any changes to `config` as needed.
"""
function init!(iter::Iterable, config)
    return nothing
end
export init!

"""
    issequential(iter) -> ::Bool

Return whether or not the iterator advances in years.  This may be necessary for some Modifications, whether they prepare the config to move forward or not.  Default is `true`.
"""
issequential(iter::Iterable) = true
export issequential

"""    
    should_iterate(iter, config, data) -> Bool
    
Returns whether or not E4ST should iterate.
"""
function should_iterate end
export should_iterate

"""
    fieldnames_for_yaml(::Type{I}) where {I<:Iterable}

returns the fieldnames in a yaml, used for printing, modified for different types of iterables. 
"""
function fieldnames_for_yaml(::Type{I}) where {I<:Iterable}
    return fieldnames(I)
end

"""
    should_reread_data(iter::Iterable) -> ::Bool

Return whether or not the data should be re-read when iterating.
"""
function should_reread_data end
export should_reread_data

"""
    iterate!(iter::Iterable, config, data)

Make any necessary modifications to the `config` or `data` based on `iter`.
"""
function iterate! end
export iterate!

"""
    function YAML._print(io::IO, iter::I, level::Int=0, ignore_level::Bool=false) where {I<:Iterable}

Prints the field determined in fieldnames_for_yaml from the Modification. 
"""
function YAML._print(io::IO, iter::I, level::Int=0, ignore_level::Bool=false) where {I<:Iterable}
    println(io)
    iter_dict = OrderedDict(:type => string(typeof(iter)), (k=>getproperty(iter, k) for k in fieldnames_for_yaml(I))...)
    YAML._print(io::IO, iter_dict, level, ignore_level)
end