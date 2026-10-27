
"""
    Sector <: Modification

    The Sector modification can be used to model the emissions and electrification pathways of any non-power sector when subject to an emission cap or price. The modification takes in emissions and electricity 
    demand baselines for each subsector. Then each sector/subsector emissions can be abated for a cost (as determined by MAC curves) and with a corresponding increase in electricity demand. The sectors are 
    linked with the core power sector model through policies that constrain or price emissions.

    For example, when an emission cap has the same regional coverage as a Sector instance, the model will select abatement and electrification pathways across the relevant sector/subsectors and a power sector 
    resource mix that minimize the economy-wide costswhile meeting the cap targets.


### Keyword Arguments:
* `name` - the name of the [`Modification`](@ref).
* `mac_file` - the filename of the marginal abatement cost curve containing the abatement and price steps for the corresponding sector and subsectors.  See also [`summarize_table(::Val{:mac_steps})`](@ref)
* `emis_baseline_file` - the filename of the sector's emissions table, which contains the baseline emissions by year for the corresponding sector and subsectros. See also [`summarize_table(::Val{:emis_baseline})`](@ref)
* `elec_baseline_file` -  the filename of the sector's electricity table, which contains the baseline electricity demand by year for the corresponding sector and subsectors. See also [`summarize_table(::Val{:elec_baseline})`](@ref)
* `load_profile_file` -  the filename of the sector's load profile table, which contains the hourly load profile for the corresponding sector and subsectors. See also [`summarize_table(::Val{:load_profile})`](@ref)
* `elasticity_file` - the filename of the sector's elastcity table, which contains the cross and own semi-elasticities for the corresponding sector and subsectors.  See also [`summarize_table(::Val{:elasticity})`](@ref)

### Tables Added:
* `mac_steps` - contains the sector's marginal abatement cost curve
* `emis_baseline` - contains the sector's baseline emissions pathway
* `elec_baseline` - contains the sector's baseline electricity pathway
* `elasticity` - contains the sector's cross and own elasticity values
* `load_profile` - contains the sector's diurnal load profile
* `nonelec` - stores emissions and electricity baselines and abatement and electrification pathways for each modeled subsector. unlike other Sector tables, nonelec is shared across every `Sector` mod instance so that each 
   sector from different regions are all included in the same table


 ### Table Columns Added:
The five input tables(`mac_steps`, `emis_baseline`, `elec_baseline`, `elasticity`, `load_profile`) are read as given and gain no columns.

Populated in [`modify_setup_data!`](@ref):
* `(:nonelec, :area, :subarea)` - indicates the E4ST region the sector mod belongs to
* `(:nonelec, :sector, :subsector)` - indicates the sector and subsector the mod represents
* `(:nonelec, :mod_name)` - which `Sector` instance (`sec.name`) the row belongs to. Since `:nonelec` is shared across instances, `modify_model!`/`modify_results!` recover only their own rows via `get_row_idxs(regsub, :mod_name => name)`.
* `(:nonelec, :baseline_emis)` - `ByYear` baseline (pre-abatement) emissions. Units follow `emis_col`.
* `(:nonelec, :baseline_demand)` - `ByYear` baseline electricity consumption (`Cons0`), in MWh. Used only to compute `elec_per_emis`; E4ST's total baseline load is not adjusted by it, since we assume load projections already carry this demand.
* `(:nonelec, :elec_per_emis)` - `ByYear` induced electricity demand per unit of emissions abated, `(cross_elast · Cons0) / (own_elast · EmisSector0)`, in MWh per `emis_col` unit. `NaN` where the denominator is zero, which 
   [`add_sector_electrification_load!`](@ref) treats as an error.

Populated post-solve in [`modify_results!`](@ref):
* `(:nonelec, :abate_total)` - `ByYear` emissions abated. Units follow `emis_col`.
* `(:nonelec, :resid_emis)` - `ByYear` residual (unabated) emissions, `baseline_emis - abate_total`. These are the emissions `EmissionCap` counts against its constraint or `EmissionPrice` will price.
* `(:nonelec, :elec_demand_change)` - `ByYear` induced change in electricity demand, `abate_total * elec_per_emis`, in MWh.


### Model Modification
Indices: `regsub_idx` is a row of this instance's region-subsectors in the shared `:nonelec` table (`mod_name == name`), `step_idx` is a MAC step local to that region-subsector (not a row index into the `mac_steps` table), and `yr_idx` 
is the simulation year.
* Variables
    * `abate_<name>[regsub_idx, step_idx, yr_idx]` - emissions abated on one MAC step, bounded above by that step's `quantity`. Units follow `emis_col`.
* Expressions
    * `abate_total_<name>[regsub_idx, yr_idx]` - total emissions abated, summed over that region-subsector's MAC steps.
    * `resid_emis_<name>[regsub_idx, yr_idx]` - residual (unabated) emissions, `baseline_emis - abate_total`. These are what `EmissionCap` counts.
    * `cost_sector_<name>_obj[yr_idx]` - MAC abatement cost, the staircase area under the MAC curve (`sum(abate * mac.price)` over all region-subsectors and steps), added to the objective via [`add_obj_exp!`](@ref) 
      under [`SectorTerm`](@ref). Residual emissions carry no direct cost term here -- their only price signal comes from whatever `EmissionCap` covers this sector's region-subsectors.
* Constraints
    * `cons_abate_cap_<name>[regsub_idx, yr_idx]` - abatement in a year cannot exceed that year's baseline emissions: `abate_total <= baseline_emis`.

## Pbal coupling
`modify_model!` calls [`add_sector_electrification_load!`](@ref), which adds only the responsive electrification load (`abate_total · elec_per_emis`) into `plserv_bus`. The load is distributed across hours using the load profile table. 


Note that the EmissionCap and EmissionPrice mods search for relevant sector emissions and add them to the full emission expression, linking these emissions with the power sector.

### Results Formulas Added:
All are `SumYearly` aggregations over `:nonelec`, summed across region-subsectors and years.
* `(:nonelec, :abate_emis_total)`, `(:nonelec, :resid_emis_total)`, `(:nonelec, :baseline_emis_total)` - emissions, units following `emis_col`.
* `(:nonelec, :baseline_demand_total)`, `(:nonelec, :elec_response_total)` - baseline and induced electricity demand, in MWh.

"""
Base.@kwdef struct Sector <: Modification
    name::Symbol
    sector::Symbol
    mac_file::String
    emis_baseline_file::String
    elec_baseline_file::String
    elasticity_file::String
    load_profile_file:: String
