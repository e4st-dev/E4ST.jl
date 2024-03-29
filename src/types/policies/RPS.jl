### Renewable Portfolio Standards

@doc raw"""
    const RPS = GenerationStandard{:RPS}

**Renewable Portfolio Standard** - A policy that constrains a certain amount of load from a region to be supplied by qualifying clean/renewable energy. 

RPS is defined as an alias of GenerationStandard where the default crediting type is StandardRPSCrediting.
mod_rank for RPS will be 1.0 because that is the rank of GenerationStandards

## Fields
* `name` - Name of the policy 
* `targets` - The yearly targets for the RPS
* `crediting` - the crediting structure and related fields. Standard CES crediting is CreditingByBenchmark.
* `gen_filters` - Filters on which generation qualifies to fulfill the RPS. Sometimes qualifying generators may be outside of the RPS load region if they supply power to it.  
* `load_bus_filters` - Filters on which buses fall into the RPS load region. The RPS will be applied to the load from these buses. 
    
[`GenerationStandard`](@ref)
"""
const RPS = GenerationStandard{:RPS}

RPS(;name, crediting=StandardRPSCrediting(), gen_filters, load_targets) = RPS(name, crediting, gen_filters, load_targets)

export RPS

@doc """
    struct StandardRPSCrediting <: Crediting

Standard RPS crediting structure. Anything included in the RPS gentypes recieves a credit of 1.  Creates a [`CreditByGentype`](@ref)

`$(collect(keys(StandardRPSCrediting().credits)))`
"""
struct StandardRPSCrediting <: Crediting 
    StandardRPSCrediting() = CreditByGentype(OrderedDict(
        "solar"=>1.0, 
        "dist_solar"=>1.0,
        "wind"=>1.0,
        "oswind"=>1.0, 
        "geothermal"=>1.0, 
        "hcc_new"=>1.0, 
        "hcc_ret"=>1.0 ))
end
export StandardRPSCrediting



# """
#     get_credit(c::StandardRPSCrediting, data, gen_row::DataFrameRow)

# Returns the credit for a given row in the generator table using standard RPS crediting. 
# Qualifying technologies include: hyrdogen, geothermal, solar, and wind (SUBJECT TO CHANGE)
# Anything qualifying technology gets a credit of one. 
# """
# function get_credit(c::StandardRPSCrediting, data, gen_row::DataFrameRow)
#     # rps_gentypes = ["solar", "dist_solar", "wind", "oswind", "geothermal", "hcc_new", "hcc_ret"]
#     # gen_row.gentype in rps_gentypes && return ByNothing(1.0)
    
#     #This could also be written to call the CreditByGentype method but probably not any better

#     c = CreditByGentype(OrderedDict(
#         "solar"=>1.0, 
#         "dist_solar"=>1.0,
#         "wind"=>1.0,
#         "oswind"=>1.0, 
#         "geothermal"=>1.0, 
#         "hcc_new"=>1.0, 
#         "hcc_ret"=>1.0 ))
#     get_credit(c, data, gen_row)

# end
# export get_credit


