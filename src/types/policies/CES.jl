
@doc raw"""
    struct CES <: Policy

**Clean Energy Standard** - A policy in which the load serving entity must purchase a certain ampount of clean energy credits. 
The number of credits for a type of generation depends on it's emission rates relative to a benchmark.

## Fields
* `name` - Name of the policy 
* `targets` - The yearly targets for the RPS
* `gen_filters` - Filters on which generation qualifies to fulfill the RPS. Sometimes qualifying generators may be outside of the RPS load region if they supply power to it. 
* `crediting` - the crediting structure and related fields. Standard CES crediting is CreditingByBenchmark. 
* `load_bus_filters` - Filters on which buses fall into the RPS load region. The RPS will be applied to the load from these buses. 
* `gen_stan` - GenerationStandard created on instantiation (not specified in the config)
"""
# struct CES <: Policy
#     name::Symbol
#     targets::OrderedDict
#     crediting::Crediting
#     gen_filters::OrderedDict
#     load_bus_filters::OrderedDict 
#     gen_stan::GenerationStandard
# end

const CES = GenerationStandard{:CES} where {CES <: Policy}

CES(name, targets, crediting::OrderedDict, gen_filters, load_bus_filters) = CES(name, targets, crediting, gen_filters, load_bus_filters)

# function CES(;name, targets, crediting::OrderedDict, gen_filters, load_bus_filters)
#     c = Crediting(crediting)
#     gen_stan = GenerationStandard(name, targets, c, gen_filters, load_bus_filters, CES)
#     return CES(name, targets, c, gen_filters, load_bus_filters, gen_stan)
# end
export CES

mod_rank(::Type{CES}) = 1.0

"""
    modify_setup_data!(pol::CES, config, data) -> 

Calls `modify_setup_data!` on the generation standard. This will add the credits column for this policy to the gen table. 
"""
# function modify_setup_data!(pol::CES, config, data)
#     modify_setup_data!(pol.gen_stan, config, data)

# end

# function modify_model!(pol::CES, config, data, model)
#     modify_model!(pol.gen_stan, config, data, model)
# end


