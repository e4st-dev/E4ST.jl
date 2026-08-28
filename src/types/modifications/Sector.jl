
"""
    Sector <: Modification

    sector is a supertype for the industrial, transportation, and building sectors. Non-electricity sectors are modeled through emissions and electricity demand baselines 
    whose emissions can be abated through paying a cost (as determined by MAC curves) and whose abatement impacts electricity demand. 

    'sector' subtypes (e.g. `Transportation`, `Buildings`, `Industrial`) are located in "src/types/sectors"

Abstract supertype for sectors.  Must implement the following interfaces:
* (required) [`sector!(sec::Sector)`](@ref)` 

####

## Sectors (Sector subtypes, see `src/types/sectors` for implementations)
* [`Transportation`](@ref)
* [`Buildings`](@ref)
* [`Industry`](@ref)

## Interface a concrete `sec <: Sector` must provide
* A struct with fields:
    - `mac_file::String`
    - `emis_baseline_file::String`
    - `elec_baseline_file::String`
    - `load_profile_file::String`
    - `electicity_file::String' own and cross-price elasticities for
      unit abatement (MWh/short ton), per Haiku eq. 10.

The following methods are defined for `Sector`.
* ['modify_raw_data!(sec::Sector, config, data)'](@ref)
* [`modify_setup_data!(sec::Sector, config, data)`](@ref)
* [`modify_model!(sec::Sector, config, data, model)`](@ref)
* [`modify_results!(sec::Sector, config, data)`](@ref)

## The `:nonelec` table
`modify_setup_data!` builds a `regsub` table (E4ST convention -- one row per
model entity, like `gen`/`bus`/`branch`/`dc_line`; here the entity is a
region-subsector, i.e. an `(area, subarea, subsector, emis_col)` combination)
at `data[:nonelec]`. Unlike the other `sector_<name>_*` tables, this one
is **shared across every `Sector` mod instance** rather than namespaced by
`name` -- so e.g. three separate Sector mods covering three different states
all contribute rows to the same table, matching how `gen`/`bus` are single
shared tables rather than one per mod. Each `modify_setup_data!` call checks
whether the table already exists (via [`has_table`](@ref)) and either creates
it or appends its own rows. Columns:
* `area`, `subarea`, `subsector`, `emis_col` -- row identity.
* `mod_name::Symbol` -- which Sector mod instance (`sec.name`) a row belongs
  to; `modify_model!`/`modify_results!` recover just their own instance's
  rows via `get_row_idxs(regsub, :mod_name => name)`.
* `baseline_emis`, `cons0`, `phi` -- `ByYear` containers, populated in
  `modify_setup_data!` from `emis`'s/`elec`'s wide y2016..y2050-style input
  columns and the Haiku eq. 10 elasticity ratio, respectively.
* `abate_total`, `resid_emis` -- `ByYear` containers, populated post-solve by
  `modify_results!` from the model's solved expression values.
* `elec_demand_change` -- `ByYear` container, populated post-solve by
  `modify_results!` as `abate_total · phi` (Haiku eq. 9's responsive term,
  in MWh) -- the induced change in electricity demand from abatement.

Note: MAC step row-indices (`mac_idxs`, into the `sector_<name>_mac_steps`
table) are *not* a column here -- they're a pure lookup with no standalone
meaning to someone inspecting `:nonelec`, so `modify_model!` builds them fresh
via `get_row_idxs` instead of persisting them alongside the columns above.

## Model contribution per sector `sec`
* Variables: `abate_<name>[s, k, y]` — tons abated at region-subsector `s`
  (indexes this instance's rows of the `regsub` table), MAC step `k` (local to
  that region-subsector, not a row index into `mac`), year `y`.
* Expressions:
    - `abate_total_<name>[i, y]` — total tons abated for region-subsector `i`
      in year `y` (`i` indexes this instance's rows of the `regsub` table).
    - `resid_emis_<name>[i, y]` — `baseline_emis[i, y] - abate_total[i, y]`.
    - `cost_sector_<name>_obj[y]` — MAC abatement cost (area under the MAC
      curve: `sum(abate[i,k,y] * mac.price[mac_idxs[i][k]])`), added to the model objective
      via [`add_obj_exp!`](@ref). Residual (unabated) emissions carry no
      direct cost term here -- the only price signal on them comes from
      whatever `EmissionCap` covers this sector's region-subsectors.
* Constraints: `cons_abate_cap_<name>[i, y]` — `abate_total <= baseline_emis`.

Note that the emissions are added in EmissionCap

## Pbal coupling
`modify_model!` unconditionally calls [`add_sector_electrification_load!`](@ref),
which adds only the responsive electrification load (`abate_total · phi`) into
`plserv_bus`. For now it distributes that load equally across hours and equally
across the buses matching each row's `(area, subarea)` -- both placeholders
pending a weighted rule (hour_weights, load profile shape, population, existing
load share, etc.). Baseline electricity (`Cons0`) is not added — E4ST already carries it as a
primary input.


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

### All sector subtypes 

"""
    modify_raw_data!(mod::SectorEmissions, config, data)

