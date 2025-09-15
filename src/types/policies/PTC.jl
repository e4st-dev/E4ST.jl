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

function should_adjust_invest_cost(pol::PTC)
    return (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)
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
    add_table_col!(data, :gen, "$(pol.name)_capex_adj", Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value adj for $(pol.name)")

    # if year_after_ref_min or max isn't set to default, then create capex_adj
    if should_adjust_invest_cost(pol)
        # warn if trying to specify more than one unique PTC value, model isn't currently set up to handle variable PTC 
        # note: >2 used here for PTC value and 0
        length(unique(values(pol.values))) > 2 && @warn "The current E4ST PTC mod isn't formulated correctly for both a variable PTC value (ie. 2020: 12, 2025: 15) and year_from_ref filters, please only specify a single PTC value"

        add_table_col!(data, :gen, Symbol("$(pol.name)_capex_adj"), Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacityPerHour, 
        "Adjustment factor added to the obj function as a PerMWCapInv term to account for PTC payments that do not continue through the entire econ lifetime of a generator.")
    end
    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    count = 0
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
        if config[:adjust_ptc] == true
            
            if any(vals_tmp .> 0)
                println(gen_idx)
                #subs_len = pol.years_after_ref_max - pol.years_after_ref_min
                subs_len = 11
                invest_life = g.econ_life + 1
                years_left_capex = min(years_int[end] - ref_year + 1, invest_life)
                years_left_subs = min(years_int[end] - ref_year + 1, subs_len)
                adjs = [(years_left_capex/invest_life)/(years_left_subs/subs_len) for i in 1:length(years)]
                vals_tmp = vals_tmp .* adjs
            end
        end

        # println(eltype(vals_tmp))
        # println(eltype(adjs))
 
        g[pol.name] = ByYear(vals_tmp)
        g["$(pol.name)_capex_adj"] = ByYear(adjs)
    
        # add capex adjustment term to the the pol.name _capex_adj column
        # if should_adjust_invest_cost(pol)
        #     adj_term = get_ptc_capex_adj(pol, g, config)
        #     g[Symbol("$(pol.name)_capex_adj")] = adj_term
        # end
    end
end


"""
    function E4ST.modify_model!(pol::PTC, config, data, model)

Subtracts the PTC price * generation in that year from the objective function using [`add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::PTC, config, data, model)
    # subtract PTC value 
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)

    # add the capex adjustment term 
    # should_adjust_invest_cost(pol) && add_obj_term!(data, model, PerMWCapInv(), Symbol("$(pol.name)_capex_adj"), oper = +)
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

    should_adjust_invest_cost(pol) && add_results_formula!(data, :gen, Symbol("$(pol.name)_capex_adj_total"), "SumYearly(ecap_inv_sim, $(pol.name)_capex_adj)", Dollars, "The necessary investment-based objective function penalty for having the subsidy end before the economic lifetime.")
    # Note there is no need to adjust welfare for the capex adjustment
end


"""
    get_ptc_capex_adj(pol::PTC, g::DataFrameRow) -> 
"""
function get_ptc_capex_adj(pol::PTC, g::DataFrameRow, config)
    r = config[:wacc]::Float64 #discount rate, using wacc to match generator cost calculations
    e = g.econ_life::Float64
    age_max = pol.years_after_ref_max
    age_min = pol.years_after_ref_min

    # determine whether capex needs to be adjusted, basically determining whether the span of age_min to age_max happens in the econ life
    age_min >= e && return ByNothing(0.0) # will receive no PTC naturally because gen will be shutdown before qualifying so no need to adjust capex
    (year2int(g.year_on) + age_max > year2int(g.year_shutdown)) && (age_max = year2int(g.year_shutdown) - year2int(g.year_on)) # if plant will shutdown before reaching age_max, change age_max to last age before shutdowns so only accounting for PTC received in lifetime
    (age_max - age_min >= e) && return ByNothing(0.0) # no need to adjust capex if reveiving PTC for entire econ life

    #hasproperty(g, :cf_hist) ? (cf = g.cf_hist) : @error "The gen and build_gen tables must have the column cf_hist in order to model PTCs with age filters."
    cf = get(g, :cf_hist) do
        get_gentype_cf_hist(g.gentype)
    end
    ptc_vals = g[pol.name]

    # This adjustment factor is the geometric formula for the difference between the actual PTC value per MW capacity and a PTC represented as a constant cash flow over the entire economic life. 
    # The derivation of this adj_factor can be found in the PTC documentation
    adj_factor = 1 - ((1-(1/(1+r))^(age_max+0.5))*(1-(1/(1+r))^(1.5)))/((1-(1/(1+r))^(e+0.5))*(1-(1/(1+r))^(age_min+1.5)))

    capex_adj = adj_factor .* cf .* ptc_vals
    return capex_adj
end


