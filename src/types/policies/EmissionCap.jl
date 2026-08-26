

@doc raw"""
    struct EmissionCap <: Policy

Emission Cap - A limit on a certain emission for a given set of generators. The mod caps emissions by setting up a generation constraint, which uses the given emissions rate column to determine the generation limit. The allowance price is equal
to the shadow price of the generation constraint, or the sum of shadow prices across years when banking is allowed, which is used to evaluate the cost of the policy. There is an option for price responsive allowances which features a structured 
allowance supply curve with multiple price-quantity steps serving different market functions.
Note: The banking formulation in this modification requires that years[n] - years[n-1] is constant.

### Keyword Arguments:
* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `targets`: OrderedDict of cap targets by year
* `gen_filters`: OrderedDict of generator filters
* `hour_filters`: OrderedDict of hour filters
* `bus_filters`: OrderedDict of bus filters
* `cap_imports`: Bool that indicates if emissions cap applies to imported power. Optional value, defaults to false. If this is true but no emissions factors are provided, will default to the emissions intensity of ng.
* `import_ef`: Single emissions factor for imported power in all regions and hours. Optional, defaults to ng emissions intensity.
* `import_ef_file`: File that contains emissions factors of imported power by region and hour. Optional.
* `banking`: Bool that indicates if emissions banking is allowed across years. When true, the constraint is cumulative: the sum of emissions from the first cap year through each year must be ≤ the sum of caps over those years plus `initial_bank`. Defaults to false.
* `initial_bank`: Initial allowance bank (in the same units as targets) available at the start of the first cap year. Only used when `banking=true`. Defaults to 0.0.
* `offset`: The amount of offsets allowed, represented as a percentage. The factor represents a limit on the use of offsets as a fraction of the entity's compliance obligation. Defaults to 0.
* `offset_under_cap`: Bool that indicates whether offsets are under or outside the emission cap, defaults to true. 
* `price_resp_alws`: Bool that turns on price responsive allowances, defaults to false.
* `step_prices`: Length-k vector of prices for each step.
* `step_adders`: Length-k vector of allowance quantities added to (positive) or withdrawn from (negative) the base target at each price step, which defines the cumulative supply available at step k. When representing a price ceiling, include a backstop step with Inf allowances.
* `rate`: The rate step prices increase by each year. Defaults to 5%. Prices escalate relative to the first year that has a target.

### Table Column Added:
Naming note: In this mod, the `<name>`` column is used to indicate which gens/branches/dc lines qualify under the cap, and the `<name>_prc`` column records the allowance price of policy which is unknown until after model solve. This is the same convention used by other post-solve-shadow-price policies (`GenerationStandard`, `ReserveRequirement`). 
It differs from policies with an exogenous input price (e.g. [`EmissionPrice`](@ref), [`PTC`](@ref), [`ITC`](@ref)), where the`<name>` column holds the `$`/MWh value directly.
* `(:gen, :<name>)` - Indicator marking whether the gen's emissions count toward the cap.
* `(:gen, :<name>_prc)` - the allowance price of the policy converted to DollarsPerMWhGenerated
* `(:branch, :<name>)` - Same indicator as `(:gen, :<name>)`, for branches that cross into the capped region. Only added when `cap_imports=true`.
* `(:dc_line, :<name>)` - Same indicator as `(:gen, :<name>)`, for dc_lines that cross into the capped region. Only added when `cap_imports=true`.
* `(:branch, :<name>_dir)` - Signed direction scalar: +1 if `t_bus_idx` is in the capped region, -1 if `f_bus_idx` is. Only added when `cap_imports=true`.
* `(:dc_line, :<name>_dir)` - Signed direction scalar: +1 if `t_bus_idx` is in the capped region, -1 if `f_bus_idx` is. Only added when `cap_imports=true`.
* `(:branch, :<name>_<emis_col>)` - Emissions factor of imported power (e.g. `<name>_emis_co2`). Only added when `cap_imports=true`.
* `(:dc_line, :<name>_<emis_col>)` - Emissions factor of imported power (e.g. `<name>_emis_co2`). Only added when `cap_imports=true`.
* `(:branch, :<name>_flag)` - Sign of realized import flow direction, nonzero only where `pflow * <name>_dir > 0`; used to isolate import flows in results formulas. Only added when `cap_imports=true`.
* `(:dc_line, :<name>_flag)` - Sign of realized import flow direction, nonzero only where `pflow * <name>_dir > 0`; used to isolate import flows in results formulas. Only added when `cap_imports=true`.
* `(:branch, :<name>_prc)` - the allowance price of the policy per MWh of imports. Only added when `cap_imports=true`.
* `(:dc_line, :<name>_prc)` - the allowance price of the policy per MWh of imports. Only added when `cap_imports=true`.
* `(:bus, :<name>_import_cost)` - Cost of the policy attributed to imports, allocated to the importing bus (`ByYearAndHour`). Only added when `cap_imports=true`.

### Results Formula:
* `(:gen, :<name>_cost)` - the cost of the policy based on the allowance price, determined using the shadow price of the generation constraint
* `(:branch, :<name>_import_cost)` - the cost of the policy attributed to imports. Only added when `cap_imports=true`.
* `(:dc_line, :<name>_import_cost)` - the cost of the policy attributed to imports. Only added when `cap_imports=true`.
* `(:branch, :<name>_import_emis)` - Total emissions from imported power. Only added when `cap_imports=true`.
* `(:dc_line, :<name>_import_emis)` - Total emissions from imported power. Only added when `cap_imports=true`.
* `(:bus, :<name>_import_cost_total)` - Total cost of the policy attributed to imports, allocated to buses. Only added when `cap_imports=true`.

"""
struct EmissionCap <: Policy
    name::Symbol
    emis_col::Symbol
    targets::OrderedDict{Symbol, Float64}
    gen_filters::OrderedDict
    hour_filters::OrderedDict
    bus_filters::OrderedDict
    cap_imports::Bool
    import_ef::Float64
    import_ef_file::String
    banking::Bool
    initial_bank::Float64
    offset::Float64
    offset_under_cap::Bool
    price_resp_alws::Bool
    step_prices::Vector{Float64}
    step_adders::Vector{Float64}
    rate::Float64

    function EmissionCap(;name, emis_col, targets, gen_filters=OrderedDict(), hour_filters=OrderedDict(), bus_filters=OrderedDict(), cap_imports=false, import_ef=0.0, import_ef_file="", banking=false, initial_bank=0.0, offset=0, offset_under_cap=true,
        price_resp_alws = false, step_prices = Float64[], step_adders = Float64[], rate = 0.05)
        if cap_imports && isempty(bus_filters)
            @warn "EmissionCap $(name) has cap_imports=true but no bus_filters specified — no import branches will be found."
        end
        if cap_imports && import_ef == 0.0 && isempty(import_ef_file)
            emis_col == "emis_co2" || error("EmissionCap $(name) has cap_imports=true but no import emissions factor was provided and there is no default for $(emis_col)")
            import_ef = 0.428
            @warn "EmissionCap $(name) has cap_imports=true but no emissions factors were provided. The default ng emissions factor (0.428) will be applied to all imports."
        elseif cap_imports && import_ef != 0.0 && !isempty(import_ef_file)
            error("EmissionCap $(name) has both import_ef and import_ef_file specified. Provide only one.")
        elseif !cap_imports && (import_ef != 0.0 || !isempty(import_ef_file))
            @warn "EmissionCap $(name) has cap_imports=false but emission factors were provided. Imports will not be counted toward the cap."
        end
        if price_resp_alws && (isempty(step_prices) || isempty(step_adders))
            error("Emission cap $(name) has price_resp_alws=true but one or more relevant kwargs were left empty")
        elseif price_resp_alws && length(step_prices) != length(step_adders)
            error("The step_prices and step_adders are not equal length for Emission cap $(name), which will error when setting up the allowance supply price curve.")
        elseif price_resp_alws == false && (!isempty(step_prices) || !isempty(step_adders))
            @warn "Emission cap $(name) has price_resp_alws=false, and the allowance supply curve will not be included in the formulation, but one or more relevant kwargs have values."
        end
        new(Symbol(name), Symbol(emis_col), OrderedDict{Symbol, Float64}(targets), OrderedDict(gen_filters), OrderedDict(hour_filters), OrderedDict(bus_filters), cap_imports, import_ef, import_ef_file, banking, initial_bank, offset, offset_under_cap,
        price_resp_alws, step_prices, step_adders, rate)
    end

