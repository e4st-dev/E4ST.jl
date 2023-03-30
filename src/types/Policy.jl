"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.

## Policies (Policy subtypes)
* `[ITC]@ref`
* `[PTC]@ref`
* `[EmissionCap]@ref`
* `[EmissionPrice]@ref`
* `[RPS]@ref`
* `[CES]@ref`
"""
abstract type Policy <: Modification end


### Loading in Policies -----------------------------------

# TODO: Load in set of policies from a CSV


### Helper functions