end
export Sector


# sector mod comes right before the EmissionCap so that the sector emissions expression is set up before the emissions constraint is created
mod_rank(::Type{<:Sector}) = mod_rank(EmissionCap) - 0.1


"""
    modify_raw_data!(sec::Sector, config, data)

Reads in necessary input data files for the sector and stores them in data as tables.

"""
function modify_raw_data!(sec::Sector, config, data)
    # read in sector tables, read_table will check type coercion and required columns against the summarize_table function
    name = sec.name

    @info "Loading sector_$(name)_mac_steps from $(sec.mac_file)"
    data[Symbol("sector_$(name)_mac_steps")] = read_table(data, sec.mac_file, :mac_steps)
    @info "Loading sector_$(name)_emis_baseline from $(sec.emis_baseline_file)"
    data[Symbol("sector_$(name)_emis_baseline")] = read_table(data, sec.emis_baseline_file, :emis_baseline)
    @info "Loading sector_$(name)_elec_baseline from $(sec.elec_baseline_file)"
    data[Symbol("sector_$(name)_elec_baseline")] = read_table(data, sec.elec_baseline_file, :elec_baseline)
    @info "Loading sector_$(name)_load_profile from $(sec.load_profile_file)"
    data[Symbol("sector_$(name)_load_profile")] = read_table(data, sec.load_profile_file, :load_profile)
    @info "Loading sector_$(name)_elasticity from $(sec.elasticity_file)"
    data[Symbol("sector_$(name)_elasticity")] = read_table(data, sec.elasticity_file, :elasticity)

    return nothing
end

@doc """
    summarize_table(::Val{:mac_steps})

$(table2markdown(summarize_table(Val(:mac_steps))))
"""
function summarize_table(::Val{:mac_steps})
    df = TableSummary()
    push!(df,
        (:area, AbstractString, NA, true, "The geographic level this row applies to, given as the name of a column in the `bus` table.  I.e. \"state\", \"county\", or \"nation\".  Paired with `subarea` to identify the region."),
        (:subarea, AbstractString, NA, true, "The region this row applies to, given as a value of the `bus` column named by `area`.  I.e. \"minnesota\" when `area` is \"state\" or \"us\" when it is \"nation\"."),
        (:sector, AbstractString, NA, true, "Refers to the sector these data correspond with (e.g. buildings, transportation, industrial)."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:price, Float64, DollarsPerShortTon, true, "The marginal abatement cost of this step, i.e. the cost per short ton of emissions abated.  Steps are used in ascending price order, so cheaper abatement is exhausted first."),
        (:quantity, Float64, ShortTonsPerYear, true, "The maximum amount of abatement available at this step, in short tons per year.  Sets the upper bound of the `abate` variable for this step."),
    )
    return df
end