end

export EmissionCap

"""
    _emiscap_colnames(pol::EmissionCap) -> NamedTuple

Returns a NamedTuple of all derived column/result Symbol names for an EmissionCap policy.
"""
function _emiscap_colnames(pol::EmissionCap)
    return (
        prc                = Symbol("$(pol.name)_prc"),
        cost               = Symbol("$(pol.name)_cost"),
        import_cost        = Symbol("$(pol.name)_import_cost"),
        import_emis        = Symbol("$(pol.name)_$(pol.emis_col)"),
        flag               = Symbol("$(pol.name)_flag"),
        import_emis_result = Symbol("$(pol.name)_import_emis"),
        dir                = Symbol("$(pol.name)_dir"),
        cons_name          = Symbol("cons_$(pol.name)_max"),
        alw_name           = Symbol("alw_$(pol.name)"),
        alw_cost           = Symbol("alw_cost_$(pol.name)"),
        price_resp_alws        = Symbol("$(pol.name)_supply_curve")
    )
end


function summarize_table(::Val{:import_ef_file})
    df = TableSummary()
    push!(df, 
        (:area, String, NA, true, "The area the ef value applies to. I.e. \"state\". Leave blank to apply grid-wide."),
        (:subarea, String, NA, true, "The subarea that ef value applies to. Leave blank to apply grid-wide"),
        (:year, String, NA, false, "The year the ef values correspond to. Include a row for each model year for each region. Optional column. When not included, the same ef values will be applied in each year."),
        (:h_, Float64, Ratio, true, "The ef of the imported power.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, etc"),
    )
    return df
