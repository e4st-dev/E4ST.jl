
@doc raw"""
    struct EmissionPrice <: Policy

Emission Price - A price on a certain emission for a given set of generators.

* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `prices`: OrderedDict of prices by year. Given as price per unit of emissions (ie. \$/short ton)
* `gen_filters`: OrderedDict of generator filters
"""
struct EmissionPrice <: Policy
    name::Symbol
    emis_col::Symbol
    prices::OrderedDict
    gen_filters::OrderedDict
end

function EmissionPrice(;name::Any, emis_col::Any, prices, gen_filters=OrderedDict())
    EmissionPrice(Symbol(name), Symbol(emis_col), prices, gen_filters)
end
export EmissionPrice


"""
    E4ST.modify_model!(pol::EmissionPrice, config, data, model)

Adds a column to the gen table containing the emission price as a per MWh value (gen emission rate * emission price). 
Adds this as a `PerMWhGen` price to the objective function using [`add_obj_term!`](@ref)
"""
function E4ST.modify_model!(pol::EmissionPrice, config, data, model)
    @info ("$(pol.name) modifying the model")

    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying Emission Price $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)

    #create column of Emission prices
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Emission price per MWh generated for $(pol.name)")
    
    #update column for gen_idx 
    price_yearly = [get(pol.prices, Symbol(year), 0.0) for year in years] #prices for the years in the sim
    for gen_idx in gen_idxs
        gen[gen_idx, pol.name] = scale_yearly(gen[gen_idx, pol.emis_col], price_yearly) #emission rate [st/MWh] * price [$/st] 
    end
    
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = +)
end


"""
    E4ST.modify_results!(pol::EmissionPrice, config, data) -> 
"""
function E4ST.modify_results!(pol::EmissionPrice, config, data)
    # policy cost, price per mwh * generation
    add_results_formula!(data, :gen, Symbol("$(pol.name)_cost"), "SumHourly($(pol.name), egen)", Dollars, "The cost of $(pol.name)")

    #add_results_formula!(data, :gen, Symbol("$(pol.name)_qual_gen"), "SumHourly($(pol.name),egen)", Dollars, "The cost of $(pol.name)")
end