@doc """
    summarize_table(::Val{:emis_baseline})

$(table2markdown(summarize_table(Val(:emis_baseline))))
"""
function summarize_table(::Val{:emis_baseline})
    df = TableSummary()
    push!(df,
        (:src_file, AbstractString, NA, false, "Description of the source data file this baseline emissions data came from."),
        (:area, AbstractString, NA, true, "The geographic level this row applies to, given as the name of a column in the `bus` table.  I.e. \"state\", \"county\", or \"nation\".  Paired with `subarea` to identify the region."),
        (:subarea, AbstractString, NA, true, "The region this row applies to, given as a value of the `bus` column named by `area`.  I.e. \"minnesota\" when `area` is \"state\" or \"us\" when it is \"nation\"."),
        (:sector, AbstractString, NA, false, "Refers to the broad sector these data correspond with e.g., industry, building, transportation."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:status, Bool, NA, false, "Whether or not to include this baseline emissions row."),
        (:emis_col, AbstractString, NA, true, "The pollutant these emissions represent (e.g. \"emis_co2\", \"emis_so2\"), matched against `EmissionCap`'s `emis_col` so this row's residual emissions only flow into caps regulating the same pollutant.  A single (area, subarea, subsector) can appear as multiple rows, one per pollutant."),
        (:y_, Float64, NA, true, "The baseline emissions for each year, in units that match the emis_col (e.g. short tons for CO2 and lbs for NOx).  Include a column for each year in the simulation, i.e. `:y2020`, `:y2030`, etc.  Years without a column are treated as 0 for all region-subsectors."),
    )
    return df
end

@doc """
    summarize_table(::Val{:elec_baseline})

$(table2markdown(summarize_table(Val(:elec_baseline))))
"""
function summarize_table(::Val{:elec_baseline})
    df = TableSummary()
    push!(df,
        (:src_file, AbstractString, NA, false, "Description of the source data file this baseline electricity data came from."),
        (:area, AbstractString, NA, true, "The geographic level this row applies to, given as the name of a column in the `bus` table.  I.e. \"state\", \"county\", or \"nation\".  Paired with `subarea` to identify the region."),
        (:subarea, AbstractString, NA, true, "The region this row applies to, given as a value of the `bus` column named by `area`.  I.e. \"minnesota\" when `area` is \"state\", \"hennepin\" when it is \"county\", or \"us\" when it is \"nation\"."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:status, Bool, NA, false, "Whether or not to include this baseline electricity row."),
        (:y_, Float64, MWhLoad, true, "The baseline electricity consumption (Cons0) for this region-subsector, per year.  Include a column for each year in the simulation, i.e. `:y2020`, `:y2030`, etc.  Used only to compute the electrification response coefficient `elec_per_emis` (Haiku eq. 10's phi); E4ST's total baseline load is not adjusted by these values, since it already ingests baseline demand as a primary input."),
    )
    return df
end

@doc """
    summarize_table(::Val{:load_profile})

$(table2markdown(summarize_table(Val(:load_profile))))
"""
function summarize_table(::Val{:load_profile})
    df = TableSummary()
    push!(df,
        (:area, AbstractString, NA, true, "The geographic level this row applies to, given as the name of a column in the `bus` table.  I.e. \"state\", \"county\", or \"nation\".  Paired with `subarea` to identify the region."),
        (:subarea, AbstractString, NA, true, "The region this row applies to, given as a value of the `bus` column named by `area`.  I.e. \"minnesota\" when `area` is \"state\" or \"us\" when it is \"nation\"."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:year, String, Year, false, "The year this load profile applies to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\".  Leave blank to apply to all years."),
        (:h_, Float64, Ratio, true, "Share of this region-subsector's annual responsive electrification load falling in each hour.  Include a column for each hour in the hours table, i.e. `:h1`, `:h2`, ... `:hn`."),
    )
    return df
end

@doc """
    summarize_table(::Val{:elasticity})

$(table2markdown(summarize_table(Val(:elasticity))))
"""
function summarize_table(::Val{:elasticity})
    df = TableSummary()
    push!(df,
        (:area, AbstractString, NA, true, "The geographic level this row applies to, given as the name of a column in the `bus` table.  I.e. \"state\", \"county\", or \"nation\".  Paired with `subarea` to identify the region."),
        (:subarea, AbstractString, NA, true, "The region this row applies to, given as a value of the `bus` column named by `area`.  I.e. \"minnesota\" when `area` is \"state\" or \"us\" when it is \"nation\"."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:own_elast, Float64, NA, true, "The semi-elasticity of emissions in response to change in the carbon price for this region-subsector, used with `cross_elast` and baseline electricity/emissions to compute the electrification response coefficient `elec_per_emis`."),
        (:cross_elast, Float64, NA, true, "The semi-elasticity of electricity demand with respect to a change in the carbon price for this region-subsector, used with `own_elast` and baseline electricity/emissions to compute the electrification response coefficient `elec_per_emis`."),
        (:c_price, Float64, NA, true, "The carbon price point used to anchor the MAC curve. For regions that do not yet have a carbon price, this will be zero."),
        (:emis_qty, Float64, NA, true, "The historical annual emissions value that corresponds with the carbon price, used to anchor the MAC curve."),
    )
    return df
