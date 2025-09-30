@doc raw"""
    struct PTC <: Policy
    
Production Tax Credit - A \$/MWh tax incentive for the generation of specific technology or under specific conditions.

# Keyword Arguments

* `name`: policy name 
* `values`: \$/MWh values of the PTC, stored as an OrderedDict with years and the value `(:y2020=>10)`, note `year` is a `Symbol`
* `years_after_ref_min`: Min (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to min gen age. 
* `years_after_ref_max`: Max (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to max gen age.
* `ref_year_col`: Column name to use as reference year for min and max above. Must be a year column. If this is :year_on, then the years_after_ref filters will filter gen age. If this is :year_retrofit, the the years_after_ref filters will filter by time since retrofit. 

* `gen_filters`: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct PTC <: Policy
    name::Symbol
    values::OrderedDict
    years_after_ref_min::Float64 = 0.0
    years_after_ref_max::Float64 = 9999.0
    ref_year_col::String = "year_on"
    # gen_age_min::Float64 = 0
    # gen_age_max::Float64 = 9999
    gen_filters::OrderedDict
end
export PTC

function should_adjust_ptc(pol::PTC, config)
    # only adjust PTC if it is a multi-year sim and the length of the subisdy is less than the number of sim years
    # if length of subsidy is greater than sim years, there won't be an edge effect anyway
    return (length(config[:years])>1 && pol.years_after_ref_max - pol.years_after_ref_min >= length(config[:years]))
end
"""
    E4ST.modify_setup_data!(pol::PTC, config, data)

Creates a column in the gen table with the PTC value in each simulation year for the qualifying generators.
"""
function E4ST.modify_setup_data!(pol::PTC, config, data)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying PTC $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)
    years_int = year2float.(years)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value for $(pol.name)")

    # warn if trying to specify more than one unique PTC value, model isn't currently set up to handle variable PTC 
    # note: >2 used here for PTC value and 0
    length(unique(values(pol.values))) > 1 && @warn "The current E4ST PTC mod isn't formulated correctly for both a variable PTC value (ie. 2020: 12, 2025: 15) and year_from_ref filters. 
        Currently, generators will receive the same PTC for each year of the subsidy."

    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    if should_adjust_ptc(pol, config)

        for gen_idx in gen_idxs
            # update pol.name column with PTC credit value 
            g = gen[gen_idx, :]
            ref_year = year2float(g[Symbol(pol.ref_year_col)])
            year_min = ref_year + pol.years_after_ref_min
            year_max = ref_year + pol.years_after_ref_max
            g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
            vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
            adjs = [0.0  for i in 1:length(years)]
        
            # edge effect adjustment
            if any(vals_tmp .> 0)
                s = year_max - year_min
                e = g.econ_life

                capex_year_idxs = findall(y -> ref_year <= y <= ref_year + e, years_int)
                s_yrs = length(g_qual_year_idxs)
                c_yrs = length(capex_year_idxs)

                # adjust the ptc to avoid edge effects https://github.com/e4st-dev/E4ST.jl/issues/340
                if haskey(config[:mods],:perfect_foresight)
                    r = config[:mods][:perfect_foresight].rate::Float64 #pfs discount rate
                    adjs = [((1-(1-r)^c_yrs)/(1-(1-r)^e))/((1-(1-r)^s_yrs)/(1-(1-r)^s)) for i in 1:length(years)]
                else
                    r = 1 
                    # if model doesn't have pfs, the adjustment does not need to consider a discount rate
                    adjs = (c_yrs/e)/(s_yrs/s) && @warn "Running a multi-year model without perfect foresight"
                end
            
                vals_tmp = vals_tmp .* adjs
            end

            g[pol.name] = ByYear(vals_tmp)

        end
    
    else
        for gen_idx in gen_idxs
            # update pol.name column with PTC credit value 
            g = gen[gen_idx, :]
            ref_year = year2float(g[Symbol(pol.ref_year_col)])
            year_min = ref_year + pol.years_after_ref_min
            year_max = ref_year + pol.years_after_ref_max
            g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
            vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
            adjs = [0.0  for i in 1:length(years)]
 
            g[pol.name] = ByYear(vals_tmp)
        end
    end

end


"""
    function E4ST.modify_model!(pol::PTC, config, data, model)

Subtracts the PTC price * generation in that year from the objective function using [`add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::PTC, config, data, model)
    # subtract PTC value 
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end


"""
    E4ST.modify_results!(pol::PTC, config, data) -> 

Calculates PTC policy cost as a results formula in the gen table. PTC Cost = PTC value * generation 
"""
function E4ST.modify_results!(pol::PTC, config, data)
    # policy cost, PTC value * generation
    result_name = "$(pol.name)_cost"
    result_name_sym = Symbol(result_name)
    add_results_formula!(data, :gen, result_name_sym, "SumHourlyWeighted($(pol.name), pgen)", Dollars, "The cost of $(pol.name)")
    add_to_results_formula!(data, :gen, :ptc_subsidy, result_name)
end
