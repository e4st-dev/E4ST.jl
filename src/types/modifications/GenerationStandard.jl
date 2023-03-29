@doc raw"""
    struct GenerationStandard <: Policy

A generation standard (also refered to as a portfolio standard) is a constraint on generation where a portion of generation from certain generators must meet the a portion of the load in a specified region.
This encompasses RPSs, CESs, and technology carveouts.
To assign the credit (the portion of generation that can contribute) to generators, the [Crediting](@ref) type is used.

* `name` - Name of the policy 
* `values` - The yearly values for the Generation Standard
* `gen_filters` - Filters on which generation qualifies to fulfill the GS. Sometimes qualifying generators may be outside of the GS load region if they supply power to it. 
* `crediting` - the crediting structure and related fields
* `load_bus_filters` - Filters on which buses fall into the GS load region. The GS will be applied to the load from these buses. 
* `gs_type` - The original type the GS (RPS, CES, etc)
"""
struct GenerationStandard <: Policy 
    name::Symbol
    values::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict
    gs_type::DataType

end
function GenerationStandard(;name, values, crediting::OrderedDict, gen_filters, load_bus_filters, gs_type)
    c = Crediting(crediting)
    return GenerationStandard(Symbol(name), values, c, gen_filters, load_bus_filters, gs_type)
end
export GenerationStandard

"""
    modify_setup_data!(pol::GenerationStandard, config, data)

"""
function modify_setup_data!(pol::GenerationStandard, config, data)
    #add policy name and type to data[:gs_pol_list]
    add_to_gs_pol_list!(pol, config, data) 

    #get gen idxs 
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    #create get table column for policy, set to zeros to start
    v = zeros(Float64, nrow(gen))
    add_table_col!(data, :gen, pol.name, v, Ratio,
        "Credit level for generation standard: $(pol.name)")

    #set credit level in the gen table
    #call get_credit on gen_idxs, dispatching on crediting type
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        gen[gen_idx, pol.name] = get_credit(pol.crediting, g)
    end

end

"""
    add_to_gs_pol_list!(pol, config, data) -> 

Adds the generation standard policy name and type as a key value pair in an ordered dict `data[:gs_pol_list]`
"""
function add_to_gs_pol_list!(pol::GenerationStandard, config, data)
    if haskey(data, :gs_pol_list) #TODO: could come up with better name
        data[:gs_pol_list][pol.name] = pol.gs_type
    else 
        #create gs_pol_list if it doesn't exist yet
        data[:gs_pol_list] = OrderedDict{}(
            pol.name => pol.gs_type
        )
    end
end

