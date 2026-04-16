
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
* `price_imports`: Bool that indicates if emissions price applies to imported power. Optional value, defaults to false. If this is true but no emissions factors are provided, will default to the emissions intensity of ng.
* `import_ef`: Single emissions factor for imported power in all regions and hours. Optional, defaults to ng emissions intensity.
* `import_ef_file`: File that contains emissions factors of imported power by region and hour. Optional.

### Table Column Added:
* `(:gen, :<name>)` - emissions price per MWh generated for each policy
* `(:gen, :<name>_capex_adj)` - Adjustment factor added to the obj function as a PerMWCapInv term to account for emisprc payments that do not continue through the entire econ lifetime of a generator
* `(:branch, :<name>)` - emissions price per MWh generated for each policy due to imports on branches
* `(:branch, :<name>_imports)` - Bool column that indicates which branches the EmissionPrice applies to. Also the name of the corresponding obj_var.
* `(:dc_line, :<name>)` - emissions price per MWh generated for each policy due to imports on dc lines
* `(:dc_line, :<name>_dc_imports)` - Bool column that indicates which branches the EmissionPrice applies to. Also the name of the corresponding obj_var.

### Results Formulas:
* `(:gen, :<name>_cost)` - the cost of the policy, excluding imports
* `(:gen, :<name>_capex_adj_total)` - The necessary investment-based objective function penalty for having the subsidy end before the economic lifetime.
* `(:branch, :<name>_cost)` - the cost of imports on branches for the policy
* `(:dc_line, :<name>_cost)` - the cost of imports on dc lines for the policy

"""
struct EmissionPrice <: Policy
    name::Symbol
    emis_col::Symbol
    prices::OrderedDict
    years_after_ref_min::Float64
    years_after_ref_max::Float64
    ref_year_col::String
    gen_filters::OrderedDict
    hour_filters::OrderedDict
    bus_filters::OrderedDict
    price_imports::Bool
    import_ef::Union{Float64, Nothing}
    import_ef_file::Union{String,Nothing}

    function EmissionPrice(; name, emis_col, prices, years_after_ref_min=0.0, years_after_ref_max=9999.0, ref_year_col="year_on", gen_filters=OrderedDict(), hour_filters=OrderedDict(), bus_filters=OrderedDict(), price_imports=false, import_ef=nothing, import_ef_file=nothing)
        if price_imports && isempty(bus_filters)
            @warn "EmissionPrice $(name) has price_imports=true but no bus_filters specified — no import branches will be found."
        end
        if price_imports && import_ef === nothing && import_ef_file === nothing
            emis_col == "emis_co2" || error("EmissionPrice $(name) has price_imports=true but no import emissions factor was provided and there is no default for $(emis_col)")
            import_ef = 0.428
            @warn "EmissionPrice $(name) has price_imports=true but no emissions factors were provided. The default ng emissions factor (0.428) will be applied to all imports."
        elseif price_imports && import_ef !== nothing && import_ef_file !== nothing
            error("EmissionPrice $(name) has both import_ef and import_ef_file specified. Provide only one.")
        elseif !price_imports && (import_ef !== nothing || import_ef_file !== nothing)
            @warn "EmissionPrice $(name) has price_imports=false but emission factors were provided. Imports will not be priced."
        end
        return new(Symbol(name), Symbol(emis_col), OrderedDict(prices), years_after_ref_min, years_after_ref_max, ref_year_col, OrderedDict(gen_filters), OrderedDict(hour_filters), OrderedDict(bus_filters), price_imports, import_ef, import_ef_file)
    end
end
export EmissionPrice


function should_adjust_invest_cost(pol::EmissionPrice)
    return (pol.years_after_ref_min != 0.0 || pol.years_after_ref_max != 9999.0)
end

function E4ST.modify_raw_data!(pol::EmissionPrice, config, data)
    if !isnothing(pol.import_ef_file)
        data[pol.name] = read_table(data, pol.import_ef_file, pol.name)
    end
end

function E4ST.modify_setup_data!(pol::EmissionPrice, config, data)
    pol.price_imports || return

    @warn "Applying emissions prices to imports for $(pol.name); emission cost estimates for the gen table will not include import costs."

    tag_import_branches!(pol, config, data, :branch)

    if any(mod -> mod isa DCLine, values(config[:mods]))
        tag_import_branches!(pol, config, data, :dc_line)
    end
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
    # hour multiplier set to 1 for hours included in the EmissionPrice policy, 0 for hours without an emission price
    hour_multiplier = length(hour_idxs) < nhr ? ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr]) : ByNothing(1.0)

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

    # add objective terms for imports if price_imports is true (columns already set up in modify_setup_data!)
    if pol.price_imports
        _add_import_obj_term!(data, model, pol, :branch)
        if any(mod -> mod isa DCLine, values(config[:mods]))
            _add_import_obj_term!(data, model, pol, :dc_line)
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

    branch = get_table(data, :branch)
    pol_name_imports = Symbol("$(pol.name)_imports")
    if hasproperty(branch, pol_name_imports)
        zero_exports!(branch, pol_name_imports) # set col to zero for rows with exports so that they are not priced
        add_import_costs!(data, :branch, pol, pol_name_imports, Symbol("$(pol.name)_import_cost"))
    end

    pol_name_imports = Symbol("$(pol.name)_dc_imports")
    if any(mod -> mod isa DCLine, values(config[:mods]))
        dc_line = get_table(data, :dc_line)
        if hasproperty(dc_line, pol_name_imports)
            zero_exports!(dc_line, pol_name_imports) # set col to zero for rows with exports so that they are not priced
            add_import_costs!(data, :dc_line, pol, pol_name_imports, Symbol("$(pol.name)_import_cost"))
        end
    end

    should_adjust_invest_cost(pol) && add_results_formula!(data, :gen, Symbol("$(pol.name)_capex_adj_total"), "SumYearly(ecap_inv_sim, $(pol.name)_capex_adj)", Dollars, "The necessary investment-based objective function penalty for having the subsidy end before the economic lifetime.")
end

"""
    add_import_costs!(data, table, pol::EmissionPrice, col::Symbol, cost_sym::Symbol) ->
    Create results formulas that find the cost of importing power due to the specific policy in the branch or dc_line tables and add the result to a total cost for imported power due to EmissionPrice policies.
