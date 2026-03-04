
@doc raw"""
    struct EmissionPrice <: Policy

Emission Price - A price on a certain emission for a given set of generators.

### Keyword Arguments:
* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `prices`: OrderedDict of prices by year. Given as price per unit of emissions (ie. \$/short ton)
* `years_after_ref_min`: Min (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to min gen age. This is rarely used in real policy, so be careful if changing from default value
* `years_after_ref_max`: Max (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to max gen age. This is rarely used in real policy, so be careful if changing from default value
* `ref_year_col`: Column name to use as reference year for min and max above. Must be a year column. If this is :year_on, then the years_after_ref filters will filter gen age. If this is :year_retrofit, the the years_after_ref filters will filter by time since retrofit. This is rarely used in real policy, so be careful if changing from default value
* `gen_filters`: OrderedDict of generator filters
* `hour_filters`: OrderedDict of hour filters
* `bus_filters`: OrderedDict of bus filters
* `import_emis`: Assumption for emissions intensity of imported electricity. Optional value. If not included, there will be no emissions price placed on imports.

### Table Column Added:
* `(:gen, :<name>)` - emissions price per MWh generated for each policy
* `(:gen, :<name>_capex_adj)` - Adjustment factor added to the obj function as a PerMWCapInv term to account for emisprc payments that do not continue through the entire econ lifetime of a generator

### Results Formulas:
* `(:gen, :<name>_cost)` - the cost of the policy 
* `(:gen, :<name>_capex_adj_total)` - The necessary investment-based objective function penalty for having the subsidy end before the economic lifetime.

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
    bus_filters::OrderedDict = OrderedDict()
    import_emis::Union{Float64,Nothing} = nothing
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

    # apply emissions prices to imports if emissions price intensity is provided
    if !isnothing(pol.import_emis)
        @warn "Applying emissions prices to imports, which means the emission cost estimates for the gen table will not be the total cost of $(pol.name). Must consider import costs from branches and/or dc lines as well. "
        bus = get_table(data, :bus)
        branch = get_table(data, :branch)
        
        # get set of buses that emissions price applies to 
        bus_idxs = get_row_idxs(bus, parse_comparisons(pol.bus_filters))
        bus_set = Set(bus_idxs)
        # set up kwarg argments for obj term function
        pflow_col = Symbol("pflow_branch")
        table = :branch

        branch[!,pol.emis_col] .= pol.import_emis  # add emissions intensity column to branch table

        branch_idxs = findall(row -> (row.t_bus_idx in bus_set) ⊻ (row.f_bus_idx in bus_set), eachrow(branch))  # get branch idxs that connect buses that are subject to emissions price and buses outside of emissions price
        
        if length(branch_idxs) > 0 
        
            # get hour weights
            if length(hour_idxs) < nhr
                hour_multiplier = ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr])
            else
                hour_multiplier = ByHour(ones(nhr))
            end

            @info "Applying Emission Price $(pol.name) to imports into $(length(bus_idxs)) busses."
            
            pol_name_imports = Symbol(pol.name, "_imports")
            #create column of Emission prices
            add_table_col!(data, :branch, pol_name_imports, Container[ByNothing(0.0) for i in 1:nrow(branch)], DollarsPerMWhGenerated,
                "Emission price per MWh imported for $(pol.name). Positive values indicate that for this branch, the t_bus is incldued in the policy while gegative values indicate the f_bus is included in the policy.")
            # create column that indicates whether emissions price applies to this branch
            add_table_col!(data, :branch, pol.name, [0 for i in 1:nrow(branch)], NA,
                "Indicator col for $(pol.name)")

            #update emission price column for branch_idx 
            price_yearly = [get(pol.prices, Symbol(year), 0.0) for year in years] #prices for the years in the sim
            # scalar so that imports to relevant buses are positive, and exports are negative, for both t_bus and f_bus
            for branch_idx in branch_idxs
                if branch[branch_idx, :t_bus_idx] in bus_set         # when pflow is positive, t_bus is importing -> set scalar to 1
                    scalar = 1
                elseif branch[branch_idx, :f_bus_idx] in bus_set     # when pflow is negative, f_bus is importing -> set scalar to -1 
                    scalar = -1
                end

                # all years of imports qualify for emissions price
                branch[branch_idx, pol_name_imports] = ByYear(price_yearly) .* branch[branch_idx, pol.emis_col] .* hour_multiplier * scalar #emission rate [st/MWh] * price [$/st] 
                branch[branch_idx, pol.name] = 1    # set indicator column to 1 for this branch
            end
            
            # add imports on branches to the objective function
            add_obj_term!(data, model, PerMWhImport(), pol_name_imports, pol.name, table, pflow_col, oper = +)
        else 
            @warn "There are no relevant branches for $(pol.name). Imports on branches have no emissions price."
        end

        # price emissions from imports on dc lines
        if any(mod -> mod isa DCLine, values(config[:mods]))   # skip if there is no dc lines mod
            dc_line = get_table(data, :dc_line)
            # set up kwarg argments for obj term function
            pflow_col = Symbol("pflow_dc") 
            table = :dc_line

            dc_line[!,pol.emis_col] .= pol.import_emis      # add emissions intensity column to dc line table
        
            dc_idxs = findall(row -> (row.t_bus_idx in bus_set) ⊻ (row.f_bus_idx in bus_set), eachrow(dc_line))  # get ids of dc lines that connect buses that are subject to emissions price and buses outside of emissions price
            
            if length(dc_idxs) > 0 
                pol_name_imports = Symbol(pol.name, "_dc_imports")
                #create column of Emission prices
                add_table_col!(data, :dc_line, pol_name_imports, Container[ByNothing(0.0) for i in 1:nrow(dc_line)], DollarsPerMWhGenerated,
                "Emission price per MWh imported for $(pol.name)")
                # create column that indicates whether emissions price applies to this branch
                add_table_col!(data, :dc_line, pol.name, [0 for i in 1:nrow(dc_line)], NA,
                "Indicator col for $(pol.name)")

                #update column for dc_idx 
                price_yearly = [get(pol.prices, Symbol(year), 0.0) for year in years] #prices for the years in the sim
                # scalar so that imports to relevant buses are positive, and exports are negative, for both t_bus and f_bus
                for dc_idx in dc_idxs
                    if dc_line[dc_idx, :t_bus_idx] in bus_set                # when pflow is positive, t_bus is importing -> set scalar to 1
                        scalar = 1
                    elseif dc_line[dc_idx, :f_bus_idx] in bus_set            # when pflow is negative, f_bus is importing -> set scalar to -1 
                        scalar = -1
                    end

                    # all years of imports qualify for emissions price
                    dc_line[dc_idx, pol_name_imports] = ByYear(price_yearly) .* dc_line[dc_idx, pol.emis_col] .* hour_multiplier * scalar #emission rate [st/MWh] * price [$/st] 
                    dc_line[dc_idx, pol.name] = 1       # set indicator column to 1 for this branch
            

                end
            
                # add imports on dc lines to the objective function
                add_obj_term!(data, model, PerMWhImport(), pol_name_imports, pol.name, table, pflow_col, oper = +)
            else
                 @warn "There are no relevant dc lines for $(pol.name). Imports on dc lines have no emissions price."
            end
        end
   
    end
    
end


"""
    E4ST.modify_results!(pol::EmissionPrice, config, data) -> 