end

function E4ST.modify_raw_data!(pol::EmissionCap, config, data)
    if !isempty(pol.import_ef_file)
        data[pol.name] = read_table(data, pol.import_ef_file, pol.name)
    end
end

function E4ST.modify_setup_data!(pol::EmissionCap, config, data)
    pol.price_resp_alws && setup_allowance_price_resp_alws(pol, config, data)  # store price steps

    pol.cap_imports || return  # check if pol.cap_imports is set to true

    # tag the branches and dc lines that import power into regions subject to emission cap
    setup_import_branches!(pol, config, data, :branch)

    if any(mod -> mod isa DCLine, values(config[:mods]))
        setup_import_branches!(pol, config, data, :dc_line)
    end
end


"""
    E4ST.modify_model!(pol::EmissionCap, config, data, model)

Calls [`modify_model!(cons::GenerationConstraint, config, data, model)`](@ref)
"""

function E4ST.modify_model!(pol::EmissionCap, config, data, model)
    cols = _emiscap_colnames(pol)

    # track emissions from generation
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters)) # get gens that this policy applies to
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    pgen_gen = model[:pgen_gen]::Array{VariableRef, 3}

    hours = get_table(data, :hours)
    hour_idxs = get_row_idxs(hours, parse_comparisons(pol.hour_filters))
    hour_weights = get_hour_weights(data)
    hour_multiplier = length(hour_idxs) < nhr ? ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr]) : ByNothing(1.0)

    # indicator column: ByHour when hour_filters apply (0 for excluded hours), ByNothing(1) otherwise, 0 for non-qualifying gens
    # encodes both gen membership and hour filtering; used in the emissions expression and modify_results!
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for _ in 1:nrow(gen)], NA,
        "Indicator for whether gen is subject to $(pol.name), ByHour when hour_filters apply")
    for gen_idx in gen_idxs
        gen[gen_idx, pol.name] = hour_multiplier
    end

     # setup expression that sums emissions from all sources regulated by the policy
    emis_expr_name = Symbol("emis_total_$(pol.name)")  # set up expression name for policy
    model[emis_expr_name] = @expression(model,
        [yr_idx in 1:nyr, hr_idx in 1:nhr],
        hour_weights[hr_idx] * sum(
            pgen_gen[gen_idx, yr_idx, hr_idx] *
            get_table_num(data, :gen, pol.name, gen_idx, yr_idx, hr_idx) *
            get_table_num(data, :gen, pol.emis_col, gen_idx, yr_idx, hr_idx)
            for gen_idx in gen_idxs
        )
    )

    # add emissions from imports to expression if pol.cap_imports == true
    if pol.cap_imports == true
        setup_imports!(pol, config, data, model, :branch)
        if any(mod -> mod isa DCLine, values(config[:mods]))
            setup_imports!(pol, config, data, model, :dc_line)
        end
    end

    # set up emissions cap constraint
    years = Symbol.(get_years(data))
    cap_years = collect(keys(pol.targets))
    filter!(in(years), cap_years)
    offset_adjust = pol.offset_under_cap == false ? pol.offset : 0.0  # only loosen the cap if offsets are outside it

    # add price responsive allowances to the model
    if pol.price_resp_alws
        add_price_responsive_allowances(pol, config, data, model)
        nsteps = length(pol.step_prices)
        alw = model[cols.alw_name]
    end
    

    cap_cons_name = cols.cons_name
    @info "Creating emissions cap constraint for $(pol.name) in years $(cap_years)"
    if pol.banking
        # Cumulative constraint: sum of emissions from the first cap year through yr_idx
        # must be ≤ sum of targets over those years + initial_bank

       model[cap_cons_name] = @constraint(model,
            [yr_idx in 1:nyr; years[yr_idx] in cap_years],
            sum(
                model[emis_expr_name][y_idx, hr_idx]
                for y_idx in 1:nyr, hr_idx in 1:nhr
                if years[y_idx] in cap_years && years[y_idx] <= years[yr_idx]
            ) <= (
                (
                    pol.price_resp_alws ?
                    sum(
                        alw[y_idx, s]
                        for y_idx in 1:nyr, s in 1:nsteps
                        if years[y_idx] in cap_years && years[y_idx] <= years[yr_idx]
                    ) :
                    sum(pol.targets[y] for y in cap_years if y <= years[yr_idx])
                ) + pol.initial_bank
            ) / (1 - offset_adjust)
        )
    else

        model[cap_cons_name] = @constraint(model,
            [yr_idx in 1:nyr; years[yr_idx] in cap_years],
            sum(model[emis_expr_name][yr_idx, hr_idx] for hr_idx in 1:nhr) <=
            (pol.price_resp_alws ?
                sum(alw[yr_idx, s] for s in 1:nsteps) :
                pol.targets[years[yr_idx]]
            ) / (1 - offset_adjust)

        )
    end