end


"""
    modify_setup_data!(sec::Sector, config, data)

Creates or appends to a shared `:nonelec` table to store emissions and electricity 
pathways for each sector. Uses the elasticity table and baseline values to calculate 
and store `elec_per_emis`: the electrification response per unit of abatement.

"""
function modify_setup_data!(sec::Sector, config, data)
    name = sec.name
    @info "Setting up Sector: $name"

    mac  = get_table(data, Symbol("sector_$(name)_mac_steps"))
    emis = get_table(data, Symbol("sector_$(name)_emis_baseline"))
    elec = get_table(data, Symbol("sector_$(name)_elec_baseline"))
    lp   = get_table(data, Symbol("sector_$(name)_load_profile"))
    elast = get_table(data, Symbol("sector_$(name)_elasticity"))

    years = get_years(data)

    # Validate per-row (area, subarea) against the bus table. `area` names a bus column ("state", "bus_idx", ...); `subarea` is one of that column's values
    bus = get_table(data, :bus)
    for (tbl_name, tbl) in ((:mac, mac), (:emis, emis), (:elec, elec), (:lp, lp), (:elast, elast))
        for area in unique(tbl.area)
            sym = Symbol(area)
            hasproperty(bus, sym) || @warn "Sector $name: bus table has no column `$area` referenced in $(tbl_name) table"
        end
    end

    # validate load profile table, check that:
    # * no individual hour may be negative -- there's no such thing as negative load in an hour.
    # * the shape must not be all-zero -- there'd be nothing to distribute the responsive load across.
    nhr = get_num_hours(data)
    hour_cols = [Symbol("h$h") for h in 1:nhr]
    hour_weights = get_hour_weights(data)
    for row in eachrow(lp)
        any(h -> row[hour_cols[h]] < 0, 1:nhr) &&
            error("Sector $name: load profile row for area=$(row.area), subarea=$(row.subarea), subsector=$(row.subsector), year=$(row.year) has a negative value in one or more of h1..h$(nhr) -- hourly load shape values must be >= 0")
        annual_shape = sum(row[hour_cols[h]] * hour_weights[h] for h in 1:nhr)
        annual_shape == 0 &&
            error("Sector $name: load profile row for area=$(row.area), subarea=$(row.subarea), subsector=$(row.subsector), year=$(row.year) has an all-zero load shape (h1..h$(nhr) all 0) -- there is no hourly pattern to distribute the responsive load across")
    end

    # sort MAC steps ascending in price (per region-subsector) so that they are listed in step_order (although table is likely read in sorted)
    sort!(mac, [:area, :subarea, :sector, :subsector, :price])
    mac.subsector = string.(mac.subsector)

    # error if any simulation year is entirely missing from emis or elec
    missing_years = filter(y -> !hasproperty(emis, Symbol(y)) || !hasproperty(elec, Symbol(y)), years)
    if !isempty(missing_years)
        error("Sector $name: is missing baseline emissions or electricity data for year(s) $missing_years.")
        return nothing
    end

    # Attach each emis row's own_elast/cross_elast (elast) and Cons0 (elec) by (area, subarea, subsector) 
    # Error if a a regsub has no match because there is no abatement option without elasticities or baseline electrificity demand
    elast_lookup = Dict((r.area, r.subarea, r.subsector) => (r.own_elast, r.cross_elast) for r in eachrow(elast))
    elec_lookup = Dict((r.area, r.subarea, r.subsector) => r for r in eachrow(elec))

    keep_idxs = findall(r -> haskey(elast_lookup, (r.area, r.subarea, r.subsector)) && haskey(elec_lookup, (r.area, r.subarea, r.subsector)), eachrow(emis))
    n_excluded = nrow(emis) - length(keep_idxs)
    n_excluded > 0 && error("Sector $name: $n_excluded region-subsector row(s) with no matching elasticity or electricity baseline row.")
    emis = emis[keep_idxs, :]

    # build rows for the shared `:nonelec` table: one row per region-subsector, with `baseline_emis`/`baseline_demand`/`elec_per_emis` as `ByYear` columns
    # elec_per_emis = (cross_elast · Cons0) / (own_elast · EmisSector0), set to `NaN` only for a zero denominator (own_elast or emis0 == 0), 
    elec_per_emis_min = 1e-6   # MWh per emis_col unit below which the electrification response is treated as none

    # `:nonelec` is a single table shared across every Sector mod
    # `mod_name` identifies which mod instance each row belongs to
    regsub_new = select(emis, [:area, :subarea, :sector, :subsector, :emis_col])
    regsub_new.mod_name = fill(name, nrow(emis))

    baseline_emis_col  = Vector{ByYear}(undef, nrow(emis))
    cons0_col          = Vector{ByYear}(undef, nrow(emis))
    elec_per_emis_col  = Vector{ByYear}(undef, nrow(emis))

    for (i, row) in enumerate(eachrow(emis))
        own_elast, cross_elast = elast_lookup[(row.area, row.subarea, row.subsector)]
        elec_row = elec_lookup[(row.area, row.subarea, row.subsector)]

        emis0_vals = [Float64(row[Symbol(y)]) for y in years]
        cons0_vals = [Float64(elec_row[Symbol(y)]) for y in years]
        elec_per_emis_vals = [
            if own_elast == 0.0 || emis0_vals[j] == 0.0
                NaN
            else
                p = (cross_elast * cons0_vals[j]) / (own_elast * emis0_vals[j])
                abs(p) < elec_per_emis_min ? 0.0 : round(p; sigdigits = 4)
            end
            for j in eachindex(years)
        ]

        baseline_emis_col[i]     = ByYear(emis0_vals)
        cons0_col[i]             = ByYear(cons0_vals)
        elec_per_emis_col[i]     = ByYear(elec_per_emis_vals)
    end

    regsub_new.baseline_emis           = baseline_emis_col
    regsub_new.baseline_demand         = cons0_col
    regsub_new.elec_per_emis           = elec_per_emis_col

    if has_table(data, :nonelec)
        append!(get_table(data, :nonelec), regsub_new)
    else
        data[:nonelec] = regsub_new
    end

    return nothing
