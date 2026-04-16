

@doc raw"""
    struct EmissionCap <: Policy

Emission Cap - A limit on a certain emission for a given set of generators. The mod caps emissions by setting up a generation constraint, which uses the given emissions rate column to determine the generation limit. The shadow price
of the generation constraint is used to evalaute the cost of the policy.

### Keyword Arguments:
* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `targets`: OrderedDict of cap targets by year
* `gen_filters`: OrderedDict of generator filters
* `hour_filters`: OrderedDict of hour filters
* `gen_cons`: GenerationConstraint Modification created on instantiation of the EmissionCap (not specified in config). It sets the cap targets as the max_targets of the GenerationConstraint and passes on other fields.
* `bus_filters`: OrderedDict of bus filters
* `cap_imports`: Bool that indicates if emissions cap applies to imported power. Optional value, defaults to false. If this is true but no emissions factors are provided, will default to the emissions intensity of ng.
* `import_ef`: Single emissions factor for imported power in all regions and hours. Optional, defaults to ng emissions intensity.
* `import_ef_file`: File that contains emissions factors of imported power by region and hour. Optional.

### Table Column Added: 
* `(:gen, :<name>_prc)` - the shadow price of the policy converted to DollarsPerMWhGenerated

### Results Formula:
* `(:gen, :cost_name)` - the cost of the policy based on the shadow price of the generation constraint


"""
struct EmissionCap <: Policy
    name::Symbol
    emis_col::Symbol
    targets::OrderedDict{Symbol, Float64}
    gen_filters::OrderedDict
    hour_filters::OrderedDict
    bus_filters::OrderedDict
    cap_imports::Bool
    import_ef::Union{Float64, Nothing}
    import_ef_file::Union{String,Nothing}

    function EmissionCap(;name, emis_col, targets, gen_filters=OrderedDict(), hour_filters=OrderedDict(), bus_filters=OrderedDict(), cap_imports=false, import_ef=nothing, import_ef_file=nothing)
        if cap_imports && isempty(bus_filters)
            @warn "EmissionCap $(name) has cap_imports=true but no bus_filters specified — no import branches will be found."
        end
        if cap_imports && import_ef === nothing && import_ef_file === nothing
            emis_col == "emis_co2" || error("EmissionCap $(name) has cap_imports=true but no import emissions factor was provided and there is no default for $(emis_col)")
            import_ef = 0.428
            @warn "EmissionCap $(name) has cap_imports=true but no emissions factors were provided. The default ng emissions factor (0.428) will be applied to all imports."
        elseif cap_imports && import_ef !== nothing && import_ef_file !== nothing
            error("EmissionCap $(name) has both import_ef and import_ef_file specified. Provide only one.")
        elseif !cap_imports && (import_ef !== nothing || import_ef_file !== nothing)
            @warn "EmissionCap $(name) has cap_imports=false but emission factors were provided. Imports will not be counted toward the cap."
        end
        new(Symbol(name), Symbol(emis_col), OrderedDict{Symbol, Float64}(targets), OrderedDict(gen_filters), OrderedDict(hour_filters), OrderedDict(bus_filters), cap_imports, import_ef, import_ef_file)
    end

end

export EmissionCap


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
    if !isnothing(pol.import_ef_file)
        data[pol.name] = read_table(data, pol.import_ef_file, pol.name)
    end
end

function E4ST.modify_setup_data!(pol::EmissionCap, config, data)
    pol.cap_imports || return  # check if pol.cap_imports is set to true

    # tag the branches and dc lines that import power into regions subject to emission cap
    tag_import_branches!(pol, config, data, :branch)

    if any(mod -> mod isa DCLine, values(config[:mods]))
        tag_import_branches!(pol, config, data, :dc_line)
    end
end


"""
    E4ST.modify_model!(pol::EmissionCap, config, data, model)

Calls [`modify_model!(cons::GenerationConstraint, config, data, model)`](@ref)
"""