end


"""
    E4ST.modify_results!(pol::EmissionCap, config, data) ->
"""
function E4ST.modify_results!(pol::EmissionCap, config, data)
    gen = get_table(data, :gen)
    cols = _emiscap_colnames(pol)

    cons_name = cols.cons_name 
    haskey(data[:results][:raw], cons_name) || return

    alw_prc = get_shadow_price_as_ByYear(data, cons_name) #($/EmissionsUnit)

    # the cumulative banking formulation means that each unit of emissions emitted in year y tightens the constraint in future years
    # that means allowance price is the sum of shadow prices on the affected constraints

    if pol.banking
        # With year-specific objective scaling, the correct emission price for year y is:
        # allowance_price[y] = (sum_{T >= y} λ_T_scaled) / (yr_scalar[y])
        # get_shadow_price_as_ByYear returns λ_T_scaled / yr_scalar[T],
        # so we first multiply λ_T_scaled = shadow_prc_as_byyear[T] * yr_scalar[T].
    
        yr_scalars = config[:yearly_objective_scalars]::Vector{Float64}
        years = Symbol.(get_years(data))
        nyr = get_num_years(data)
        cap_years = collect(keys(pol.targets))

        # recover raw scaled shadow prices: λ_T_scaled = returned_value * yr_scalar[T] 
        lambda_scaled = [alw_prc[t_idx] * yr_scalars[t_idx] for t_idx in 1:nyr]
        
        alw_prc = ByYear(zeros(nyr))
        for y_idx in 1:nyr
            years[y_idx] in cap_years || continue  # no compliance obligation, and thus no allowance price, outside cap years
            alw_prc[y_idx] = sum(
                lambda_scaled[t_idx]
                for t_idx in 1:nyr
                if years[t_idx] in cap_years && years[t_idx] >= years[y_idx];
                init=0.0
            ) / (yr_scalars[y_idx])
        end

        data[:results][cons_name] = alw_prc   # replace the shadow price of constraint with allowance price 
    end
   
    prc_col = [(-alw_prc) .* g[pol.name] .* g[pol.emis_col] for g in eachrow(gen)] #($/MWh Generated)
    add_table_col!(data, :gen, cols.prc, prc_col, DollarsPerMWhGenerated, "Allowance price of $(pol.name) converted to DollarsPerMWhGenerated")

    add_results_formula!(data, :gen, cols.cost, "SumHourlyWeighted($(cols.prc), pgen)*(1-pol.offset)", Dollars, "The cost of $(pol.name) based on the allowance price, which is determined with the shadow price of the generation constraint")
    add_to_results_formula!(data, :gen, :emission_cap_cost, cols.cost)

    if pol.cap_imports
        for table_name in (:branch, :dc_line)
            table_name == :dc_line && !any(mod -> mod isa DCLine, values(config[:mods])) && continue
            tag_import_flows!(pol, data, table_name)
            add_import_results!(data, table_name, pol, cols, alw_prc)
        end
    end