end


"""
    modify_model!(sec::Sector, config, data, model)

Set up the sector's abatement and residual emissions variables, constraints (non-negativity), 
and objective function contribution. The emissions expression for a Sector mod is created here, 
but it is added to the relevant constraint through the respective mod (e.g., the EmissionCap 
mod will search for a Sector mod and add the sector emissions to the model-wide emissions expression). 

Also adds the sector's responsive electric load to `plserv_bus` via [`add_sector_electrification_load!`](@ref). 

"""
function modify_model!(sec::Sector, config, data, model)
    name = sec.name
    @info "Adding Sector $name to the model"

    mac = get_table(data, Symbol("sector_$(name)_mac_steps"))
    lp  = get_table(data, Symbol("sector_$(name)_load_profile"))
    years = get_years(data)
    nyear = length(years)
    nstep = nrow(mac)

    regsub_full = get_table(data, :nonelec)
    regsub = view(regsub_full, get_row_idxs(regsub_full, :mod_name => name), :)
    nregsub = nrow(regsub)

    # skip model modification if there are no MAC or baseline rows for the sector
    if nstep == 0 || nregsub == 0
        @warn "Sector $name: empty MAC or baseline table, skipping model modification"
        return nothing
    end

    # Two region-subsector -> input-row lookups, `load_profile` and `mac_steps`.

    # Load profile: lp varies by year, so these are set up as keyed Dicts rather than a Vector. 
    #  `lp_index` is the exact match, # (area, subarea, subsector, year) -> lp row
    #  `lp_years_index` is the fallback, (area, subarea, subsector) -> [(year, lp row)], which lets `_lp_lookup` pick the closest available year instead of skipping the region-subsector
    lp_index = Dict{NTuple{4, String}, Int}()
    lp_years_index = Dict{NTuple{3, String}, Vector{Tuple{Int,Int}}}()
    for (lp_idx, row) in enumerate(eachrow(lp))
        area, subarea, subsector = string(row.area), string(row.subarea), string(row.subsector)
        yearstr = string(row.year)
        lp_index[(area, subarea, subsector, yearstr)] = lp_idx
        isempty(yearstr) && continue
        push!(get!(lp_years_index, (area, subarea, subsector), Tuple{Int,Int}[]), (year2int(yearstr), lp_idx))
    end

    # MAC steps: year-invariant, setup as a vector indexed by `regsub_idx` and kept local rather than stored in `:nonelec` column, since there is no meaning outside this function
    # A region-subsector with no matching steps still has its emissions counted by whatever cap covers it, there just is no way to abate 
    mac_idxs = map(1:nregsub) do regsub_idx
        idxs = get_row_idxs(mac, :area => regsub.area[regsub_idx], :subarea => regsub.subarea[regsub_idx], :subsector => regsub.subsector[regsub_idx])
        isempty(idxs) && @warn "Sector $name: no MAC steps found for area=$(regsub.area[regsub_idx]), subarea=$(regsub.subarea[regsub_idx]), subsector=$(regsub.subsector[regsub_idx]). Emissions will be added to constraint but there will be no way to abate."
        idxs
    end
    nsteps = length.(mac_idxs)

    # Baseline emissions per (region-subsector, year)
    baseline_emis = [regsub.baseline_emis[regsub_idx][yr_idx] for regsub_idx in 1:nregsub, yr_idx in 1:nyear]

    abate_name       = Symbol("abate_$(name)")
    abate_total_name = Symbol("abate_total_$(name)")
    resid_name       = Symbol("resid_emis_$(name)")
    cons_name        = Symbol("cons_abate_cap_$(name)")
    cost_name        = Symbol("cost_sector_$(name)_obj")
    
    
    # abatement variable, indexed by [regsub_idx, step_idx, yr_idx] where regsub_idx is the region-subsector, step_idx is the step on the mac curve, and yr_idx is the year
    model[abate_name] = @variable(model,
        [regsub_idx in 1:nregsub, step_idx in 1:nsteps[regsub_idx], yr_idx in 1:nyear],
        lower_bound = 0,
        upper_bound = mac.quantity[mac_idxs[regsub_idx][step_idx]],
        base_name = String(abate_name)
    )
    abate = model[abate_name]

    # set up abatement expression, indexed by region-subsector and year, summing over each step in abate[regsub_idx, step_idx, yr_idx]
    model[abate_total_name] = @expression(model,
        [regsub_idx in 1:nregsub, yr_idx in 1:nyear],
        sum(abate[regsub_idx, step_idx, yr_idx] for step_idx in 1:nsteps[regsub_idx]; init = AffExpr(0.0))
    )
    abate_total = model[abate_total_name]

    # residual emissions expression (baseline emissions minus abated emissions), indexed by [regsub_idx, yr_idx]
    model[resid_name] = @expression(model,
        [regsub_idx in 1:nregsub, yr_idx in 1:nyear],
        baseline_emis[regsub_idx, yr_idx] - abate_total[regsub_idx, yr_idx]
    )
    resid_emis = model[resid_name]

    # constraint so that abated emissions in a year can not be greater than the baseline emissions in that year
    model[cons_name] = @constraint(model,
        [regsub_idx in 1:nregsub, yr_idx in 1:nyear],
        abate_total[regsub_idx, yr_idx] <= baseline_emis[regsub_idx, yr_idx]
    )

    # couple the load from the electrification response with power-balancing equation
    # the baseline electricity (Cons0) is NOT added, because load projections already capture the baseline demand from each of these sectors
    add_sector_electrification_load!(sec, config, data, model, regsub, abate_total, lp, lp_index, lp_years_index)
    
    # abatement cost expression, summed over regsub and steps so that it is indexed by year only
    model[cost_name] = @expression(model,
        [yr_idx in 1:nyear],
        sum(abate[regsub_idx, step_idx, yr_idx] * mac.price[mac_idxs[regsub_idx][step_idx]]
            for regsub_idx in 1:nregsub, step_idx in 1:nsteps[regsub_idx]; init = AffExpr(0.0))
    )

    # add abatement costs to objective term, in units of $/short ton of emissions
    add_obj_exp!(data, model, SectorTerm(), cost_name; oper = +)
    return nothing