function E4ST.modify_model!(pol::EmissionCap, config, data, model)
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

    
    cap_cons_name = Symbol("cons_$(pol.name)_max")
    @info "Creating emissions cap constraint for $(pol.name) in years $(cap_years)"
    model[cap_cons_name] = @constraint(model,
        [
            yr_idx in 1:nyr;
            years[yr_idx] in cap_years
        ],
        sum(model[emis_expr_name][yr_idx, hr_idx] for hr_idx in 1:nhr)
        <= pol.targets[years[yr_idx]]
    )
    
end


"""
    E4ST.modify_results!(pol::EmissionCap, config, data) -> 
"""
function E4ST.modify_results!(pol::EmissionCap, config, data)
    gen = get_table(data, :gen)

    # create column for per MWh price of the policy in :gen
    cons_name = Symbol("cons_$(pol.name)_max")
    haskey(data[:results][:raw], cons_name) || return

    shadow_prc = get_shadow_price_as_ByYear(data, cons_name) #($/EmissionsUnit)

    prc_col = [(-shadow_prc) .* g[pol.name] .* g[pol.emis_col] for g in eachrow(gen)] #($/MWh Generated)

    add_table_col!(data, :gen, Symbol("$(pol.name)_prc"), prc_col, DollarsPerMWhGenerated, "Shadow price of $(pol.name) converted to DollarsPerMWhGenerated")

    # policy cost for generation: shadow price (per MWh generated) * generation
    cost_name = Symbol("$(pol.name)_cost")
    add_results_formula!(data, :gen, cost_name, "SumHourlyWeighted($(pol.name)_prc, pgen)", Dollars, "The cost of $(pol.name) based on the shadow price of the generation constraint")
    add_to_results_formula!(data, :gen, :emission_cap_cost, cost_name)

    # policy cost for imports: shadow price * emis factor * import flow, for branch and dc_line tables
    if pol.cap_imports
        import_emis_col = Symbol("$(pol.name)_$(pol.emis_col)")
        import_prc_col = Symbol("$(pol.name)_prc")
        import_cost_name = Symbol("$(pol.name)_import_cost")

        for table_name in (:branch, :dc_line)
            table_name == :dc_line && !any(mod -> mod isa DCLine, values(config[:mods])) && continue
            table = get_table(data, table_name)
            hasproperty(table, pol.name) || continue

            # shadow price per MWh of imports: shadow_prc * indicator * emis_factor
            prc_col = [(-shadow_prc) .* row[pol.name] .* row[import_emis_col] for row in eachrow(table)]
            add_table_col!(data, table_name, import_prc_col, prc_col, DollarsPerMWhGenerated,
                "Shadow price of $(pol.name) per MWh of imports on $(table_name)")

            add_results_formula!(data, table_name, import_cost_name, "SumHourlyWeighted($(import_prc_col), pflow)",
                Dollars, "The cost of $(pol.name) attributed to imports on $(table_name)")
            haskey(get_results_formulas(data), (table_name, :emission_cap_cost)) ||
                add_results_formula!(data, table_name, :emission_cap_cost, "0", Dollars, "Cost attributed to imports for all emission caps on $(table_name)")
            add_to_results_formula!(data, table_name, :emission_cap_cost, import_cost_name)
        end
    end
end

"""
    tag_import_branches!(pol::EmissionCap, config, data, table_name) -> 
    Function that identifies the branches and dc_lines that import power into the region/s covered by the EmissionCap.
"""