"""
function add_import_costs!(data, table, pol::EmissionPrice, col::Symbol, cost_sym::Symbol)
    add_results_formula!(data, table, cost_sym, "SumHourlyWeighted($(col), pflow)",
                            Dollars, "The cost of $(pol.name) associated with imported emissions.")
    haskey(get_results_formulas(data), (table, :emission_cost)) ||
        add_results_formula!(data, table, :emission_cost, "0", Dollars,
                            "The total cost of imported emissions for $(table).")
    add_to_results_formula!(data, table, :emission_cost, cost_sym)
end

"""
    zero_exports!(table, col::Symbol) ->
    Search in the branch and dc line tables for rows where power is being exported out of the EmissionPrice region. In these cases, set the emission price per MWh to 0 so that the emissions price won't be applied to exports.
"""
function zero_exports!(table, col::Symbol)
    for i in axes(table,1), y in axes(table[i,:pflow],1), h in axes(table[i,:pflow],2)
        if table[i,:pflow][y,h] * table[i,col][y,h] < 0
            table[i,col][y,h] = 0
        end
    end
end

function tag_import_branches!(pol::EmissionPrice, config, data, table_name::Symbol)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    bus_idxs = get_row_idxs(bus, parse_comparisons(pol.bus_filters))
    bus_set = Set(bus_idxs)

    hours = get_table(data, :hours)
    nhr = get_num_hours(data)
    hour_idxs = get_row_idxs(hours, parse_comparisons(pol.hour_filters))
    hour_multiplier = length(hour_idxs) < nhr ? ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr]) : ByHour(ones(nhr))

    years = get_years(data)
    import_emis_col = Symbol("$(pol.name)_$(pol.emis_col)")
    pol_name_imports = Symbol(pol.name, table_name == :branch ? "_imports" : "_dc_imports")  # suffix added to pol.name in branch/dc_line table to prevent duplicative obj_vars in add_obj_term

    # pol_name_imports: price per MWh of imports (ByYear * emis_col * hour_multiplier * scalar), 0 for non-qualifying branches
    add_table_col!(data, table_name, import_emis_col, Container[ByNothing(0.0) for _ in 1:nrow(table)], DollarsPerMWhGenerated,
        "Emissions factor of imported power on $(table_name) for $(pol.name)")
    add_table_col!(data, table_name, pol_name_imports, Container[ByNothing(0.0) for _ in 1:nrow(table)],
        DollarsPerMWhGenerated, "Emission price per MWh imported for $(pol.name)")

    if !isnothing(pol.import_ef_file)
        _tag_import_branches_by_file!(pol, data, table_name, bus_set, import_emis_col, pol_name_imports, hour_multiplier, years)
    else
        _tag_import_branches_by_value!(pol, data, table_name, bus_set, import_emis_col, pol_name_imports, hour_multiplier, years)
    end
end

"""
Single emissions factor: assign pol.import_ef to all branches crossing the price region boundary.
"""
function _tag_import_branches_by_value!(pol::EmissionPrice, data, table_name, bus_set, import_emis_col, pol_name_imports, hour_multiplier, years)
    table = get_table(data, table_name)
    idxs = findall(row -> (row.t_bus_idx in bus_set) ⊻ (row.f_bus_idx in bus_set), eachrow(table))
    if isempty(idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports have no emissions price."
        return
    end
    table[idxs, import_emis_col] .= pol.import_ef
    price_yearly = [get(pol.prices, Symbol(y), 0.0) for y in years]
    for idx in idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol_name_imports] = ByYear(price_yearly) .* table[idx, import_emis_col] .* hour_multiplier .* scalar
    end
    @info "Applied EmissionPrice $(pol.name) to $(length(idxs)) $(table_name)."
end

"""
Region- and hour-varying emissions factors from a file. Each row of the ef table defines a source
region (via its column values used as bus filters) and the hourly EFs for that region. Branches
are tagged per source region so each gets the correct EF container.
"""
function _tag_import_branches_by_file!(pol::EmissionPrice, data, table_name, bus_set, import_emis_col, pol_name_imports, hour_multiplier, years)
    pol_table = data[pol.name]
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    hr_col_start = findfirst(s -> s == "h1", names(pol_table))
    nhr = get_num_hours(data)
    all_idxs = Int[]

    for sa in unique(pol_table.subarea)
        sa_table = pol_table[pol_table.subarea .== sa, :]

        row_idxs = get_row_idxs(bus, parse_comparisons(sa_table[1, :]))
        row_set = Set(row_idxs)
        idxs = findall(
            row -> (row.t_bus_idx in bus_set && row.f_bus_idx in row_set) ⊻
                   (row.f_bus_idx in bus_set && row.t_bus_idx in row_set),
            eachrow(table)
        )
        isempty(idxs) && continue

        # build EF container — ByYearAndHour if the file has a year column, ByHour otherwise
        if hasproperty(pol_table, :year)
            pol_years = [y for y in years if y in string.(collect(keys(pol.prices)))]
            ef_years = unique(sa_table.year)
            if !all(in(ef_years), pol_years)
                @warn "The ef table for $(sa) is missing years required by $(pol.name). There will be no emission price on imported power from region $(sa)."
                continue
            end
            efs = ByYearAndHour(zeros(length(years), nhr))
            for (yr_idx, year) in enumerate(years)
                rows = sa_table[sa_table.year .== year, :]
                isempty(rows) && continue
                nrow(rows) > 1 && @warn "Multiple rows for $(sa) $(year) in $(pol.name). Using first."
                efs[yr_idx] = [rows[1, hr] for hr in hr_col_start:(hr_col_start + nhr - 1)]
            end
        else
            nrow(sa_table) > 1 && @warn "Multiple rows for $(sa) in $(pol.name). Using first."
            efs = ByHour(Float64[sa_table[1, hr] for hr in hr_col_start:(hr_col_start + nhr - 1)])
        end
        table[idxs, import_emis_col] .= Ref(efs)
        append!(all_idxs, idxs)
    end

    if isempty(all_idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports have no emissions price."
        return
    end

    price_yearly = [get(pol.prices, Symbol(y), 0.0) for y in years]
    for idx in all_idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol_name_imports] = ByYear(price_yearly) .* table[idx, import_emis_col] .* hour_multiplier .* scalar
    end
    @info "Applied EmissionPrice $(pol.name) to $(length(all_idxs)) $(table_name)."
end

"""
    _add_import_obj_term!(data, model, pol::EmissionPrice, table_name::Symbol)

Adds the objective term for import emissions pricing. Called from modify_model!.
Columns must already exist on the table (set up by modify_setup_data!).
"""
function _add_import_obj_term!(data, model, pol::EmissionPrice, table_name::Symbol)
    table = get_table(data, table_name)
    pol_name_imports = Symbol(pol.name, table_name == :branch ? "_imports" : "_dc_imports")
    hasproperty(table, pol_name_imports) || return
    any(c -> any(!iszero, c), getproperty(table, pol_name_imports)) || return
    pflow_col = table_name == :branch ? :pflow_branch : :pflow_dc
    add_obj_term!(data, model, PerMWhImport(), pol_name_imports, table_name, pflow_col, oper = +)  
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
