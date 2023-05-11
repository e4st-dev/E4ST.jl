
"""
    struct ITC <: Policy

Investment Tax Credit - A tax incentive that is a percentage of capital cost given to generators that meet the qualifications. 

# Keyword Arguments

* `name`: policy name
* `values`: the credit level, stored as an OrderedDict with year and value `(:y2020=>0.3)`
* `gen_filters`: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct ITC <: Policy
    name::Symbol
    values::OrderedDict
    gen_filters::OrderedDict
end
export ITC

"""
    E4ST.modify_setup_data!(pol::ITC, config, data)

Creates a column in the gen table with the ITC value in each simulation year for the qualifying generators.
 
ITC values are calculated based on `capex_obj` so ITC values only apply in `year_on` for a generator.
"""
function E4ST.modify_setup_data!(pol::ITC, config, data)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying ITC $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)

    #create column of annualized ITC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity,
        "Investment tax credit value for $(pol.name)")

    #update column for gen_idx 
    #TODO: do we want the ITC value to apply to all years within econ life? Will get multiplied by capex_obj so will only be non zero for year_on but maybe for accounting? 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # credit yearly * capex_obj for that year, capex_obj is only non zero in year_on so ITC should only be non zero in year_on
        vals_tmp = [credit_yearly[i]*g.capex_obj[i, :]  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
end

"""
    function E4ST.modify_model!(pol::ITC, config, data, model)
    
Subtracts the ITC price * Capacity in that year from the objective function using [`add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::ITC, config, data, model)
    add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)
end

#TODO: something about how to process this in results

"""
    struct HydFuelITC <: Policy

HydFuelITC - Hydrogen Fuel Investment Tax Credit is a way to apply an investment tax credit to the facilities needed to produce hydrogen. 
The E4ST representation of hydrogen costs include the cost of the hydrogen production facility in the fuel cost so in order to apply an ITC to hydrogen generation, we need to apply a tax credit to the fuel cost. 
This is set up more like a PTC, where a PerMWhGen term is subtracted from the objective (instead of a PerMWCap value in a standard ITC). 
This is primarily used in representing the tech neutral ITC in the Inflation Reduction Act.  
"""
Base.@kwdef struct HydFuelITC <: Policy
    name::Symbol
    values::OrderedDict
    gen_filters::OrderedDict
end
export HydFuelITC

"""
    E4ST.modify_setup -> 

Creates a column in the gen table with the ITC value in each simulation year for the qualifying generators.
 
ITC values are calculated based on `fuel_cost` and `heat_rate`, resulting in a PerMWhGen value (see [`HydFuelITC`]@ref for more explanation).
"""
function E4ST.modify_setup_data!(pol::HydFuelITC, config, data)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying ITC $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)

    #create column of annualized ITC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity,
        "Investment tax credit value for $(pol.name)")

    #update column for gen_idx 
    #TODO: do we want the ITC value to apply to all years within econ life? Will get multiplied by capex_obj so will only be non zero for year_on but maybe for accounting? 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # credit yearly * capex_obj for that year, capex_obj is only non zero in year_on so ITC should only be non zero in year_on
        vals_tmp = [credit_yearly[i]*g.fuel_cost[i,:]*g.heat_rate  for i in 1:length(years)] 

        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end  
end

"""
    E4ST.modify_model!(pol::HydFuelITC, config, data, model) -> 

Subtracts the HydFuelITC price * generation in that year from the objective function using [`add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::HydFuelITC, config, data, model)
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end