function tag_import_branches!(pol, config, data, table_name::Symbol)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)
    bus_idxs = get_row_idxs(bus, parse_comparisons(pol.bus_filters))
    bus_set = Set(bus_idxs)

    hours = get_table(data, :hours)
    nhr = get_num_hours(data)
    hour_idxs = get_row_idxs(hours, parse_comparisons(pol.hour_filters))
    hour_multiplier = length(hour_idxs) < nhr ? ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr]) : ByNothing(1.0)

    # use a policy-specific column name to avoid overwriting existing emis_col on the table
    import_emis_col = Symbol("$(pol.name)_$(pol.emis_col)")
    add_table_col!(data, table_name, import_emis_col, Container[ByNothing(0.0) for _ in 1:nrow(table)], NA,
        "Emissions factor of imported power on $(table_name) for $(pol.name)")

    # pol.name: hour-filtered indicator (ByHour when hour_filters apply, ByNothing(1) otherwise), 0 for non-qualifying branches
    # pol.name_dir: signed direction scalar (+1 if t_bus in region, -1 if f_bus in region) for use in setup_imports!
    add_table_col!(data, table_name, pol.name, Container[ByNothing(0.0) for _ in 1:nrow(table)], NA, "Indicator col for $(pol.name)")
    dir_col_name = Symbol("$(pol.name)_dir")
    add_table_col!(data, table_name, dir_col_name, [0.0 for _ in 1:nrow(table)], NA,
        "Direction scalar for $(pol.name): +1 if t_bus is in region, -1 if f_bus is in region")

    if !isnothing(pol.import_ef_file)
        _tag_import_branches_by_file!(pol, data, table_name, bus_set, import_emis_col, dir_col_name, hour_multiplier)
    else
        _tag_import_branches_by_value!(pol, data, table_name, bus_set, import_emis_col, dir_col_name, hour_multiplier)
    end
end

"""
Single emissions factor: assign pol.import_ef to all branches crossing the cap region boundary.
"""
function _tag_import_branches_by_value!(pol, data, table_name, bus_set, import_emis_col, dir_col_name, hour_multiplier)
    table = get_table(data, table_name)
    idxs = findall(row -> (row.t_bus_idx in bus_set) ⊻ (row.f_bus_idx in bus_set), eachrow(table))
    if isempty(idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports will not count toward the emission cap."
        return
    end
    table[idxs, import_emis_col] .= pol.import_ef
    for idx in idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol.name] = hour_multiplier
        table[idx, dir_col_name] = Float64(scalar)
    end
end

"""
Region- and hour-varying emissions factors from a file. Each row of the ef table defines a source
region (via its column values used as bus filters) and the hourly EFs for that region. Branches
are tagged per source region so each gets the correct EF container.
"""
function _tag_import_branches_by_file!(pol, data, table_name, bus_set, import_emis_col, dir_col_name, hour_multiplier)
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
        table[idxs, import_emis_col] .= Ref(efs)
        append!(all_idxs, idxs)
    end
    
    if isempty(all_idxs)
        @warn "No relevant $(table_name) for $(pol.name). Imports will not count toward the emission cap."
        return
    end

    for idx in all_idxs
        scalar = table[idx, :t_bus_idx] in bus_set ? 1 : -1
        table[idx, pol.name] = hour_multiplier
        table[idx, dir_col_name] = Float64(scalar)
    end
end


function setup_imports!(pol, config, data, model, table_name::Symbol)
    table = get_table(data, table_name)

    # skip if tag_import_branches! found no relevant branches for this table
    hasproperty(table, pol.name) || return

    dir_col = table[!, Symbol("$(pol.name)_dir")]
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
    import_emis_col = Symbol("$(pol.name)_$(pol.emis_col)")
    emis_expr = model[Symbol("emis_total_$(pol.name)")]
    for branch_idx in valid_idxs, yr_idx in 1:nyr, hr_idx in 1:nhr
        add_to_expression!(
            emis_expr[yr_idx, hr_idx],
            model[import_var_name][branch_idx, yr_idx, hr_idx],
            hour_weights[hr_idx] *
            get_table_num(data, table_name, pol.name, branch_idx, yr_idx, hr_idx) *
            get_table_num(data, table_name, import_emis_col, branch_idx, yr_idx, hr_idx)
        )
    end
end

"""
    fieldnames_for_yaml(::EmissionCap) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(T::Type{M}) where {M<:EmissionCap}
    return setdiff(fieldnames(T), (:name, :gen_cons,))
end
export fieldnames_for_yaml