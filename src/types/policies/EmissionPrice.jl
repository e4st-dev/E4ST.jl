
@doc raw"""
    struct EmissionPrice <: Policy

Emission Price - A price on a certain emission for a given set of generators.

*`name`: name of the policy (Symbol)
*`emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
*`values`: OrderedDict of cap values by year
*`gen_filters`: OrderedDict of generator filters
"""
struct EmissionPrice <: Policy
    name::Symbol
    emis_col::Symbol
    values::OrderedDict
    gen_filters::OrderedDict
end

function EmissionPrice(;name::Any, emis_col::Any, values, gen_filters=OrderedDict())
    EmissionPrice(Symbol(name), Symbol(emis_col), values, gen_filters)
end
export EmissionPrice

function E4ST.modify_model!(pol::EmissionPrice, config, data, model)

    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying Emission Price $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Emission price per MWh generated for $(pol.name)")
    
    #update column for gen_idx 
    price_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        gen[gen_idx, pol.name] = scale_yearly(gen[gen_idx, pol.emis_col], price_yearly)
    end

    data[:gen] = gen
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = +)
end
