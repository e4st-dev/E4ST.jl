
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
  `modify_setup_data!` from `base`'s/`elec`'s wide y2016..y2050-style input
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
* Variables: `abate_<name>[k, y]` — tons abated at MAC step `k`, year `y`.
* Expressions:
    - `abate_total_<name>[i, y]` — total tons abated for region-subsector `i`
      in year `y` (`i` indexes this instance's rows of the `regsub` table).
    - `resid_emis_<name>[i, y]` — `baseline_emis[i, y] - abate_total[i, y]`.
    - `cost_sector_<name>_obj[y]` — MAC abatement cost (area under the MAC
      curve: `sum(abate[k,y] * mac.price[k])`), added to the model objective
      via [`add_obj_exp!`](@ref). Residual (unabated) emissions carry no
      direct cost term here -- the only price signal on them comes from
      whatever `EmissionCap` covers this sector's region-subsectors.
* Constraints: `cons_abate_cap_<name>[i, y]` — `abate_total <= baseline_emis`.


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


# Comes after policy (needs emissions cap to work, appends emissions to cap's emis_total expression)
mod_rank(::Type{<:Sector}) = mod_rank(EmissionCap) + 0.1

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
    name = sec.name
    mac_key   = Symbol("sector_$(name)_mac_file")
    emis_key  = Symbol("sector_$(name)_emis_baseline_file")
    elec_key  = Symbol("sector_$(name)_elec_baseline_file")
    lp_key    = Symbol("sector_$(name)_load_profile_file")
    elast_key = Symbol("sector_$(name)_elasticity_file")


    config[mac_key]  = sec.mac_file
    config[emis_key] = sec.emis_baseline_file
    config[elec_key] = sec.elec_baseline_file
    config[lp_key]   = sec.load_profile_file
    config[elast_key] = sec.elasticity_file

    # Each table is read via the plain `read_table` (not `read_table!`) so
    # that type coercion/required-column validation happens against the
    # generic, shared `summarize_table` entry (:mac_steps, :emis_baseline,
    # ...) -- a fixed symbol, one per table kind, matching what
    # `read_summary_table!` registers -- and only afterward gets stored under
    # this instance's namespaced `data` key. This mirrors
    # `Adjust.modify_raw_data!` (see `Adjust.jl`), which validates against the
    # fixed `Adjust{T}` type parameter `T` before storing under the free-form
    # `mod.name`. Using `read_table!` here instead would look up the summary
    # by the namespaced key itself (e.g. `sector_$(name)_emis_baseline`),
    # which no `summarize_table` method is ever defined for, silently
    # skipping all type coercion and required-column checks.
    @info "Loading sector_$(name)_mac_steps from $(config[mac_key])"
    data[Symbol("sector_$(name)_mac_steps")] = read_table(data, config[mac_key], :mac_steps)

    @info "Loading sector_$(name)_emis_baseline from $(config[emis_key])"
    data[Symbol("sector_$(name)_emis_baseline")] = read_table(data, config[emis_key], :emis_baseline)

    @info "Loading sector_$(name)_elec_baseline from $(config[elec_key])"
    data[Symbol("sector_$(name)_elec_baseline")] = read_table(data, config[elec_key], :elec_baseline)

    @info "Loading sector_$(name)_load_profile from $(config[lp_key])"
    data[Symbol("sector_$(name)_load_profile")] = read_table(data, config[lp_key], :load_profile)

    @info "Loading sector_$(name)_elasticity from $(config[elast_key])"
    data[Symbol("sector_$(name)_elasticity")] = read_table(data, config[elast_key], :elasticity)
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
        (:h_, Float64, Ratio, true, "Share of this region-subsector's annual responsive electrification load falling in each hour, intended to replace the current equal-split-across-hours placeholder in `add_sector_electrification_load!`.  Include a column for each hour in the hours table, i.e. `:h1`, `:h2`, ... `:hn`."),
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

Adds this mod instance's rows to the shared `:nonelec` table (see the
`Sector` docstring): joins elasticities and baseline electricity onto the
baseline emissions table, computes `phi` (Haiku eq. 10), sorts MAC steps
ascending in price, and builds a lookup from each region-subsector to its MAC
step indices.
"""


function modify_setup_data!(sec::Sector, config, data)
    name = sec.name
    @info "Setting up Sector: $name"

    mac  = get_table(data, Symbol("sector_$(name)_mac_steps"))
    base = get_table(data, Symbol("sector_$(name)_emis_baseline"))
    elec = get_table(data, Symbol("sector_$(name)_elec_baseline"))
    lp   = get_table(data, Symbol("sector_$(name)_load_profile"))
    elast = get_table(data, Symbol("sector_$(name)_elasticity"))

    years = get_years(data)

    # base/elec are read wide (one row per (area, subarea, subsector), with a
    # y2016..y2050-style column per year) -- matching E4ST's established
    # convention for year-varying input tables (e.g. AdjustYearly's `:y_`
    # columns). Their year columns get consolidated below, per row, into
    # `ByYear` columns on a single derived `regsub` table (E4ST convention --
    # like `gen`/`bus`/`branch`/`dc_line`, one row per model entity, here a
    # region-subsector). base additionally carries an emis_col column
    # identifying which pollutant each row's emissions are, so a subsector
    # can have separate rows (and thus separate baselines/abatement) per
    # pollutant; regsub carries that through too.
    base.area = string.(base.area)
    base.subarea = string.(base.subarea)
    base.subsector = string.(base.subsector)
    base.emis_col = string.(base.emis_col)
    elec.area = string.(elec.area)
    elec.subarea = string.(elec.subarea)
    elec.subsector = string.(elec.subsector)

    # Elasticities and baseline electricity (Cons0) are joined onto base's key
    # columns (area, subarea, subsector) -- matching E4ST's join convention
    # for attaching cross-table attributes (see e.g. `newgens.jl`,
    # `io/load.jl`, `io/data.jl`) -- rather than looked up through hand-built
    # Dicts. Assumes elast/elec have at most one row per (area, subarea,
    # subsector), same as the Dict-based lookups this replaces implicitly
    # assumed (last match silently wins there; a duplicate here instead
    # duplicates the joined row, which sort!(..., :_row_id) below would then
    # misalign -- not expected to occur given the input format).
    elast.area = string.(elast.area)
    elast.subarea = string.(elast.subarea)
    elast.subsector = string.(elast.subsector)
    elast.own_elast = Float64.(elast.own_elast)
    elast.cross_elast = Float64.(elast.cross_elast)

    keys3 = [:area, :subarea, :subsector]

    # _row_id preserves base's row order through the joins, independent of
    # DataFrames' join-order guarantees.
    base_keys = select(base, keys3)
    base_keys._row_id = 1:nrow(base)

    merged = leftjoin(base_keys, select(elast, [keys3; :own_elast; :cross_elast]), on = keys3)

    elec_ycols = [Symbol(y) for y in years if hasproperty(elec, Symbol(y))]
    elec_sel = select(elec, [keys3; elec_ycols])
    for ycol in elec_ycols
        elec_sel[!, ycol] = Float64.(elec_sel[!, ycol])
    end
    rename!(elec_sel, [ycol => Symbol("cons0_", ycol) for ycol in elec_ycols])
    merged = leftjoin(merged, elec_sel, on = keys3)

    sort!(merged, :_row_id)

    n_no_elast = count(ismissing, merged.own_elast)
    n_no_elast > 0 && @warn "Sector $name: no elasticities for $n_no_elast region-subsector row(s); phi=NaN (no electrification response) for those rows"

    missing_base_years = [y for y in years if !hasproperty(base, Symbol(y))]
    for y in missing_base_years
        @warn "Sector $name: no baseline emissions column for year $y; treating as 0 for all region-subsectors"
    end
    missing_cons0_years = [y for y in years if !hasproperty(merged, Symbol("cons0_", y))]
    for y in missing_cons0_years
        @warn "Sector $name: no baseline electricity (Cons0) for year $y; phi=NaN for all region-subsectors in $y"
    end

    # Validate per-row (area, subarea) against the bus table. `area` names a bus
    # column ("state", "bus_idx", ...); `subarea` is one of that column's
    # values. This mirrors the load_shape/load_match pattern in `load.jl` and
    # lets a single file mix nodal rows with state-aggregated rows.
    bus = get_table(data, :bus)
    for (tbl_name, tbl) in ((:mac, mac), (:base, base), (:elec, elec), (:lp, lp), (:elast, elast))
        for area in unique(tbl.area)
            sym = Symbol(area)
            hasproperty(bus, sym) || @warn "Sector $name: bus table has no column `$area` referenced in $(tbl_name) table"
        end
    end

    # MAC steps sorted ascending in price per region-subsector, so that the
    # `mac_idxs` lookup built in `modify_model!` (via `get_row_idxs`) lists
    # them in step order -- mac's row position IS the step index `k` used to
    # index the `abate[k,y]` variable there.
    sort!(mac, [:area, :subarea, :subsector, :price])
    mac.subsector = string.(mac.subsector)

    # Build this mod instance's rows for the shared `:nonelec` table:
    # one row per region-subsector (matching base's row order), with
    # `baseline_emis`/`cons0`/`phi` as `ByYear` columns -- consolidating
    # base's and elec's wide y2016..y2050-style columns, and the derived
    # Haiku eq. 10 elasticity ratio, onto a single table (E4ST convention:
    # see `gen`/`bus`/`branch`/`dc_line`). MAC step indices (`mac_idxs`) are
    # *not* stored here -- unlike `baseline_emis`/`cons0`/`phi`, they're a pure
    # lookup into `mac` with no standalone meaning to someone inspecting
    # `:nonelec`, so (like `lp_index` in `add_sector_electrification_load!`)
    # they're built fresh where consumed, in `modify_model!`, instead of
    # persisted here.
    # Post-solve, `modify_results!` adds `abate_total`/`resid_emis` ByYear
    # columns to this same table.
    #   phi = (cross_elast · Cons0) / (own_elast · EmisSector0)   (Haiku eq. 10)
    # A cell is `NaN` (rather than 0.0) when phi couldn't be computed (no
    # elasticity/Cons0 match, or a zero denominator), distinguishing it from
    # a legitimately-zero response.
    #
    # `:nonelec` is a single table shared across every Sector mod
    # instance (not namespaced by `name`, unlike the other `sector_<name>_*`
    # tables), so that e.g. three separate Sector mods covering three
    # different states all contribute rows to the same table -- matching how
    # `gen`/`bus` are single shared tables rather than one per mod. `mod_name`
    # identifies which mod instance each row belongs to, so `modify_model!`/
    # `modify_results!` can recover just this instance's rows (in the same
    # relative order they were added here) via `get_row_idxs(regsub,
    # :mod_name => name)`.
    regsub_new = select(base, [:area, :subarea, :subsector, :emis_col])
    regsub_new.mod_name = fill(name, nrow(base))

    baseline_emis_col = Vector{ByYear}(undef, nrow(base))
    cons0_col         = Vector{ByYear}(undef, nrow(base))
    phi_col           = Vector{ByYear}(undef, nrow(base))

    for i in 1:nrow(base)
        row = base[i, :]
        own_elast, cross_elast = merged.own_elast[i], merged.cross_elast[i]

        emis0_vals = Float64[]
        cons0_vals = Float64[]
        phi_vals   = Float64[]
        for y in years
            ycol = Symbol(y)
            emis0 = hasproperty(base, ycol) ? Float64(row[ycol]) : 0.0
            push!(emis0_vals, emis0)

            cons0_ycol = Symbol("cons0_", ycol)
            cons0 = hasproperty(merged, cons0_ycol) ? merged[i, cons0_ycol] : missing
            push!(cons0_vals, coalesce(cons0, NaN))

            phi_val = (ismissing(own_elast) || ismissing(cross_elast) || ismissing(cons0) || own_elast == 0.0 || emis0 == 0.0) ?
                NaN : (cross_elast * cons0) / (own_elast * emis0)
            push!(phi_vals, phi_val)
        end
        baseline_emis_col[i] = ByYear(emis0_vals)
        cons0_col[i]         = ByYear(cons0_vals)
        phi_col[i]           = ByYear(phi_vals)
    end

    regsub_new.baseline_emis = baseline_emis_col
    regsub_new.cons0         = cons0_col
    regsub_new.phi           = phi_col

    if has_table(data, :nonelec)
        append!(get_table(data, :nonelec), regsub_new)
    else
        data[:nonelec] = regsub_new
    end

    return nothing
end


"""
    modify_model!(sec::Sector, config, data, model)

