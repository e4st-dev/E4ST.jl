## Emission captures


@doc raw"""
    struct EmisCap <: Policy

Emission Cap - A limit on a certain emission for a given region.
name
"""
Base.@kwdef struct EmisCap <: Policy
    name::AbstractString
    emis_col::AbstractString
    value::OrderedDict
    bus_filters::OrderedDict


end
export EmisCap

"""
 E4ST.modify_model!(pol::EmisCap, config, data, model)

"""
function E4ST.modify_model!(pol::EmisCap, config, data, model)
    # get buses and then associated gens
    gen = get_table(data, :gen)
    bus = get_table(data, :bus)

    bus_idxs = get_row_idxs(bus, parse_comparisons(pol.bus_filters))
    gen_idxs = []
    for bus_i in bus_idxs 
        append!(gen_idxs, get_bus_gens(data, bus_idx))
    end

    emis_col = Symbol{emis_col}
    
    #get cap values for the sim years
    cap_yearly = [get(pol.value, Symbol(year), 0.0) for year in years] #values for the years in the sim

    #set constraint on total emissions for given gens based on emis rate and gen
    @constraint(model, pol.name[year_idx in 1:length(years)],
        sum(get_table_val(data, :gen, emis_col, gen_idx)*get_egen_gen(data, model, gen_idx, year_idx), gen_idxs) <= cap_yearly[year_idx])

end