end

"""
    SectorTerm <: Term

Labels the sector's contribution to the objective function: the MAC abatement
cost `cost_sector_<name>_obj`, added via [`add_obj_exp!`](@ref).
"""
struct SectorTerm <: Term end

"""
    _sector_region_buses(bus, nbus)

Returns a function `buses_for(area, subarea)` that returns bus indices in the region. Stores the busses 
for each region, so that the bus table is only scanned once per region instead of once per lookup.
"""
function _sector_region_buses(bus, nbus)
    cache = Dict{Tuple{String,String}, Vector{Int}}()
    return function buses_for(area, subarea)
        get!(cache, (string(area), string(subarea))) do
            col = Symbol(area)
            hasproperty(bus, col) || return Int[]
            target = string(subarea)
            [b for b in 1:nbus if string(bus[b, col]) == target]
        end
    end
end

"""
    _lp_lookup(lp_index, lp_years_index, area, subarea, sub, y, target_yr) -> (row_idx, closest_yr) or nothing

Looks up a load-profile row for `(area, subarea, sub)` at year `y`: an exact-year match in `lp_index` 
if one exists, otherwise the closest available year for that key from `lp_years_index`. Returns `nothing` 
if there's no data at all for `(area, subarea, sub)`. `sub` is usually a subsector, but see the
`add_sector_electrification_load!` has a two stage lookup, which also tries this with a sector name in place of `sub`.
"""
function _lp_lookup(lp_index, lp_years_index, area, subarea, sub, y, target_yr)
    lp_row_idx = get(lp_index, (area, subarea, sub, string(y)), nothing)
    lp_row_idx !== nothing && return (lp_row_idx, nothing)
    years_for_key = get(lp_years_index, (area, subarea, sub), nothing)
    (years_for_key === nothing || isempty(years_for_key)) && return nothing
    _, best_idx = findmin(yr_ridx -> abs(yr_ridx[1] - target_yr), years_for_key)
    closest_yr, lp_row_idx = years_for_key[best_idx]
    return (lp_row_idx, closest_yr)
