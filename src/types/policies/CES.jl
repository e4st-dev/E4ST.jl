
@doc raw"""
    const CES = GenerationStandard{:CES}

**Clean Energy Standard** - A policy in which the load serving entity must purchase a certain ampount of clean energy credits. 
The number of credits for a type of generation typically depends on it's emission rates relative to a benchmark.

CES is defined as an alias of [`GenerationStandard`](@ref). 

No default crediting is specified although the standard crediting will be [`CreditByBenchmark`](@ref) where the benchmark should be specified in the config.

## Fields
* `name` - Name of the policy 
* `targets` - The yearly targets for the CES
* `crediting` - the crediting structure and related fields. CES crediting is often [`CreditByBenchmark`](@ref). 
* `gen_filters` - Filters on which generation qualifies to fulfill the CES. Sometimes qualifying generators may be outside of the RPS load region if they supply power to it. 
* `load_bus_filters` - Filters on which buses fall into the load region. The CES will be applied to the load from these buses. 

[`GenerationStandard`](@ref)
"""
const CES = GenerationStandard{:CES}

CES(;name, crediting, gen_filters, load_targets) = CES(name, crediting, gen_filters, load_targets)

export CES