Implements the sector's abatement and residual emissions variables,
constraints (non-negativity), objective function contribution, and emissions cap contribution via [`add_resid_emis_to_caps!`](@ref).
Also feeds residual emissions into any covering `EmissionCap`, and adds the
sector's responsive electric load to `plserv_bus` via
[`add_sector_electrification_load!`](@ref). Reads region-subsector data from
this instance's rows (`mod_name == sec.name`) of the shared `:nonelec`
table built by `modify_setup_data!`; the solved `abate_total`/`resid_emis`
values get written back onto those same rows post-solve by
[`modify_results!`](@ref).

"""

function modify_model!(sec::Sector, config, data, model)
    name = sec.name
    @info "Adding Sector $name to the model"

    mac = get_table(data, Symbol("sector_$(name)_mac_steps"))
    lp  = get_table(data, Symbol("sector_$(name)_load_profile"))
    # Load-profile lookup by (area, subarea, subsector, year) -> row index in
    # lp, built once here (not per row/year/hour inside
    # `add_sector_electrification_load!`'s loop) and passed down as an
    # explicit argument, the same way `regsub`/`abate_total` already are --
    # rather than round-tripped through a bespoke `data[...]` key.
    lp_index = Dict{NTuple{4, String}, Int}()
    for (i, row) in enumerate(eachrow(lp))
        lp_index[(string(row.area), string(row.subarea), string(row.subsector), string(row.year))] = i
    end
    # `regsub` is a view onto this instance's rows only, within the table
    # shared across every Sector mod instance -- see `:nonelec` in
    # `modify_setup_data!`. A view (rather than a copy) is fine here since
    # modify_model! only reads columns off it, never adds new ones.
    regsub_full = get_table(data, :nonelec)
    regsub = view(regsub_full, get_row_idxs(regsub_full, :mod_name => name), :)
    years = get_years(data)
    nyear = length(years)
    nstep = nrow(mac)
    nregsub = nrow(regsub)

    if nstep == 0 || nregsub == 0
        @warn "Sector $name: empty MAC or baseline table, skipping model modification"
        return nothing
    end

    # MAC step row-indices (into `mac`, sorted ascending in price by
    # `modify_setup_data!`) for each region-subsector, year-invariant. A pure
    # lookup with no standalone meaning outside this function, so it's built
    # fresh here rather than persisted as a `:nonelec` column (unlike
    # `lp_index` above, this one only needs `regsub`'s row identity, not a
    # `year` dimension `regsub` doesn't have).
    mac_idxs = map(1:nregsub) do i
        idxs = get_row_idxs(mac, :area => regsub.area[i], :subarea => regsub.subarea[i], :subsector => regsub.subsector[i])
        isempty(idxs) && @warn "Sector $name: no MAC steps found for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i])"
        idxs
    end

    # Baseline emissions per (region-subsector, year), read directly off
    # regsub's `baseline_emis` ByYear column -- region-subsector i is
    # regsub's row i.
    baseline_emis = [regsub.baseline_emis[i][yi] for i in 1:nregsub, yi in 1:nyear]

    abate_sym       = Symbol("abate_$(name)")
    abate_total_sym = Symbol("abate_total_$(name)")
    # like equation 7 in Nick's HAIKU documentation
    resid_sym       = Symbol("resid_emis_$(name)")
    # like equation 8 in Nick's HAIKU documentation
    cons_sym        = Symbol("cons_abate_cap_$(name)")
    # like equation 6 in Nick's HAIKU documentation 
    cost_sym        = Symbol("cost_sector_$(name)_obj")

    model[abate_sym] = @variable(model,
        [k in 1:nstep, y in 1:nyear],
        lower_bound = 0,
        upper_bound = mac.quantity[k],
        base_name = String(abate_sym)
    )
    abate = model[abate_sym]

    # abate_total is indexed by (region-subsector, year): region-subsector i
    # is regsub's row i (area, subarea, subsector), and mac_idxs[i] (built
    # above) gives the MAC step indices for region-subsector i, independent
    # of year.
    model[abate_total_sym] = @expression(model,
        [i in 1:nregsub, y in 1:nyear],
        sum(abate[k, y] for k in mac_idxs[i]; init = AffExpr(0.0))
    )
    abate_total = model[abate_total_sym]

        # Equation 7 in HAIKU documentation
    model[resid_sym] = @expression(model,
        [i in 1:nregsub, y in 1:nyear],
        baseline_emis[i, y] - abate_total[i, y]
    )
    resid_emis = model[resid_sym]

        # Equation 8 in HAIKU documentation
    model[cons_sym] = @constraint(model,
        [i in 1:nregsub, y in 1:nyear],
        abate_total[i, y] <= baseline_emis[i, y]
    )

    # Feed residual sector emissions into any EmissionCap whose bus-filter
    # region contains this region-subsector's (area, subarea). Spread uniformly
    # across hours so the annual total the cap sees equals resid_emis[i, y].
    # see the function `add_resid_emis_to_caps!` for details of adding to emissions cap

    # Sectoral abatement is only meaningful when there is a price signal on
    # residual emissions -- an EmissionCap covering at least one of this
    # sector's region-subsectors, whose shadow price is the only thing that
    # makes reducing resid_emis worth paying the MAC cost for. Absent that,
    # every MAC step has strictly positive cost with zero offsetting benefit,
    # so the LP picks abate = 0 at every step and the modification is dormant.
    cap_rows_added = add_resid_emis_to_caps!(sec, config, data, model, regsub, resid_emis)
    if cap_rows_added == 0
        @warn "Sector $name: no EmissionCap covers this sector's region-subsectors. Abatement will be zero for every MAC step in every year; the modification will not affect the LP."
        return nothing
    end

     # Power-balance coupling: add ONLY the responsive electrification load
    # induced by abatement (affine in abate_total, per Haiku eq. 9/10) into
    # plserv_bus. The sector's baseline electricity (Cons0) is NOT added here --
    # E4ST already ingests total baseline electric demand as a primary input, so
    # adding it again would double-count in the power-balance constraint.
    add_sector_electrification_load!(sec, config, data, model, regsub, abate_total, lp, lp_index)
  
    model[cost_sym] = @expression(model,
        [y in 1:nyear],
        sum(abate[k, y] * mac.price[k] for k in 1:nstep)
    )

    # sector term is in $/short ton of emissions 
    add_obj_exp!(data, model, SectorTerm(), cost_sym; oper = +)
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
    add_resid_emis_to_caps!(sec::Sector, config, data, model, regsub, resid_emis)

Appends this sector's residual (non-abated) emissions into every
[`EmissionCap`](@ref) policy in `config[:mods]`. Region-subsector `i` (a row of
the `regsub` table, i.e. an `(area, subarea, subsector, emis_col)`
combination) is included in a cap for every year if:
1. `regsub.emis_col[i]` matches the cap's `emis_col` (i.e. they regulate the same
   pollutant), and
2. every bus in region-subsector `i`'s `(area, subarea)` set is inside the cap's
   `bus_filters`-defined region.
Region-subsectors that pass the pollutant check but only partially overlap a
cap's bus region are skipped with a warning. Empty `bus_filters` is treated as
grid-wide.

Residual emissions are spread uniformly across the `nhour` hours of the year
(coefficient `1/nhour` per hour), so `sum_h emis_expr[y,h]` — the quantity
the cap's `<=` constraint compares against `target[y]` — receives exactly
`resid_emis[i, y]`.

Currently runs unconditionally: any Sector modification whose residual emissions
overlap an active cap on the same pollutant contributes to that cap. There is
no config knob to opt out — remove the cap or narrow its `bus_filters` if you
don't want the sector to be captured.

### might need to add a check for the case where the sector is not in the bus filter of any emission cap / there is no emission cap
### in that case, the sector will not be abated at all, should issue warning sector isn't being captured

"""
function add_resid_emis_to_caps!(sec::Sector, config, data, model, regsub, resid_emis)
    name = sec.name
    bus = get_table(data, :bus)
    nbus = nrow(bus)
    nhr  = get_num_hours(data)
    nyear = get_num_years(data)
    nregsub = nrow(regsub)
    total_added = 0

    # Bus set per region-subsector (row of regsub): buses where bus[!, Symbol(area)] == subarea.
    regsub_bus_sets = Vector{Set{Int}}(undef, nregsub)
    for i in 1:nregsub
        col = Symbol(regsub.area[i])
        if !hasproperty(bus, col)
            regsub_bus_sets[i] = Set{Int}()
        else
            target = string(regsub.subarea[i])
            regsub_bus_sets[i] = Set(b for b in 1:nbus if string(bus[b, col]) == target)
        end
    end

    for (pname, pol) in config[:mods]
        pol isa EmissionCap || continue

        cap_bus_set = isempty(pol.bus_filters) ?
            Set(1:nbus) :
            Set(get_row_idxs(bus, parse_comparisons(pol.bus_filters)))

        emis_sym = Symbol("emis_total_$(pol.name)")
        haskey(model, emis_sym) || continue   # cap ran but produced no expression
        emis_expr = model[emis_sym]::Matrix{AffExpr}

        coef = 1.0 / nhr
        n_added = 0
        for i in 1:nregsub
            Symbol(regsub.emis_col[i]) == pol.emis_col || continue   # different pollutant, not applicable to this cap

            bs = regsub_bus_sets[i]
            isempty(bs) && continue

            if issubset(bs, cap_bus_set)
                for y in 1:nyear, h in 1:nhr
                    add_to_expression!(emis_expr[y, h], coef, resid_emis[i, y])
                end
                n_added += 1
            elseif !isdisjoint(bs, cap_bus_set)
                @warn "Sector $name: region-subsector i=$i (area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), emis_col=$(regsub.emis_col[i])) partially overlaps EmissionCap $(pol.name); not counted."
            end
        end
        @info "Sector $name: added residual emissions from $n_added region-subsectors to EmissionCap $(pol.name)"
        total_added += n_added
    end

    return total_added
