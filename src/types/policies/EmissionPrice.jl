
@doc raw"""
    struct EmissionPrice <: Policy

Emission Price - A price on a certain emission for a given set of generators.

* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `prices`: OrderedDict of prices by year. Given as price per unit of emissions (ie. \$/short ton)
* `years_after_ref_min`: Min (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to min gen age. This is rarely used in real policy, so be careful if changing from default value
* `years_after_ref_max`: Max (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to max gen age. This is rarely used in real policy, so be careful if changing from default value
* `ref_year_col`: Column name to use as reference year for min and max above. Must be a year column. If this is :year_on, then the years_after_ref filters will filter gen age. If this is :year_retrofit, the the years_after_ref filters will filter by time since retrofit. This is rarely used in real policy, so be careful if changing from default value
* `gen_filters`: OrderedDict of generator filters
* `hour_filters`: OrderedDict of hour filters
"""
Base.@kwdef struct EmissionPrice <: Policy
    name::Symbol
    emis_col::Symbol
    prices::OrderedDict
    years_after_ref_min::Float64 = 0.
    years_after_ref_max::Float64 = 9999.
    ref_year_col::String = "year_on"
    gen_filters::OrderedDict = OrderedDict()
    hour_filters::OrderedDict = OrderedDict()
end
export EmissionPrice

function should_adjust_invest_cost(pol::EmissionPrice)
    return (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)
end

"""
    E4ST.modify_model!(pol::EmissionPrice, config, data, model)

Adds a column to the gen table containing the emission price as a per MWh value (gen emission rate * emission price). 
Adds this as a `PerMWhGen` price to the objective function using [`add_obj_term!`](@ref)
"""
function E4ST.modify_model!(pol::EmissionPrice, config, data, model)
    @info ("$(pol.name) modifying the model")

    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    hours = get_table(data, :hours)
    nhr = get_num_hours(data)
    hour_idxs = get_row_idxs(hours, parse_comparisons(pol.hour_filters))
    if length(hour_idxs) < nhr
        hour_multiplier = ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr])
    else
        hour_multiplier = 1.0
    end

    @info "Applying Emission Price $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)
    years_int = year2float.(years)

    #create column of Emission prices
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Emission price per MWh generated for $(pol.name)")

        # if year_after_ref_min or max isn't set to default, then create capex_adj
    if should_adjust_invest_cost(pol) 
        # warn if trying to specify more than one unique emisprc value, model isn't currently set up to handle variable emisprc 
        # note: >2 used here for emisprc value and 0
        length(unique(values(pol.prices))) > 2 && @warn "The current E4ST EmissionPrice mod isn't formulated correctly for both a variable EmissionPrice value (ie. 2020: 12, 2025: 15) and year_from_ref filters, please only specify a single value"

        add_table_col!(data, :gen, Symbol("$(pol.name)_capex_adj"), Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacityPerHour, 
        "Adjustment factor added to the obj function as a PerMWCapInv term to account for emisprc payments that do not continue through the entire econ lifetime of a generator.")
    end
    
    #update column for gen_idx 
    price_yearly = [get(pol.prices, Symbol(year), 0.0) for year in years] #prices for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # Get the years that qualify
        ref_year = year2float(g[pol.ref_year_col])
        year_min = ref_year + pol.years_after_ref_min
        year_max = ref_year + pol.years_after_ref_max
        g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
        qual_price_yearly = ByYear([(i in g_qual_year_idxs) ? price_yearly[i] : 0.0  for i in 1:length(years)])
        gen[gen_idx, pol.name] = qual_price_yearly .* gen[gen_idx, pol.emis_col] .* hour_multiplier #emission rate [st/MWh] * price [$/st] 

        # add capex adjustment term to the the pol.name _capex_adj column
        if should_adjust_invest_cost(pol)
            adj_term = get_emisprc_capex_adj(pol, g, config)
            g[Symbol("$(pol.name)_capex_adj")] = adj_term
        end
    end
    
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = +)

    # add the capex adjustment term 
    should_adjust_invest_cost(pol) && add_obj_term!(data, model, PerMWCapInv(), Symbol("$(pol.name)_capex_adj"), oper = -)
end


"""
    E4ST.modify_results!(pol::EmissionPrice, config, data) -> 
"""
function E4ST.modify_results!(pol::EmissionPrice, config, data)
    # policy cost, price per mwh * generation
    cost_name = Symbol("$(pol.name)_cost")
    add_results_formula!(data, :gen, cost_name, "SumHourlyWeighted($(pol.name), pgen)", Dollars, "The cost of $(pol.name)")
    add_to_results_formula!(data, :gen, :emission_cost, cost_name)

    should_adjust_invest_cost(pol) && add_results_formula!(data, :gen, Symbol("$(pol.name)_capex_adj_total"), "SumYearly(ecap_inv_sim, $(pol.name)_capex_adj)", Dollars, "The necessary investment-based objective function penalty for having the subsidy end before the economic lifetime.")
end

"""
    get_emisprc_capex_adj(pol::EmissionPrice, g::DataFrameRow) -> 
"""
function get_emisprc_capex_adj(pol::EmissionPrice, g::DataFrameRow, config)
    r = config[:wacc]::Float64 #discount rate, using wacc to match generator cost calculations
    e = g.econ_life::Float64
    age_max = pol.years_after_ref_max
    age_min = pol.years_after_ref_min

    # determine whether capex needs to be adjusted, basically determining whether the span of age_min to age_max happens in the econ life
    age_min >= e && return ByNothing(0.0) # will receive no emisprc naturally because gen will be shutdown before qualifying so no need to adjust capex
    (year2int(g.year_on) + age_max > year2int(g.year_shutdown)) && (age_max = year2int(g.year_shutdown) - year2int(g.year_on)) # if plant will shutdown before reaching age_max, change age_max to last age before shutdowns so only accounting for EmissionPrice received in lifetime
    (age_max - age_min >= e) && return ByNothing(0.0) # no need to adjust capex if reveiving emisprc for entire econ life

    #hasproperty(g, :cf_hist) ? (cf = g.cf_hist) : @error "The gen and build_gen tables must have the column cf_hist in order to model emisprcs with age filters."
    cf = get(g, :cf_hist) do
        get_gentype_cf_hist(g.gentype)
    end
    emisprc_vals = g[pol.name]

    # This adjustment factor is the geometric formula for the difference between the actual emisprc value per MW capacity and a emisprc represented as a constant cash flow over the entire economic life. 
    # The derivation of this adj_factor can be found in the PTC documentation
    adj_factor = 1 - ((1-(1/(1+r))^age_max)*(1-(1/(1+r))))/((1-(1/(1+r))^e)*(1-(1/(1+r))^(age_min+1)))

    capex_adj = adj_factor .* cf .* emisprc_vals
    return capex_adj
end


# """
#     modify_results!(config, data, model, results) -> 
# """
# function modify_results!(pol::EmissionPrice, config, data)
#     gen = get_table(data, :gen)
    
# end