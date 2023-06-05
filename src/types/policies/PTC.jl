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

    add_table_col!(data, :gen, Symbol("$(pol.name)_capex_adj"), Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity, 
    "Adjustment factor added to the obj function as a PerMWCapInv term to account for PTC payments that do not continue through the entire econ lifetime of a generator.")

    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        # update pol.name column with PTC credit value 
        g = gen[gen_idx, :]
        g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
        vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
        g[pol.name] = ByYear(vals_tmp)

        # add capex adjustment term to the the pol.name _capex_adj column
        adj_term = get_ptc_capex_adj(pol, g, config)
        g[Symbol("$(pol.name)_capex_adj")] = adj_term
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
    add_obj_term!(data, model, PerMWCapInv(), Symbol("$(pol.name)_capex_adj"), oper = +)
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
    r = config[:wacc] #discount rate, using wacc to match generator cost calculations
    e = g.econ_life
    age_max = pol.gen_age_max
    age_min = pol.gen_age_min

    hasproperty(g, :cf_hist) ? (cf = g.cf_hist) : (cf = get_gentype_cf_hist(g.gentype))
    ptc_vals = g[pol.name]

    # This adjustment factor is the geometric formula for the difference between the actual PTC value per MW capacity and a PTC represented as a constant cash flow over the entire economic life. 
    # The derivation of this adj_factor can be found in the PTC documentation
    adj_factor = 1 - ((1-(1/(1+r))^age_max)*(1-(1/(1+r))))/((1-(1/(1+r))^e)*(1-(1/(1+r))^(age_min+1)))

    capex_adj = adj_factor .* cf .* ptc_vals
    return capex_adj
end

"""
    get_gentype_cf_hist(gentype::AbstractString)

"""
function get_gentype_cf_hist(gentype::AbstractString)
    # default cf are drawn from a previous E4ST run, using the year 2030 with baseline policies including the IRA
    # they could be updated over time and it is much better to specify cf_hist in the gen and build_gen tables
    # E4ST run: OSW 230228, no_osw_build_230228
    default_cf = OrderedDict{String, Float64}(
        "nuclear" => 0.92, 
        "ngcc" => 0.58,
        "ngt" => 0.04, 
        "ngo" => 0.06, 
        "ngccccs_new" => 0.55, 
        "ngccccs_ret" => 0.55, # this is set to same as new because no ret was done in the sim
        "coal" => 0.68, 
        "igcc" => 0.55, # this is taken from the EIA monthly average coal (in general)
        "coalccs_new" => 0.85, # set to same as ret because no new in run
        "coal_ccus_retrofit" => 0.85, 
        "solar" => 0.25, 
        "dist_solar" => 0.25, # set to same as solar
        "wind" => 0.4, 
        "oswind" => 0.39, 
        "geothermal" => 0.77, 
        "deepgeo" => 0.77, # set to same as geothermal
        "biomass" => 0.48, 
        #battery, unsure what to do for this but should mostly recieve itc anyways
        "hyc" => 0.43, 
        "hyps" => 0.11, 
        "hyrr" => 0.39, 
        "oil" => 0.01, 
        # hcc_new, unsure
        # hcc_ret, unsure
        "other" => 0.67
    )
    return default_cf[gentype]
end