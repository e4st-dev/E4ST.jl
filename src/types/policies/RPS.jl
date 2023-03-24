### Renewable Portfolio Standards

@doc raw"""
    struct RPS <: Policy

Renewable Portfolio Standard - 
*`name` - Name of the policy 
*`values`
*`gen_filters` - Filters on which generation qualifies to fulfill the RPS. Sometimes qualifying generators may be outside of the RPS region if they supply power to it. 
*`load_bus_filters` - Filters on which buses fall into the RPS region. The RPS will be applied to the load from these buses. 
"""
struct RPS <: Policy
    name::Symbol
    values
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict 

end

@doc raw"""
    struct GenerationStandard <: Policy

*`name` - Name of the policy/standard 
*`gen_credits`- An OrderedDict of the generation types and the credit level that they receive
*`gen_filters` - An OrderedDict of filters for which generators can supply to meet the generation standard
"""
struct GenerationStandard <: Policy 
    name::Symbol
    gen_credits::OrderedDict
    gen_filters::OrderedDict
    
end
