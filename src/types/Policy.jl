"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.
"""
abstract type Policy <: Modification end


### Loading in Policies -----------------------------------




### Basic Policy Types ------------------------------------

"""
    struct CES <: Policy

Clean Energy Standard - Load serving entity must purchase a certain amount of clean energy credits. The number of credits for a type of generation depends on it's emissions relative to a benchmark.
"""
struct CES <: Policy
    name::Symbol
    value::OrderedDict #
    benchmark::Float64

    # function CES(;name,emiscol,benchmark,cap_file)
    #     #create a container of cap value and years 
    #     cap_table = load_table(joinpath(@__DIR__,cap_file))
    #         #for each year in the sim that is in the cap_table, add it to a vector and then call set_yearly
    # end

end

"""
    struct PTC <: Policy
    
Production Tax Credit - A \$/MWh tax incentive for the generation of specific technology or under specific conditions.

name: policy name 
value: \$/MWh value of the PTC, stored as an OrderedDict with years and the value (:y2020=>10), note year is a Symbol
gen_age_min: minimum generator age to qualifying (inclusive)
gen_age_max: maximum generator age to qualify (inclusive)
gen_filters: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (:emis_co2=>"<=0.1" for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct PTC <: Policy
    name::Symbol
    value::OrderedDict
    gen_age_min::Float64
    gen_age_max::Float64
    gen_filters::OrderedDict #Ethan adding a parse comparison that will work for ordered dicts 

end

"""
    function E4ST.modify_model!(pol::PTC, config, data, model)

Creates a column in the gen table with the PTC value in each simulation year for the qualifying generators.
Subtracts the PTC price * generation in that year from the objective function using `add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`
"""
function E4ST.modify_model!(pol::PTC, config, data, model)
    
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))
    years = get_years(data)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value for $(pol.name)")

    #update column for gen_idx 
    sim_values = [get(pol.value, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
        vals_tmp = [(i in g_qual_year_idxs) ? sim_values[i] : 0.0  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
    data[:gen] = gen
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end

#TODO: something about how to process this in results
#TODO: log statements

"""
    struct ITC <: Policy

Investment Tax Credit - A tax incentive that is a percentage of capital cost given to generators that meet the qualifications. 

name: policy name
value: the credit level, stored as an OrderedDict with year and value (:y2020=>0.3)
gen_filters: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (:emis_co2=>"<=0.1" for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct ITC <: Policy
    name::Symbol
    value::OrderedDict
    gen_filters::OrderedDict

end


"""
    function E4ST.modify_model!(pol::ITC, config, data, model)

Creates a column in the gen table with the ITC value in each simulation year for the qualifying generators. 
ITC values are calculated based on capex_obj so ITC values only apply in year_on for a generator.
Subtracts the ITC price * Capacity in that year from the objective function using `add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)`
"""
function E4ST.modify_model!(pol::ITC, config, data, model)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))
    years = get_years(data)
   
    #create column of annualized ITC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity,
        "Investment tax credit value for $(pol.name)")

    #update column for gen_idx 
    #TODO: do we want the ITC value to apply to all years within econ life? Will get multiplied by capex_obj so will only be non zero for year_on but maybe for accounting? 
    sim_values = [get(pol.value, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # sim val * capex_obj for that year, capex_obj is only non zero in year_on so ITC should only be non zero in year_on
        vals_tmp = [sim_values[i]*g.capex_obj.v[i]  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
    data[:gen] = gen
    add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)
end

#TODO: something about how to process this in results