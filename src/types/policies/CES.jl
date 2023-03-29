
@doc raw"""
    struct CES <: Policy

**Clean Energy Standard** - A policy in which the load serving entity must purchase a certain ampount of clean energy credits. 
The number of credits for a type of generation depends on it's emission rates relative to a benchmark.

## Fields
* `name` - Name of the policy 
* `values` - The yearly values for the RPS
* `gen_filters` - Filters on which generation qualifies to fulfill the RPS. Sometimes qualifying generators may be outside of the RPS load region if they supply power to it. 
* `crediting` - the crediting structure and related fields 
* `load_bus_filters` - Filters on which buses fall into the RPS load region. The RPS will be applied to the load from these buses. 
* `gen_stan` - GenerationStandard created on instantiation (not specified in the config)
"""
struct CES <: policy
    name::Symbol
    values::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict 
    gen_stan::GenerationStandard
end