end
export add_resid_emis_to_caps!


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

  If no `lp` row exists for a given region-subsector/year (or its shape sums
  to zero), that region-subsector/year's responsive load is skipped with a
  warning rather than falling back to an equal split.

Because the coefficient multiplies the JuMP expression `abate_total[i, y]`, the
LP is forced to serve more electric load whenever it chooses to abate more —
the endogenous electrification feedback.

`lp` (the `sector_<name>_load_profile` table) and `lp_index` (a
`(area, subarea, subsector, year) -> row index in lp` lookup) are built once
by the caller, `modify_model!`, and passed in here rather than being re-fetched
from `data` -- the same way `regsub`/`abate_total` already are.
"""
function add_sector_electrification_load!(sec::Sector, config, data, model, regsub, abate_total, lp, lp_index)
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
            @warn "Sector $name: no phi (eq. 10) for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i]), year=$y; responsive load skipped"
            continue
        end
        phi == 0.0 && continue   # no electrification response for this region-subsector/year

        # Look up this region-subsector/year's hourly load shape. `lp_row`'s
        # `h1..hn` values need not already be normalized (`get_sector_load_shape`
        # in `SectorLoadProfile.jl` does normalize them so that `annual_shape`
        # below comes out to ~1, but dividing through here makes this robust
        # to an unnormalized `lp` too).
        lp_key = (string(regsub.area[i]), string(regsub.subarea[i]), string(regsub.subsector[i]), string(y))
        lp_row_idx = get(lp_index, lp_key, nothing)
        if lp_row_idx === nothing
            @warn "Sector $name: no load profile found for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i]), year=$y; responsive load skipped"
            continue
        end
        lp_row = lp[lp_row_idx, :]
        annual_shape = sum(lp_row[hour_cols[h]] * hour_weights[h] for h in 1:nhr)
        if annual_shape <= 0
            @warn "Sector $name: zero annual load-profile shape for area=$(regsub.area[i]), subarea=$(regsub.subarea[i]), subsector=$(regsub.subsector[i]), year=$y; responsive load skipped"
            continue
        end

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
function modify_results!(sec::Sector, config, data)
    name = sec.name
    regsub = get_table(data, :nonelec)
    row_idxs = get_row_idxs(regsub, :mod_name => name)
    isempty(row_idxs) && return nothing

    nyear = get_num_years(data)
    hasproperty(regsub, :abate_total)        || (regsub.abate_total        = [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)])
    hasproperty(regsub, :resid_emis)         || (regsub.resid_emis         = [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)])
    hasproperty(regsub, :elec_demand_change) || (regsub.elec_demand_change = [ByYear(fill(NaN, nyear)) for _ in 1:nrow(regsub)])

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