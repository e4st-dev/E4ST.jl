
"""
    struct ITC <: Policy

Investment Tax Credit - A tax incentive that is a percentage of capital cost given to generators that meet the qualifications. 

# Keyword Arguments

* `name`: policy name
* `values`: the credit level, stored as an OrderedDict with year and value `(:y2020=>0.3)`.  Credit level refers to the percentage of the capex that will be rebated to the investor
* `gen_filters`: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct ITC <: Policy
    name::Symbol
    values::OrderedDict
    gen_filters::OrderedDict = OrderedDict{Symbol, Any}()
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
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # credit yearly * capex_obj for that year, capex_obj is only non zero in year_on so ITC should only be non zero in year_on
        vals_tmp = [credit_yearly[i]*g.capex_obj[i,:] for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
end

"""
    function E4ST.modify_model!(pol::ITC, config, data, model)
    
Subtracts the ITC price * Capacity in that year from the objective function using [`add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::ITC, config, data, model)
    add_obj_term!(data, model, PerMWCapInv(), pol.name, oper = -) 
end


"""
    E4ST.modify_results!(pol::ITC, config, data) -> 

Calculates ITC cost as seen by the objective (cost_obj) which is ITC value * capacity (where ITC value is credit level as a % multiplied by capital cost)
"""
function E4ST.modify_results!(pol::ITC, config, data)

    # calculate objective policy cost (based on capacity in each sim year)
    add_results_formula!(data, :gen, Symbol("$(pol.name)_cost_obj"), "SumYearly($(pol.name),ecap_inv_sim)", Dollars, "The cost of $(pol.name) as seen by the objective, not used for gov spending welfare")
    #add_results_formula!(data, :gen, Symbol("$(pol.name)_cost_obj"), "SumHourly($(pol.name),ecap)", Dollars, "The cost of $(pol.name) as seen by the objective, not necessarily used for gov spending welfare")

    # for gen_idx in gen_idxs
    #     g = gen[gen_idx, :]

    #     # credit yearly * capex_obj for that year, capex_obj is only non zero in year_on so ITC should only be non zero in year_on
    #     vals_tmp = [credit_yearly[i]*g.capex_obj.v[i]  for i in 1:length(years)]
    #     gen[gen_idx, pol.name] = ByYear(vals_tmp)
    # end
    # data[:gen] = gen
    add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)
end

function E4ST.modify_results!(pol::ITC, config, data)
    total_result_name = "$(pol.name)_cost_obj"
    total_result_sym = Symbol(total_result_name)

    # calculate objective policy cost (based on capacity in each sim year)
    add_results_formula!(data, :gen, total_result_sym, "SumYearly($(pol.name),ecap_inv_sim)", Dollars, "The cost of $(pol.name) as seen by the objective, not used for gov spending welfare")
    #add_results_formula!(data, :gen, Symbol("$(pol.name)_cost_obj"), "SumHourly($(pol.name),ecap)", Dollars, "The cost of $(pol.name) as seen by the objective, not necessarily used for gov spending welfare")

    add_to_results_formula!(data, :gen, :invest_subsidy, total_result_name)
end