end

"""
    add_cap_import_results!(data, table_name, pol::EmissionCap, cols, alw_prc)

Creates results formulas for import cost attributed to an EmissionCap for the given table.
"""
function add_import_results!(data, table_name, pol::EmissionCap, cols, alw_prc)
    table = get_table(data, table_name)
    hasproperty(table, pol.name) || return

    prc_col = [(-alw_prc) .* row[pol.name] .* row[cols.import_emis] for row in eachrow(table)]
    add_table_col!(data, table_name, cols.prc, prc_col, DollarsPerMWhGenerated,
        "Allowance price of $(pol.name) per MWh of imports on $(table_name)")

    # results formula for cost of emission cap policy contributed by imports
    add_results_formula!(data, table_name, cols.import_cost, "SumHourlyWeighted($(cols.prc), pflow)*(1-pol.offset)",
        Dollars, "The cost of $(pol.name) attributed to imports on $(table_name). Import costs have also been allocated to the corresponding busses in the bus table's emission_cap_cost result formula.")
    # setup a results formula to track total cost of all emission cap policies for imported power
    haskey(get_results_formulas(data), (table_name, :emission_cap_cost)) ||
        add_results_formula!(data, table_name, :emission_cap_cost, "0", Dollars,
            "Cost attributed to imports for all emission caps on $(table_name). Import costs have aslo been allocated to the corresponding busses in the bus table's emission_cap_cost result formula")
    add_to_results_formula!(data, table_name, :emission_cap_cost, cols.import_cost)

    # attribute the import cost to the importing bus, so that it can be aggregated/filtered by
    # any area available on the bus table (e.g. state) - branch/dc_line rows span two areas and
    # have no area columns of their own.
    add_import_cost_to_bus!(data, table_name, pol, cols, prc_col)

    # results formula to track associated emissions from imported power
    if pol.emis_col == "emis_co2"
        unit = ShortTons
    else
        unit = Pounds
    end
    add_results_formula!(data, table_name, cols.import_emis_result, "SumHourlyWeighted($(cols.import_emis), (pflow .* $(cols.flag)))", unit, "Total emissions from imported power under $(pol.name). Note the imported emissions are calculated using the exogenous ef inputs and do not reflect the actual ef of the model run.")
end

"""
    add_import_cost_to_bus!(data, table_name, pol::EmissionCap, cols, prc_col)

Allocates the per-row import cost computed in [`add_import_results!`](@ref) (using the same
per-row price container `prc_col`) onto the importing bus,which is the endpoint inside the capped
region (`t_bus_idx` when `dir > 0`, `f_bus_idx` when `dir < 0`). This mirrors how branch-level
merchandising surplus is allocated to buses in `parse_lmp_results!`. This is necessary to compute
results like retail price at the state level, since the branch and dc line table have no area
columns. 
"""
function add_import_cost_to_bus!(data, table_name, pol::EmissionCap, cols, prc_col)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hour_weights = get_hour_weights(data)

    bus_cost_col = Symbol("$(pol.name)_import_cost")
    bus_cost_total = Symbol("$(pol.name)_import_cost_total")
    if !hasproperty(bus, bus_cost_col)
        add_table_col!(data, :bus, bus_cost_col, Container[ByYearAndHour(zeros(nyr, nhr)) for _ in 1:nrow(bus)], Dollars,
            "Cost of $(pol.name) attributed to imports, allocated to the importing bus.")
        add_results_formula!(data, :bus, bus_cost_total, "SumHourly($(bus_cost_col))", Dollars,
            "Total cost of $(pol.name) attributed to imports, allocated to buses.")
        haskey(get_results_formulas(data), (:bus, :emission_cap_cost)) ||
            add_results_formula!(data, :bus, :emission_cap_cost, "0", Dollars,
                "Cost attributed to imports for all emission caps, allocated to buses.")
        add_to_results_formula!(data, :bus, :emission_cap_cost, bus_cost_total)
    end

    for (row_idx, row) in enumerate(eachrow(table))
        dir = row[cols.dir]
        dir == 0 && continue
        bus_idx = dir > 0 ? row[:t_bus_idx] : row[:f_bus_idx]
        prc = prc_col[row_idx]
        for y in 1:nyr, h in 1:nhr
            bus[bus_idx, bus_cost_col][y,h] += hour_weights[h] * prc[y,h] * row[:pflow][y,h] * (1-pol.offset)
        end
    end
