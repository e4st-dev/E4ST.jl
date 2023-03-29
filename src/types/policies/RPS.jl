### Renewable Portfolio Standards

@doc raw"""
    struct RPS <: Policy

Renewable Portfolio Standard - 
* `name` - Name of the policy 
* `values` - The yearly values for the RPS
* `gen_filters` - Filters on which generation qualifies to fulfill the RPS. Sometimes qualifying generators may be outside of the RPS load region if they supply power to it. 
* `crediting` - the crediting structure and related fields 
* `load_bus_filters` - Filters on which buses fall into the RPS load region. The RPS will be applied to the load from these buses. 
* `gen_stan` - GenerationStandard created on instantiation (not specified in the config)
"""
struct RPS <: Policy
    name::Symbol
    values::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict 
    gen_stan::GenerationStandard

end

function RPS(;name, values, crediting::OrderedDict, gen_filters, load_bus_filters)
    c = Crediting(crediting)
    gen_stan = GenerationStandard(name, values, c, gen_filters, load_bus_filters, RPS)
    return RPS(name, values, c, gen_filters, load_bus_filters, gen_stan)
end
export RPS


"""
    modify_setup_data!(pol::RPS, config, data) -> 
"""
function modify_setup_data!(pol::RPS, config, data)
    modify_setup_data!(pol.gen_stan, config, data)

end


"""
   struct StandardRPSCrediting <: Crediting

Standard RPS crediting structure. Anything included in the RPS gentypes recieves a credit of 1. 
"""
struct StandardRPSCrediting <: Crediting end
export StandardRPSCrediting

"""
    get_credit(c::StandardRPSCrediting)

Returns the credit for a given row in the generator table using standard RPS crediting. 
Qualifying technologies include: hyrdogen, geothermal, solar, and wind (SUBJECT TO CHANGE)
Anything qualifying technology gets a credit of one. 
"""
function get_credit(c::StandardRPSCrediting, gen_row::DataFrameRow)
    rps_gentypes = ["solar", "dist_solar", "wind", "oswind", "geothermal", "hcc_new", "hcc_ret"]
    gen_row.gentype in rps_gentypes && return 1.0
    #This could also be written to call the CreditByGentype method but probably not any better
end
export get_credit

# """
#     set_gs_credits!(pol::RPS, config, data) -> 

# Sets the credit level for generators that qualify under the RPS. 
# Default, all qualifying generators will receive a credit of 1. 
# """
# function set_gs_credits!(pol::RPS, config, data)
#     gen = get_table(data, :gen)

#     #get qualifying gen idxs
#     gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

#     v = zeros(Bool, nrow(gen))
#     add_table_col!(data, :gen, pol.name, v, Ratio,
#         "Credit level for generators that qualify under the $(cons.name) RPS") 
#     gen[gen_idxs, cons.name] .= 1 

#     #TODO: Does CCS get a partial credit for this? I think it does in some RPSs in matlab E4ST
# end