Loads input files into tables:
':sector_<name>_mac_steps', ':sector_<name>_baseline_emissions', ':sector_<name>_baseline_load_profile'

# sector_mac_steps
# edit table to append MAC curves from the preprocessing step by subsector 
#
# :region - string, region name to match to bus table (state should be fine?)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
# :step_id - int, step id for MAC curve, ordered by price 
# :price - float, MAC for given step
# :quantity - float, abatement quantity for given step

# sector_emis_baseline
# :src_file - string, description of source data file for baseline emissions
# :description - string, description of the baseline emissions row
# :set
# :area - string, geographic area of aggregation (state)
# :subarea - string, state name or other subregion name to match to bus table
# :sector - string, sector name (Transportation, Industry, Buildings)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
# :emis_col - string, the pollutant this row's emissions are (e.g. "emis_co2", "emis_so2"),
#             matched against EmissionCap.emis_col in add_resid_emis_to_caps! so a
#             region-subsector's residual emissions only flow into caps regulating the
#             same pollutant. A single (area, subarea, subsector) can appear as multiple
#             rows, one per pollutant.
# :y2016-y2050 - float, baseline emissions for given year in short tons

# sector_load_profile 
# :area
# :subarea

# sector_elec_baseline
#
#

# sector_elec_per_ton

"""

"""
    modify_raw_data!(sec::Sector, config, data)

Reads in necessary input data files for the sector

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
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:step_id, Int64, NA, false, "Identifier for this MAC step.  Informational only -- step order (and thus the abatement step index `k`) is determined by sorting rows on `price` within each (area, subarea, subsector), not by this column."),
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
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
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
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:y_, Float64, MWhLoad, true, "The baseline electricity consumption (Cons0) for this region-subsector, per year.  Include a column for each year in the simulation, i.e. `:y2020`, `:y2030`, etc.  Used only to compute the electrification response coefficient `phi`; E4ST's total baseline load is not adjusted by these values, since it already ingests baseline demand as a primary input."),
    )
    return df
end

@doc """
    summarize_table(::Val{:load_profile})

Placeholder -- the `sector_<name>_load_profile` table is not yet wired up
(its `read_table!` call is commented out in `modify_raw_data!`, and
`add_sector_electrification_load!` currently splits responsive
electrification load equally across hours rather than reading a shape from
this table). Columns below are inferred from the `lp`/`lp_index`/`hour_cols`
TODO comments in `add_sector_electrification_load!`, which key rows by
`(area, subarea, subsector, year)` and reserve an hourly-shape column per
hour. Update this once the table is actually implemented.

$(table2markdown(summarize_table(Val(:load_profile))))
"""
function summarize_table(::Val{:load_profile})
    df = TableSummary()
    push!(df,
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:year, String, Year, false, "The year this load profile applies to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\".  Leave blank to apply to all years."),
        (:status, Bool, NA, false, "Whether or not to use this load profile row."),
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
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:subsector, AbstractString, NA, true, "Refers to the subsector these data correspond with (e.g. a NAICS code for the industrial sector, or LDV/MHDV/transit for transportation).  Can be left blank if there are no subsectors for this sector."),
        (:own_elast, Float64, NA, true, "The semi-elasticity of emissions in response to change in the carbon price for this region-subsector, used with `cross_elast` and baseline electricity/emissions to compute the electrification response coefficient `phi` (Haiku eq. 10)."),
        (:cross_elast, Float64, NA, true, "The semi-elasticity of electricity demand with respect to a change in the carbon price for this region-subsector, used with `own_elast` and baseline electricity/emissions to compute the electrification response coefficient `phi` (Haiku eq. 10)."),
    )
    return df
end