end

"""
    tag_import_flows!(table, col::Symbol) ->
    Tag rows in branch or dc line tables where power is imported into the EmissionCap region..
"""

function tag_import_flows!(pol, data, table_name)
    table = get_table(data, table_name)
    cols = _emiscap_colnames(pol)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    add_table_col!(data, table_name, cols.flag, Container[ByYearAndHour(zeros(nyr,nhr)) for i in 1:nrow(table)], NA,
                "Indicates pflow in $(table_name) table is covered by $(pol.name).")
    for i in axes(table,1), y in axes(table[i,:pflow],1), h in axes(table[i,:pflow],2)   # search for rows where pol col times pflow is greater than 0, which indicates the power line 1) transfers power with policy region 2) and is importing power in the y,h combination
        if table[i,:pflow][y,h] * table[i,cols.dir][y,h] > 0
            table[i,cols.flag][y,h] = 1 * table[i,cols.dir][y,h]
        end
    end
end

"""
    setup_import_branches!(pol::EmissionCap, config, data, table_name) -> 
    Function that identifies the branches and dc_lines that import power into the region/s covered by the EmissionCap.
"""

function setup_import_branches!(pol, config, data, table_name::Symbol)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    bus_idxs = get_row_idxs(bus, parse_comparisons(pol.bus_filters))
    bus_set = Set(bus_idxs)

    hours = get_table(data, :hours)
    nhr = get_num_hours(data)
    hour_idxs = get_row_idxs(hours, parse_comparisons(pol.hour_filters))
    hour_multiplier = length(hour_idxs) < nhr ? ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr]) : ByNothing(1.0)

    cols = _emiscap_colnames(pol)

    # use a policy-specific column name to avoid overwriting existing emis_col on the table
    add_table_col!(data, table_name, cols.import_emis, Container[ByNothing(0.0) for _ in 1:nrow(table)], NA,
        "Emissions factor of imported power on $(table_name) for $(pol.name)")

    # pol.name: hour-filtered indicator (ByHour when hour_filters apply, ByNothing(1) otherwise), 0 for non-qualifying branches
    # cols.dir: signed direction scalar (+1 if t_bus in region, -1 if f_bus in region) for use in setup_imports!
    add_table_col!(data, table_name, pol.name, Container[ByNothing(0.0) for _ in 1:nrow(table)], NA, "Indicator col for $(pol.name)")
    add_table_col!(data, table_name, cols.dir, [0.0 for _ in 1:nrow(table)], NA,
        "Direction scalar for $(pol.name): +1 if t_bus is in region, -1 if f_bus is in region")

    if !isempty(pol.import_ef_file)
        _setup_import_branches_by_file!(pol, data, table_name, bus_set, cols, hour_multiplier)
    else
        _setup_import_branches_by_value!(pol, data, table_name, bus_set, cols, hour_multiplier)
    end
end

"""
Single emissions factor: assign pol.import_ef to all branches crossing the cap region boundary.
"""
function _setup_import_branches_by_value!(pol, data, table_name, bus_set, cols, hour_multiplier)
    table = get_table(data, table_name)
    idxs = findall(row -> (row.t_bus_idx in bus_set) ⊻ (row.f_bus_idx in bus_set), eachrow(table))
    if isempty(idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports will not count toward the emission cap."
        return
    end
    table[idxs, cols.import_emis] .= pol.import_ef
    for idx in idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol.name] = hour_multiplier
        table[idx, cols.dir] = Float64(scalar)
    end
end

