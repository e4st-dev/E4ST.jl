@doc raw"""
    struct GenerationStandard <: Policy

*`name` - Name of the policy/standard 
*`gen_credits`- An OrderedDict of the generation types and the credit level that they receive
*`gen_filters` - An OrderedDict of filters for which generators can supply to meet the generation standard
"""
struct GenerationStandard <: Policy 
    name::Symbol
    values::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict
    gs_type::DataType

    function GenerationStandard(;name, values, crediting, gen_filters, load_bus_filters, gs_type)
        c = Crediting(crediting)
        return GenerationStandard(Symbol(name), values, c, gen_filters, load_bus_filters, gs_type)
    end

    
end

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
function add_to_gs_pol_list!(pol::Policy, config, data)
    if haskey(data, :gs_pol_list) #TODO: could come up with better name
        data[:gs_pol_list][pol.name] => typeof(pol)
    else 
        #create gs_pol_list if it doesn't exist yet
        data[:gs_pol_list] => OrderedDict{}(
            pol.name => typeof(pol)
        )
    end
end