"""
    modify_setup_data!(sec::Sector, config, data)

Creates or appends to a shared `:nonelec` table to store emissions and electricity pathways for each sector. Uses the elasticity table and baseline values to calculate and store `phi`: the electrification response per unit of abatement.

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

    # sort MAC steps ascending in price (per region-subsector) so that they are listed in step_order
    # although table is likely read in sorted
    sort!(mac, [:area, :subarea, :subsector, :price])
    mac.subsector = string.(mac.subsector)

    # If any simulation year is entirely missing from emis or elec, there's no
    # complete baseline for any region-subsector in this mod -- exclude all of
    # them (no abatement option) rather than silently defaulting to 0/NaN.
    missing_years = filter(y -> !hasproperty(emis, Symbol(y)) || !hasproperty(elec, Symbol(y)), years)
    if !isempty(missing_years)
        @warn "Sector $name: missing baseline emissions/electricity data for year(s) $missing_years -- excluding all region-subsectors for this Sector mod (no abatement option)"
        return nothing
    end

    # Attach each emis row's own_elast/cross_elast (elast) and Cons0 (elec) by
    # (area, subarea, subsector) via direct Dict lookups. A regsub with no
    # match in either is excluded entirely (no abatement option), rather than
    # kept with a NaN phi.
    elast_lookup = Dict((r.area, r.subarea, r.subsector) => (r.own_elast, r.cross_elast) for r in eachrow(elast))
    elec_lookup = Dict((r.area, r.subarea, r.subsector) => r for r in eachrow(elec))

    keep_idxs = findall(r -> haskey(elast_lookup, (r.area, r.subarea, r.subsector)) && haskey(elec_lookup, (r.area, r.subarea, r.subsector)), eachrow(emis))
    n_excluded = nrow(emis) - length(keep_idxs)
    n_excluded > 0 && @warn "Sector $name: excluding $n_excluded region-subsector row(s) with no matching elasticity or electricity baseline row (no abatement option for those)"
    emis = emis[keep_idxs, :]

    # build rows for the shared `:nonelec` table: one row per region-subsector, with `baseline_emis`/`cons0`/`phi` as `ByYear` columns
    #   phi = (cross_elast · Cons0) / (own_elast · EmisSector0)   (Haiku eq. 10)
    # phi is set to `NaN` only for a zero denominator (own_elast or emis0 == 0), since every remaining row is now guaranteed a full data match

    # `:nonelec` is a single table shared across every Sector mod
    # `mod_name` identifies which mod instance each row belongs to
    regsub_new = select(emis, [:area, :subarea, :subsector, :emis_col])
    regsub_new.mod_name = fill(name, nrow(emis))

    baseline_emis_col = Vector{ByYear}(undef, nrow(emis))
    cons0_col         = Vector{ByYear}(undef, nrow(emis))
    phi_col           = Vector{ByYear}(undef, nrow(emis))

    for (i, row) in enumerate(eachrow(emis))
        own_elast, cross_elast = elast_lookup[(row.area, row.subarea, row.subsector)]
        elec_row = elec_lookup[(row.area, row.subarea, row.subsector)]

        emis0_vals = [Float64(row[Symbol(y)]) for y in years]
        cons0_vals = [Float64(elec_row[Symbol(y)]) for y in years]
        phi_vals = [
            (own_elast == 0.0 || emis0_vals[j] == 0.0) ? NaN : (cross_elast * cons0_vals[j]) / (own_elast * emis0_vals[j])
            for j in eachindex(years)
        ]

        baseline_emis_col[i] = ByYear(emis0_vals)
        cons0_col[i]         = ByYear(cons0_vals)
        phi_col[i]           = ByYear(phi_vals)
    end

    regsub_new.baseline_emis           = baseline_emis_col
    regsub_new.baseline_demand         = cons0_col
    regsub_new.phi                     = phi_col

    if has_table(data, :nonelec)
        append!(get_table(data, :nonelec), regsub_new)
    else
        data[:nonelec] = regsub_new
    end

    return nothing
end


"""
    modify_model!(sec::Sector, config, data, model)