"""
function E4ST.modify_results!(pol::EmissionPrice, config, data)

    # policy cost, price per mwh * generation
    cost_name = Symbol("$(pol.name)_cost")
    add_results_formula!(data, :gen, cost_name, "SumHourlyWeighted($(pol.name), pgen)", Dollars, "The cost of $(pol.name)")
    add_to_results_formula!(data, :gen, :emission_cost, cost_name)

    # policy cost for imports on branches
    branch = get_table(data, :branch)
    pol_name_imports = Symbol(pol.name, "_imports")
    
    if hasproperty(branch, pol_name_imports)
        # ignore exports
        for i in axes(branch,1), y in axes(branch[i,:pflow],1), h in axes(branch[i,:pflow],2)
            if branch[i,:pflow][y,h] * branch[i,pol_name_imports][y,h] < 0
                branch[i,pol_name_imports][y,h] = 0    # neg pflow and pos col value together indicate exports, not imports, at relevant bus and vice versa
            end
        end  
        cost_name = Symbol("$(pol.name)_imports_cost")
        add_results_formula!(data, :branch, cost_name, "SumHourlyWeighted($(pol.name)_imports, pflow)", Dollars, "The cost of $(pol.name) associated with imported emissions.")
        add_results_formula!(data, :branch, :emission_cost, "0", Dollars, "The total cost of imported emissions on branches.")
        add_to_results_formula!(data, :branch, :emission_cost, cost_name)
    end
    
    # policy cost for imports on dc lines
    if any(mod -> mod isa DCLine, values(config[:mods]))  # create emissions price for imports on dc lines
        dc_line = get_table(data, :dc_line)

        if hasproperty(dc_line, pol_name_imports)
            #ignore exports
            pol_name_imports = Symbol(pol.name, "_dc_imports")
            for i in axes(dc_line,1), y in axes(dc_line[i,:pflow],1), h in axes(dc_line[i,:pflow],2)
                if dc_line[i,:pflow][y,h] * dc_line[i,pol_name_imports][y,h] < 0
                    dc_line[i,pol_name_imports][y,h] = 0    # neg pflow and pos col value together indicate exports, not imports, at relevant bus and vice versa
                end
            end  
            cost_name = Symbol("$(pol.name)_imports_cost")
            add_results_formula!(data, :dc_line, cost_name, "SumHourlyWeighted($(pol.name)_imports, pflow)", Dollars, "The cost of $(pol.name) associated with imported emissions.")
            add_results_formula!(data, :dc_line, :emission_cost, "0", Dollars, "The total cost of imported emissions on dc lines.")
            add_to_results_formula!(data, :dc_line, :emission_cost, cost_name)
        end
    end

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
