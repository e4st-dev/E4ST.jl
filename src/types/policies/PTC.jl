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

    # if year_after_ref_min or max isn't set to default, then create capex_adj
    if (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)  
        # warn if trying to specify more than one unique PTC value, model isn't currently set up to handle variable PTC 
        # note: >2 used here for PTC value and 0
        length(unique(pol.values)) > 2 && @warn "The current E4ST PTC mod isn't formulated correctly for both a variable PTC value (ie. 2020: 12, 2025: 15) and year_from_ref filters, please only specify a single PTC value"

        add_table_col!(data, :gen, Symbol("$(pol.name)_capex_adj"), Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity, 
        "Adjustment factor added to the obj function as a PerMWCapInv term to account for PTC payments that do not continue through the entire econ lifetime of a generator.")
    end
    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        # update pol.name column with PTC credit value 
        g = gen[gen_idx, :]
        ref_year = year2float(g[Symbol(pol.ref_year_col)])
        year_min = ref_year + pol.years_after_ref_min
        year_max = ref_year + pol.years_after_ref_max
        g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
        vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
        g[pol.name] = ByYear(vals_tmp)

        # add capex adjustment term to the the pol.name _capex_adj column
        if (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)
            adj_term = get_ptc_capex_adj(pol, g, config)
            g[Symbol("$(pol.name)_capex_adj")] = adj_term
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

    # add the capex adjustment term 
    (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)  && add_obj_term!(data, model, PerMWCapInv(), Symbol("$(pol.name)_capex_adj"), oper = +)
end


"""
    E4ST.modify_results!(pol::PTC, config, data) -> 

Calculates PTC policy cost as a results formula in the gen table. PTC Cost = PTC value * generation 
"""
function E4ST.modify_results!(pol::PTC, config, data)
    # policy cost, PTC value * generation
    add_results_formula!(data, :gen, Symbol("$(pol.name)_cost"), "SumHourly($(pol.name), egen)", Dollars, "The cost of $(pol.name)")
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
    adj_factor = 1 - ((1-(1/(1+r))^age_max)*(1-(1/(1+r))))/((1-(1/(1+r))^e)*(1-(1/(1+r))^(age_min+1)))

    capex_adj = adj_factor .* cf .* ptc_vals
    return capex_adj
end

## We currently require that cf_hist be specified in the gen and build_gen tables but the values below are left as a record of default options. We would actually have to implement this when loading data and/or in the creation of newgens. 

"""
    get_gentype_cf_hist(gentype::AbstractString)

"""
function get_gentype_cf_hist(gentype::AbstractString)
    # default cf are drawn from a previous E4ST run, using the year 2030 with baseline policies including the IRA
    # they could be updated over time and it is much better to specify cf_hist in the gen and build_gen tables
    # E4ST run: OSW 230228, no_osw_build_230228
        gentype == "nuclear" && return 0.92
        gentype == "ngcc" && return 0.58
        gentype == "ngt" && return 0.04 
        gentype == "ngo" && return 0.06 
        gentype == "ngccccs_new" && return 0.55
        gentype == "ngccccs_ret" && return 0.55 # this is set to same as new because no ret was done in the sim
        gentype == "coal" && return 0.68
        gentype == "igcc" && return 0.55 # this is taken from the EIA monthly average coal (in general)
        gentype == "coalccs_new" && return 0.85 # set to same as ret because no new in run
        gentype == "coal_ccus_retrofit" && return 0.85 
        gentype == "solar" && return 0.25
        gentype == "dist_solar" && return 0.25 # set to same as solar
        gentype == "wind" && return 0.4
        gentype == "oswind" && return 0.39 
        gentype == "geothermal" && return 0.77 
        gentype == "deepgeo" && return 0.77 # set to same as geothermal
        gentype == "biomass" && return 0.48 
        #battery, unsure what to do for this but should mostly recieve itc anyways
        gentype == "hyc" && return 0.43 
        gentype == "hyps" && return 0.11 
        gentype == "hyrr" && return 0.39 
        gentype == "oil" && return 0.01 
        # hcc_new, unsure
        # hcc_ret, unsure
        gentype == "other" && return 0.67

        @warn "No default cf_hist provided for $(gentype) in E4ST, setting to 0.35"
        return 0.35 # overall system capacity factor

end
export get_gentype_cf_hist