Set up the sector's abatement and residual emissions variables, constraints (non-negativity), and objective function contribution. The emissions expressoin for all Sector mods is created here, but it is added to the relevant constraint through
the respective mod (e.g., the EmissionCap mod will search for a Sector mod and add the sector emissions to the model-wide emissions expression). 

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

     # Load-profile lookup by (area, subarea, subsector, year) -> row index in lp, and passied as an argument to `add_sector_electrification_load!`
    # `lp_years_index` is a fallback for when there's no exact-year match in
    # `lp_index`: (area, subarea, subsector) -> [(year, row index in lp), ...],
    # used to find the closest available year instead of skipping outright.
    lp_index = Dict{NTuple{4, String}, Int}()
    lp_years_index = Dict{NTuple{3, String}, Vector{Tuple{Int,Int}}}()
    for (i, row) in enumerate(eachrow(lp))
        area, subarea, subsector = string(row.area), string(row.subarea), string(row.subsector)
        yearstr = string(row.year)
        lp_index[(area, subarea, subsector, yearstr)] = i
        isempty(yearstr) && continue
        push!(get!(lp_years_index, (area, subarea, subsector), Tuple{Int,Int}[]), (year2int(yearstr), i))
    end

    # MAC step row-indices (into `mac`, sorted ascending in price by
    # `modify_setup_data!`) for each region-subsector, year-invariant. A pure
    # lookup with no standalone meaning outside this function, so it's built
    # fresh here rather than persisted as a `:nonelec` column (unlike
    # `lp_index` above, this one only needs `regsub`'s row identity, not a
    # `year` dimension `regsub` doesn't have).
    mac_idxs = map(1:nregsub) do i
        idxs = get_row_idxs(mac, :area => regsub.area[i], :subarea => regsub.subarea[i], :subsector => regsub.subsector[i])
        isempty(idxs) && @warn "Sector $name: no MAC steps found for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i]). Emissions will be added to constraint but there will be no way to abate."
        idxs
    end
    nsteps = length.(mac_idxs)

    # Baseline emissions per (region-subsector, year), read directly off
    # regsub's `baseline_emis` ByYear column -- region-subsector i is
    # regsub's row i.
    baseline_emis = [regsub.baseline_emis[i][yi] for i in 1:nregsub, yi in 1:nyear]

    abate_name       = Symbol("abate_$(name)")
    abate_total_name = Symbol("abate_total_$(name)")
    resid_name       = Symbol("resid_emis_$(name)")
    cons_name        = Symbol("cons_abate_cap_$(name)")
    cost_name        = Symbol("cost_sector_$(name)_obj")
    
    
    # abatement variable, indexed by [i,k,y] where i is the region-subsector, k is the step on the mac curve, and y is the year
    model[abate_name] = @variable(model,
        [i in 1:nregsub, k in 1:nsteps[i], y in 1:nyear],
        lower_bound = 0,
        upper_bound = mac.quantity[mac_idxs[i][k]],
        base_name = String(abate_name)
    )
    abate = model[abate_name]

    # set up abatement expression, index by region-subsector,year and sums over each step in abate[i,k,y]
    model[abate_total_name] = @expression(model,
        [i in 1:nregsub, y in 1:nyear],
        sum(abate[i, k, y] for k in 1:nsteps[i]; init = AffExpr(0.0))
    )
    abate_total = model[abate_total_name]

    # residual emissions expression (baseline emissions minus abated emissions), indexed by [i, y] where is the region-subsector
    model[resid_name] = @expression(model,
        [i in 1:nregsub, y in 1:nyear],
        baseline_emis[i, y] - abate_total[i, y]
    )
    resid_emis = model[resid_name]

    # constraint so that abated emissions in a year can not be greater than the baseline emissions in that year
    model[cons_name] = @constraint(model,
        [i in 1:nregsub, y in 1:nyear],
        abate_total[i, y] <= baseline_emis[i, y]
    )

    # couple the load from the electrification response with power-balancing equation
    # the baseline electricity (Cons0) is NOT added, because load projections already capture the baseline demand from each of these sectors
    add_sector_electrification_load!(sec, config, data, model, regsub, abate_total, lp, lp_index, lp_years_index)
    
    # abatement cost expression, summed over regsub and steps so that it is indexed by year only
    model[cost_name] = @expression(model,
        [y in 1:nyear],
        sum(abate[i, k, y] * mac.price[mac_idxs[i][k]] for i in 1:nregsub, k in 1:nsteps[i]; init = AffExpr(0.0))
    )

    # add abatement costs to objective term, in units of $/short ton of emissions
    add_obj_exp!(data, model, SectorTerm(), cost_name; oper = +)
    return nothing
end