end

"""
    add_sector_electrification_load!(sec::Sector, config, data, model, regsub, abate_total, lp, lp_index)

Adds the *responsive* electrification load induced by abatement into `plserv_bus`, 
mplementing the consumption/abatement linkage equation:

    Cons_{y,r,sec} = Cons0_{y,r,sec} + Σ_k EmisAbatement_{y,r,sec,k} · phi_{y,r,sec}

where `phi` (emis_col unit -> MWh) is computed in `modify_setup_data!` 
per  `(cross_elast · Cons0) / (own_elast · EmisSector0)`, 
and stored as `regsub.elec_per_emis`, a `ByYear` column. 

For each region-subsector `regsub_idx` and year `yr_idx`:
* Responsive annual MWh = abate_total[regsub_idx, yr_idx] · elec_per_emis[regsub_idx, yr_idx]`
* Annual energy is distributed across the `nhr` representative hours according to `lp`'s hourly 
shape for the region-subsector/year, weighted by `hour_weights` and renormalized by `annual_shape` 
so the shape need not already sum to 1). It's split equally across the buses in `(area, subarea)`:

      plserv_bus[bus_idx, yr_idx, hr_idx] += (1/n_buses) · elec_per_emis[regsub_idx, yr_idx] · (lp_row.h_hr_idx / annual_shape) · abate_total[regsub_idx, yr_idx]

If `lp` has no row for a given region-subsector/year, the closest available year for that region-subsector 
(via `lp_years_index`) is used instead; only when there's no `lp` row at all for the region-subsector is
that region-subsector/year's responsive load skipped with a warning rather than falling back to an equal split. 


`lp`, `lp_index`, and `lp_years_index` are built once by  `modify_model!`, and passed in here rather than being re-fetched from `data`.
"""
function add_sector_electrification_load!(sec::Sector, config, data, model, regsub, abate_total, lp, lp_index, lp_years_index)
    name = sec.name
    plserv_bus = model[:plserv_bus]::Array{AffExpr,3}
    bus = get_table(data, :bus)
    nbus = nrow(bus)
    nhr = get_num_hours(data)
    nregsub = nrow(regsub)
    years = get_years(data)
    buses_for = _sector_region_buses(bus, nbus)

    hour_cols = [Symbol("h$hr_idx") for hr_idx in 1:nhr]
    hour_weights = get_hour_weights(data)

    n_applied = 0
    for regsub_idx in 1:nregsub, (yr_idx, yr) in enumerate(years)
        elec_per_emis = regsub.elec_per_emis[regsub_idx][yr_idx]
        if isnan(elec_per_emis)
            error("Sector $name: no elec_per_emis for area=$(regsub.area[regsub_idx]), subarea=$(regsub.subarea[regsub_idx]), subsector=$(regsub.subsector[regsub_idx]), year=$yr; can't have emission abatement without electrification")
            continue
        end
        elec_per_emis == 0.0 && continue   # no electrification response for this region-subsector/year

        # Look up this region-subsector/year's hourly load shape
        area, subarea, subsector = string(regsub.area[regsub_idx]), string(regsub.subarea[regsub_idx]), string(regsub.subsector[regsub_idx])
        target_yr = year2int(string(yr))

        result = _lp_lookup(lp_index, lp_years_index, area, subarea, subsector, yr, target_yr)
        lookup_sub = subsector
        if result === nothing
            # Some sectors (e.g. buildings) provide a single load profile per area/subarea rather than one per subsector -- in that case the lp table's `subsector` column holds the sector name itself.
            lookup_sub = string(sec.sector)
            result = _lp_lookup(lp_index, lp_years_index, area, subarea, lookup_sub, yr, target_yr)
        end
        if result === nothing
            error("Sector $name: no load profile found for area=$area, subarea=$subarea, subsector=$subsector (also tried sector-level subsector=$(sec.sector)), can't have emission abatement without electrification.")
            continue
        end
        lp_row_idx, closest_yr = result
        if closest_yr !== nothing
            @info "Sector $name: no load profile for area=$area, subarea=$subarea, subsector=$lookup_sub, year=$yr; using closest available year y$closest_yr instead"
        end
        lp_row = lp[lp_row_idx, :]
        # annual_shape is guaranteed > 0 here -- every lp row was validated in modify_setup_data!
        annual_shape = sum(lp_row[hour_cols[hr_idx]] * hour_weights[hr_idx] for hr_idx in 1:nhr)

        buses = buses_for(regsub.area[regsub_idx], regsub.subarea[regsub_idx])
        isempty(buses) && continue
        share = 1.0 / length(buses)

        # Distribute the responsive annual MWh across the nhr representative hours according to lp_row's shape
        applied_this = false
        for hr_idx in 1:nhr
            coef = share * elec_per_emis * lp_row[hour_cols[hr_idx]] / annual_shape
            coef == 0.0 && continue
            for bus_idx in buses
                add_to_expression!(plserv_bus[bus_idx, yr_idx, hr_idx], coef, abate_total[regsub_idx, yr_idx])
            end
            applied_this = true
        end
        applied_this && (n_applied += 1)
    end
    @info "Sector $name: added responsive electrification load for $n_applied (region-subsector, year) pairs to plserv_bus"
    return nothing
