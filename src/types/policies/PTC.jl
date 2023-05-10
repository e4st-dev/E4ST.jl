@doc raw"""
    struct PTC <: Policy
    
Production Tax Credit - A \$/MWh tax incentive for the generation of specific technology or under specific conditions.

# Keyword Arguments

* `name`: policy name 
* `values`: \$/MWh values of the PTC, stored as an OrderedDict with years and the value `(:y2020=>10)`, note `year` is a `Symbol`
* `gen_age_min`: minimum generator age to qualifying (inclusive)
* `gen_age_max`: maximum generator age to qualify (inclusive)
* `gen_filters`: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct PTC <: Policy
    name::Symbol
    values::OrderedDict
    gen_age_min::Float64
    gen_age_max::Float64
    gen_filters::OrderedDict
end
export PTC

"""
    E4ST.modify_setup_data!(pol::PTC, config, data)

Creates a column in the gen table with the PTC value in each simulation year for the qualifying generators.
"""
function E4ST.modify_setup_data!(pol::PTC, config, data)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying PTC $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value for $(pol.name)")

    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
        vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
end


"""
    function E4ST.modify_model!(pol::PTC, config, data, model)

Subtracts the PTC price * generation in that year from the objective function using [`add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::PTC, config, data, model)
    
    # gen = get_table(data, :gen)
    # gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    # @info "Applying PTC $(pol.name) to $(length(gen_idxs)) generators"

    # years = get_years(data)

    # #create column of PTC values
    # add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
    #     "Production tax credit value for $(pol.name)")

    # #update column for gen_idx 
    # credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    # for gen_idx in gen_idxs
    #     g = gen[gen_idx, :]
    #     g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
    #     vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
    #     gen[gen_idx, pol.name] = ByYear(vals_tmp)
    # end
    # data[:gen] = gen
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end


#TODO: something about how to process this in results