"""
    named `SectorTerm` for the sector's contribution to the objective function.
Used in `add_obj_term!` to add the sector's MAC abatement cost to the objective function.
Residual (unabated) emissions carry no direct cost term here -- see `cost_sector_<name>_obj`.

    look at emissions price modification -- might use per MWh term, might be reusable if it's just per unit of emissions
"""

  struct SectorTerm <: Term end



"""
    _sector_region_buses(bus, nbus)

Returns a closure `buses_for(area, subarea) -> Vector{Int}` giving the bus
indices where `bus[!, Symbol(area)] == subarea`, memoized per `(area, subarea)`.
Shared by the baseline- and responsive-load couplings.
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

Looks up a load-profile row for `(area, subarea, sub)` at year `y`: an
exact-year match in `lp_index` if one exists, else the closest available year
for that key from `lp_years_index` (in which case `closest_yr` is that year;
otherwise `closest_yr` is `nothing`). Returns `nothing` if there's no data at
all for `(area, subarea, sub)`. `sub` is usually a subsector, but see the
two-stage lookup in `add_sector_electrification_load!`, which also tries this
with a sector name in place of `sub`.
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
    add_sector_electrification_load!(sec::Sector, config, data, model,
                                     regsub, abate_total, lp, lp_index)

Adds the *responsive* electrification load induced by abatement into
`plserv_bus`, implementing the consumption/abatement linkage of Haiku eq. 9:

    Cons_{y,r,sec} = Cons0_{y,r,sec} + Σ_k EmisAbatement_{y,r,sec,k} · phi_{y,r,sec}

where `phi` (short tons -> MWh) is computed in `modify_setup_data!` per Haiku
eq. 10, `phi = (cross_elast · Cons0) / (own_elast · EmisSector0)`, and stored as
`regsub.phi`, a `ByYear` column. `Cons0` (baseline electricity) is NOT added
by the Sector modification — E4ST already carries total baseline electric
demand as a primary input, so this function adds only the second (responsive)
term to avoid double-counting.

For each region-subsector `i` (a row of the `regsub` table, i.e. an
`(area, subarea, subsector)` combination) and year `y`:
* `annual_responsive_MWh = abate_total[i, y] · phi[i, y]` (an affine expression
  in the `abate` variables).
* That annual energy is distributed across the `nhr` representative hours
  according to `lp`'s hourly shape for this region-subsector/year (`lp_row.h1
  .. lp_row.hn`, weighted by `hour_weights` and renormalized by
  `annual_shape` so the shape need not already sum to 1). It's split equally
  across the buses in `(area, subarea)`:

      plserv_bus[b, y, h] += (1/n_buses) · phi[i, y] · (lp_row.h_h / annual_shape) · abate_total[i, y]

  If `lp` has no row for a given region-subsector/year, the closest available
  year for that region-subsector (via `lp_years_index`) is used instead; only
  when there's no `lp` row *at all* for the region-subsector is that
  region-subsector/year's responsive load skipped with a warning rather than
  falling back to an equal split. (Every `lp` row is guaranteed to have a
  nonzero annual shape -- `modify_setup_data!` validates this up front and
  errors otherwise, so that case can't arise here.)

Because the coefficient multiplies the JuMP expression `abate_total[i, y]`, the
LP is forced to serve more electric load whenever it chooses to abate more —
the endogenous electrification feedback.

`lp` (the `sector_<name>_load_profile` table), `lp_index` (a
`(area, subarea, subsector, year) -> row index in lp` lookup for exact-year
matches), and `lp_years_index` (a `(area, subarea, subsector) -> [(year, row
index), ...]` fallback used to find the closest year when there's no exact
match) are built once by the caller, `modify_model!`, and passed in here
rather than being re-fetched from `data` -- the same way `regsub`/`abate_total`
already are.
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
    # `:h_` -> `h1`, `h2`, ... `hn` (E4ST's wide-hour-column convention, see
    # e.g. `summarize_table(::Val{:load_profile})`/`AdjustHourly`), not
    # `hour1`, `hour2`, ....
    hour_cols = [Symbol("h$h") for h in 1:nhr]
    hour_weights = get_hour_weights(data)

    n_applied = 0
    for i in 1:nregsub, (yi, y) in enumerate(years)
        phi = regsub.phi[i][yi]
        if isnan(phi)
            error("Sector $name: no phi (eq. 10) for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i]), year=$y; can't have emission abatement without electrification")
            continue
        end
        phi == 0.0 && continue   # no electrification response for this region-subsector/year

        # Look up this region-subsector/year's hourly load shape. `lp_row`'s
        # `h1..hn` values need not already be normalized (`get_sector_load_shape`
        # in `SectorLoadProfile.jl` does normalize them so that `annual_shape`
        # below comes out to ~1, but dividing through here makes this robust
        # to an unnormalized `lp` too).
        area, subarea, subsector = string(regsub.area[i]), string(regsub.subarea[i]), string(regsub.subsector[i])
        target_yr = year2int(string(y))

        result = _lp_lookup(lp_index, lp_years_index, area, subarea, subsector, y, target_yr)
        lookup_sub = subsector
        if result === nothing
            # Some sectors (e.g. buildings) provide a single load profile per
            # area/subarea rather than one per subsector -- in that case the
            # lp table's `subsector` column holds the sector name itself.
            lookup_sub = string(sec.sector)
            result = _lp_lookup(lp_index, lp_years_index, area, subarea, lookup_sub, y, target_yr)
        end
        if result === nothing
            error("Sector $name: no load profile found for area=$area, subarea=$subarea, subsector=$subsector (also tried sector-level subsector=$(sec.sector)), can't have emission abatement without electrification.")
            continue
        end
        lp_row_idx, closest_yr = result
        if closest_yr !== nothing
            @info "Sector $name: no load profile for area=$area, subarea=$subarea, subsector=$lookup_sub, year=$y; using closest available year y$closest_yr instead"
        end
        lp_row = lp[lp_row_idx, :]
        # annual_shape is guaranteed > 0 here -- every lp row was validated in modify_setup_data!
        annual_shape = sum(lp_row[hour_cols[h]] * hour_weights[h] for h in 1:nhr)

        buses = buses_for(regsub.area[i], regsub.subarea[i])
        isempty(buses) && continue
        share = 1.0 / length(buses)

        # Distribute the responsive annual MWh (abate_total[i,y] * phi[i,y])
        # across the nhr representative hours according to lp_row's shape,
        # rather than splitting it equally.
        applied_this = false
        for h in 1:nhr
            coef = share * phi * lp_row[hour_cols[h]] / annual_shape
            coef == 0.0 && continue
            for b in buses
                add_to_expression!(plserv_bus[b, yi, h], coef, abate_total[i, yi])
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

Writes the solved `abate_total_<name>`/`resid_emis_<name>` expressions back
onto this instance's rows (`mod_name == sec.name`) of the shared
`:nonelec` table, as `ByYear` columns (`abate_total`, `resid_emis`) --
alongside `baseline_emis`, `cons0`, and `phi`, which are populated the same
way (per-row `ByYear`) in `modify_setup_data!`. Solved values are retrieved
via [`get_raw_result`](@ref) rather than the (by now emptied) JuMP `model`,
since `modify_results!` runs after `parse_results!` has already pulled every
registered variable/expression value into `data[:results][:raw]`.

Also writes `elec_demand_change`, the induced change in electricity demand
(Haiku eq. 9's responsive term, `abate_total · phi`, in MWh -- see
[`add_sector_electrification_load!`](@ref)). Unlike `abate_total`/`resid_emis`,
this isn't a separate JuMP expression -- `phi` is a precomputed constant
(not a decision variable), so it's just an elementwise product of the
already-retrieved `abate_total` and the `phi` column `modify_setup_data!`
already populated.

Since `:nonelec` is shared across every Sector mod instance, the
`abate_total`/`resid_emis`/`elec_demand_change` columns are created (filled
with a `NaN`-`ByYear` placeholder for every row) the first time any
instance's `modify_results!` runs; each instance then overwrites only its
own rows. Which instance runs first doesn't matter -- `process_results!`
calls `modify_results!` for every mod, so every row ends up written by the
time all Sector instances have run.
"""

# Post-solve, `modify_results!` adds `abate_total`/`resid_emis` ByYear
    # columns to this same table.
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
            "Induced change in electricity demand from abatement: `abate_total * phi`.")

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

    for (i, row_idx) in enumerate(row_idxs)
        regsub.abate_total[row_idx] = ByYear(Float64.(abate_total_raw[i, :]))
        regsub.resid_emis[row_idx]  = ByYear(Float64.(resid_emis_raw[i, :]))

        phi = regsub.phi[row_idx]
        regsub.elec_demand_change[row_idx] = ByYear([abate_total_raw[i, yi] * phi[yi] for yi in 1:nyear])
    end

    
   
    return nothing
end