"""
Region- and hour-varying emissions factors from a file. Each row of the ef table defines a source
region (via its column values used as bus filters) and the hourly EFs for that region. Branches
are tagged per source region so each gets the correct EF container.
"""
function _setup_import_branches_by_file!(pol, data, table_name, bus_set, cols, hour_multiplier)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    pol_table = data[pol.name]
    years = get_years(data)
    nhr = get_num_hours(data)
    hr_col_start = findfirst(s -> s == "h1", names(pol_table))
    all_idxs = Int[]

    for sa in unique(pol_table.subarea)
        sa_table = pol_table[pol_table.subarea .== sa, :]

        # find buses in the source region for this ef table entry
        src_idxs = get_row_idxs(bus, parse_comparisons(sa_table[1, :]))
        src_set = Set(src_idxs)

        # branches that cross between the cap region and this specific source region
        idxs = findall(
            row -> (row.t_bus_idx in bus_set && row.f_bus_idx in src_set) ⊻
                   (row.f_bus_idx in bus_set && row.t_bus_idx in src_set),
            eachrow(table)
        )
        isempty(idxs) && continue

        # build EF container — ByYearAndHour if the file has a year column, ByHour otherwise
        if hasproperty(pol_table, :year)
            cap_years = [y for y in years if string(y) in string.(collect(keys(pol.targets)))]
            ef_years = unique(sa_table.year)
            if !all(in(ef_years), cap_years)
                @warn "The ef table for $(sa) is missing cap years required by $(pol.name). No import emissions counted for region $(sa)."
                continue
            end
    
            efs = ByYearAndHour(zeros(length(years), nhr))
            for (yr_idx, year) in enumerate(years)
                rows = sa_table[sa_table.year .== year, :]
                isempty(rows) && continue
                nrow(rows) > 1 && @warn "Multiple ef rows for $(sa) $(year) in $(pol.name). Using first."
                efs[yr_idx] = [rows[1, hr] for hr in hr_col_start:(hr_col_start + nhr - 1)]
            end
        else
            nrow(sa_table) > 1 && @warn "Multiple ef rows for $(sa) in $(pol.name). Using first."
            efs = ByHour(Float64[sa_table[1, hr] for hr in hr_col_start:(hr_col_start + nhr - 1)])
        end
        table[idxs, cols.import_emis] .= Ref(efs)
        append!(all_idxs, idxs)
    end

    if isempty(all_idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports will not count toward the emission cap."
        return
    end

    for idx in all_idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol.name] = hour_multiplier
        table[idx, cols.dir] = Float64(scalar)
    end
end


function setup_imports!(pol, config, data, model, table_name::Symbol)
    table = get_table(data, table_name)

    # skip if setup_import_branches! found no relevant branches for this table
    hasproperty(table, pol.name) || return

    cols = _emiscap_colnames(pol)
    dir_col = table[!, cols.dir]
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    valid_idxs = findall(br -> dir_col[br] != 0, axes(table, 1))
    isempty(valid_idxs) && return

    pflow_col = table_name == :branch ? :pflow_branch : :pflow_dc
    pflow = table_name == :branch ? model[pflow_col]::Array{AffExpr, 3} : model[pflow_col]::Array{VariableRef, 3}

    import_var_name = Symbol("import_$(table_name)_$(pol.name)")

    # variable and constraint together ensure exports are not counted: import_var >= dir * pflow,
    # so only positive (inbound) flows contribute.
    model[import_var_name] = @variable(model,
        [branch_idx in valid_idxs, yr_idx in 1:nyr, hr_idx in 1:nhr],
        lower_bound = 0
    )

    @constraint(model, [branch_idx in valid_idxs, yr_idx in 1:nyr, hr_idx in 1:nhr],
        model[import_var_name][branch_idx, yr_idx, hr_idx] >=
            dir_col[branch_idx][yr_idx, hr_idx] *
            pflow[branch_idx, yr_idx, hr_idx]
    )

    # add import emissions into the total emissions expression for this policy
    # pol.name col encodes hour filtering (ByHour or ByNothing), matching the gen indicator pattern
    hour_weights = get_hour_weights(data)
    emis_expr = model[Symbol("emis_total_$(pol.name)")]
    
    for branch_idx in valid_idxs, yr_idx in 1:nyr, hr_idx in 1:nhr
        add_to_expression!(
            emis_expr[yr_idx, hr_idx],
            model[import_var_name][branch_idx, yr_idx, hr_idx],
            hour_weights[hr_idx] *
            get_table_num(data, table_name, pol.name, branch_idx, yr_idx, hr_idx) *
            get_table_num(data, table_name, cols.import_emis, branch_idx, yr_idx, hr_idx)
        )
    end