end
export add_sector_electrification_load!

"""
    modify_results!(sec::Sector, config, data)

Modify sector results.  Add `ByYear` columns to the `nonelec` table, 
for this instance's rows only (`mod_name == sec.name`):
* `abate_total` - emissions abated, by year
* `resid_emis` - residual (unabated) emissions, `baseline_emis - abate_total`
* `elec_demand_change` - induced electricity demand, `abate_total * elec_per_emis`, in MWh

Also adds `SumYearly` results formulas for those columns plus `baseline_emis`
and `baseline_demand`.

Because `nonelec` is shared across every `Sector` instance, the columns are created once by 
whichever instance runs first, and each instance then overwrites only its own rows.
"""
function modify_results!(sec::Sector, config, data)
    name = sec.name
    regsub = get_table(data, :nonelec)
    row_idxs = get_row_idxs(regsub, :mod_name => name)
    isempty(row_idxs) && return nothing

    nyear = get_num_years(data)
    hasproperty(regsub, :abate_total) ||
        add_table_col!(data, :nonelec, :abate_total, [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)], NA,
            "Total emissions abated for this region-subsector, by year. Units match `baseline_emis`'s (emis_col-dependent).")
    hasproperty(regsub, :resid_emis) ||
        add_table_col!(data, :nonelec, :resid_emis, [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)], NA,
            "Residual (unabated) emissions for this region-subsector, by year: `baseline_emis - abate_total`. Units match `baseline_emis`'s (emis_col-dependent).")
    hasproperty(regsub, :elec_demand_change) ||
        add_table_col!(data, :nonelec, :elec_demand_change, [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)], MWhLoad,
            "Induced change in electricity demand from abatement: `abate_total * elec_per_emis`.")

    # setup results formulas
    results_formulas = get_results_formulas(data)
    haskey(results_formulas, (:nonelec, :abate_emis_total)) ||
        add_results_formula!(data, :nonelec, :abate_emis_total, "SumYearly(abate_total)", NA,
            "Total emissions abated, summed across region-subsectors and years. Units match `baseline_emis`'s (emis_col-dependent).")
    haskey(results_formulas, (:nonelec, :resid_emis_total)) ||
        add_results_formula!(data, :nonelec, :resid_emis_total, "SumYearly(resid_emis)", NA,
            "Residual (unabated) emissions, summed across region-subsectors and years. Units match `baseline_emis`'s (emis_col-dependent).")
    haskey(results_formulas, (:nonelec, :baseline_emis_total)) ||
        add_results_formula!(data, :nonelec, :baseline_emis_total, "SumYearly(baseline_emis)", NA,
            "Baseline (pre-abatement) emissions, summed across region-subsectors and years. Units match `baseline_emis`'s (emis_col-dependent).")
    haskey(results_formulas, (:nonelec, :baseline_demand_total)) ||
        add_results_formula!(data, :nonelec, :baseline_demand_total, "SumYearly(baseline_demand)", MWhLoad,
            "Baseline electricity consumption (Cons0), summed across region-subsectors and years.")
    haskey(results_formulas, (:nonelec, :elec_response_total)) ||
        add_results_formula!(data, :nonelec, :elec_response_total, "SumYearly(elec_demand_change)", MWhLoad,
            "Induced change in electricity demand from abatement, summed across region-subsectors and years.")

    abate_total_raw = get_raw_result(data, Symbol("abate_total_$(name)"))::AbstractMatrix
    resid_emis_raw  = get_raw_result(data, Symbol("resid_emis_$(name)"))::AbstractMatrix

    # `regsub_idx` indexes this instance's rows as the model saw them (and so
    # indexes the raw result matrices); `row_idx` is the corresponding row of the
    # shared `:nonelec` table.
    for (regsub_idx, row_idx) in enumerate(row_idxs)
        regsub.abate_total[row_idx] = ByYear(Float64.(abate_total_raw[regsub_idx, :]))
        regsub.resid_emis[row_idx]  = ByYear(Float64.(resid_emis_raw[regsub_idx, :]))

        elec_per_emis = regsub.elec_per_emis[row_idx]
        regsub.elec_demand_change[row_idx] = ByYear([abate_total_raw[regsub_idx, yr_idx] * elec_per_emis[yr_idx] for yr_idx in 1:nyear])
    end
    
   
    return nothing
end