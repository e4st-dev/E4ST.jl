"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.

Basic Policy Types are used when defining standard policies in E4ST. They are specified as mods in the config file with a `type` field. 

There are currently six basic policy types. Novel policy types can also be added as needed. 

## Policies (Policy subtypes)
* [`ITC`](@ref)
* [`PTC`](@ref)
* [`EmissionCap`](@ref)
* [`EmissionPrice`](@ref)
* [`RPS`](@ref)
* [`CES`](@ref)
"""
abstract type Policy <: Modification end

mod_rank(::Type{<:Policy}) = 1.0

### Helper functions