end

"""
    setup_allowance_prce_steps!(pol::EmissionCap, config, data) -> 
    Function that sets up prices and allowance quantities based on kwarg and stores values in data. 
"""
function setup_allowance_price_resp_alws(pol, config, data)
    cols = _emiscap_colnames(pol)

    years = get_years(data)
    sym_years = Symbol.(get_years(data))
    nyr = get_num_years(data)
    nsteps = length(pol.step_prices)

    target_years = [String(y) for y in sym_years if haskey(pol.targets, y)]
    target_idxs = [i for i in 1:nyr if years[i] in target_years]
    target_nyr = length(target_years)

    # Escalate price steps at 5%/yr, relative to the first year that has a target
    # (not the first model year), so the configured step_prices land unescalated in that year.
    first_target_idx = first(target_idxs)
    prices = [[p * (1 + pol.rate)^(yr_idx - first_target_idx) for yr_idx in 1:nyr] for p in pol.step_prices]
    
    # cumulative allowance quantity at each step boundary = target + adder
    targets = [get(pol.targets, y, 0.0) for y in Symbol.(target_years)]
    step_alw = [targets .+ adder for adder in pol.step_adders]
    
    # Marginal (incremental) width of each step
    # Step 1 lower boundary is 0, so width = cum_qty[1]
    step_widths = Vector{Vector{Float64}}(undef, nsteps)
    step_widths[1] = step_alw[1]
    for s in 2:nsteps
        step_widths[s] = step_alw[s] .- step_alw[s-1]
    end

    # add price steps to data
    price_resp_alws = DataFrame(
        step         = Int[],
        year         = String[],
        price        = Float64[],
        cum_alw      = Float64[],
        step_alw_q   = Float64[],
        )

    for s in 1:nsteps
        for (i,yr_idx) in enumerate(target_idxs)
            yr = get_years(data)[yr_idx]
            haskey(pol.targets, Symbol(yr)) || continue 

            push!(price_resp_alws, (
                s,
                years[yr_idx],
                prices[s][yr_idx],
                step_alw[s][i],
                step_widths[s][i],
            ))

        end
    end
    
    data[cols.price_resp_alws] = price_resp_alws
end

"""
    add_price_responsive_allowances!(pol::EmissionCap, config, data) -> 
    Function creates a variable for price responsive allowances and adds cost of allowances at each step to objective term. 
"""
function add_price_responsive_allowances(pol, config, data, model)
    cols = _emiscap_colnames(pol)

    nyr = get_num_years(data)
    years = get_years(data)
    nsteps = length(pol.step_prices)
    price_resp_alws = data[cols.price_resp_alws]

    # Rebuild matrices
    prices = zeros(Float64, nsteps, nyr)
    step_widths = fill(Inf, nsteps, nyr)

    for row in eachrow(price_resp_alws)
        s = row.step
        yr_idx = findfirst(==(row.year), years)

        prices[s, yr_idx] = row.price
        step_widths[s, yr_idx] = row.step_alw_q
    end
    
    # Variables: allowances purchased per year per step, in tons
    alw_name = cols.alw_name
    model[alw_name] = @variable(model,          # initialize a variable of size year x steps with lower bound 0
        [yr_idx in 1:nyr, s in 1:nsteps],
        lower_bound = 0,
        base_name = string(alw_name)
    )
    alw = model[alw_name]
    for yr_idx in 1:nyr, s in 1:nsteps         # set upper bound of allowances for each step s
        w = step_widths[s, yr_idx]
        isinf(w) || set_upper_bound(alw[yr_idx, s], w)
    end

    # Per-year cost expression
    alw_cost_name = cols.alw_cost
    model[alw_cost_name] = @expression(model,           # cost expression is allowances at step k multiplied by price at step s
        [yr_idx in 1:nyr],
        sum(prices[s, yr_idx] * alw[yr_idx, s] for s in 1:nsteps)
    )
   
    add_obj_exp!(data, model, AllowanceTerm(), alw_cost_name; oper=+)   # add allowance costs to objective function
end

struct AllowanceTerm <: Term end

"""
    fieldnames_for_yaml(::EmissionCap) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(T::Type{M}) where {M<:EmissionCap}
    return setdiff(fieldnames(T), (:name, :gen_cons,))
end
export fieldnames_for_yaml