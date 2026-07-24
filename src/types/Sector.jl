
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
    - `emis_price::Float64`
    - `add_to_pbal::Bool`

The following methods are defined for `Sector`.
* ['modify_raw_data!(sec::Sector, config, data)'](@ref)   
* [`modify_setup_data!(sec::Sector, config, data)`](@ref)
* [`modify_model!(sec::Sector, config, data, model)`](@ref)

## Model contribution per sector `sec`
* Variables: `abate_<name>[k, y]` — tons abated at MAC step `k`, year `y`.
* Expressions:
    - `abate_total_<name>[g]` — total tons for baseline row `g`
      `(region, year)`.
    - `resid_emis_<name>[g]` — `baseline_emis - abate_total`.
    - `cost_sector_<name>_obj[y]` — MAC area + residual emissions cost, added
      to the model objective via [`add_obj_exp!`](@ref).
* Constraints: `cons_abate_cap_<name>[g]` — `abate_total <= baseline_emis`.


## Pbal coupling

## Pbal coupling
When `mod.add_to_pbal` is true, `modify_model!` calls
[`add_sector_electrification_load!`](@ref), which adds only the responsive
electrification load (`abate_total · phi`) into `plserv_bus`. It uses the
sector's load profile for the hourly shape and distributes load equally across
the buses matching each row's `(area, subarea)`. Equal-split disaggregation is
a placeholder pending a weighted rule (population, existing load share, etc.).
Baseline electricity (`Cons0`) is not added — E4ST already carries it as a
primary input.


"""


abstract type Sector <: Modification end
export Sector



# Comes after policy (needs emissions cap to work, appends emissions to cap's emis_total expression)
mod_rank(::Type{<Sector}) = 1.1

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
# :price_per_ton - float, MAC for given step
# :quantity_tons - float, abatement quantity for given step

# sector_emis_baseline 
# :src_file - string, description of source data file for baseline emissions
# :description - string, description of the baseline emissions row
# :set 
# :area - string, geographic area of aggregation (state)
# :subarea - string, state name or other subregion name to match to bus table
# :sector - string, sector name (Transportation, Industry, Buildings)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
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
    name = sector_name(sec)
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

    read_table!(config, data, mac_key  => Symbol("sector_$(name)_mac_steps"))
    read_table!(config, data, emis_key => Symbol("sector_$(name)_emis_baseline"))
    read_table!(config, data, elec_key => Symbol("sector_$(name)_elec_baseline"))
    read_table!(config, data, lp_key   => Symbol("sector_$(name)_load_profile"))
    read_table!(config, data, elast_key => Symbol("sector_$(name)_elasticity"))
    return nothing
end


"""
    modify_setup_data!(sec::Sector, config, data)

Attaches `year_idx` to the emissions baseline, creating a map, then validates regions against the
bus table. It sorts MAC steps ascending in price, and builds a lookup from each
baseline emissions row to its MAC step indices.
"""
"""

"""

function modify_setup_data!(sec::Sector, config, data)
    name = sector_name(sec)
    @info "Setting up Sector: $name"

    mac  = get_table(data, Symbol("sector_$(name)_mac_steps"))
    base_wide = get_table(data, Symbol("sector_$(name)_emis_baseline"))
    elec_wide = get_table(data, Symbol("sector_$(name)_elec_baseline"))
    lp   = get_table(data, Symbol("sector_$(name)_load_profile"))
    elast_wide = get_table(data, Symbol("sector_$(name)_elasticity"))

    years = get_years(data)
    year_to_idx = Dict(y => i for (i, y) in enumerate(years))

    # Transpose wide-year emissions and electricity baselines (one row per
    # (area, subarea, subsector) with yearly value columns y2016..y2050)
    # into long form so downstream indexing stays keyed by year.
    base = DataFrame(area=String[], subarea=String[], subsector=String[],
                    year=String[], baseline_emis=Float64[])
    for row in eachrow(base_wide), y in years
        col = Symbol(y)
        hasproperty(base_wide, col) || continue
        push!(base, (string(row.area), string(row.subarea),
                     string(row.subsector), string(y), Float64(row[col])))
    end
    data[Symbol("sector_$(name)_emis_baseline")] = base


    elec = DataFrame(area=String[], subarea=String[], subsector=String[],
                    year=String[], baseline_elec_use=Float64[])
    for row in eachrow(elec_wide), y in years
        col = Symbol(y)
        hasproperty(elec_wide, col) || continue
        push!(elec, (string(row.area), string(row.subarea),
                     string(row.subsector), string(y), Float64(row[col])))
    end
    data[Symbol("sector_$(name)_elec_baseline")] = elec

   
    # Build the year-invariant elasticity lookup: (area, subarea, subsector) ->
    # (own, cross). These are the CGE-derived elasticities of Haiku eq. 10.
    elast_lookup = Dict{NTuple{3, String}, Tuple{Float64, Float64}}()
    for row in eachrow(elast)
        elast_lookup[(string(row.area), string(row.subarea), string(row.subsector))] =
            (Float64(row.own), Float64(row.cross))
    end

    # Build the Cons0 lookup (annual baseline electricity) keyed by
    # (area, subarea, subsector, year) from the melted elec baseline.
    cons0_lookup = Dict{NTuple{4, String}, Float64}()
    for row in eachrow(elec)
        cons0_lookup[(row.area, row.subarea, row.subsector, row.year)] = row.baseline_elec_use
    end

    # Compute phi per (area, subarea, subsector, year) via Haiku eq. 10:
    #   phi = (cross · Cons0) / (own · EmisSector0)
    # EmisSector0 is the baseline emissions for the row (base.baseline_emis);
    # Cons0 is the baseline electricity for the same key. phi varies by year even
    # though the elasticities do not, because Cons0 and EmisSector0 do.
    phi = Dict{NTuple{4, String}, Float64}()
    for row in eachrow(base)
        key4 = (row.area, row.subarea, row.subsector, row.year)
        key3 = (row.area, row.subarea, row.subsector)

        oc = get(elast_lookup, key3, nothing)
        if oc === nothing
            @warn "Sector $name: no elasticities for $key3; phi=0 (no electrification response) for its rows"
            continue
        end
        own, cross = oc

        emis0 = row.baseline_emis
        cons0 = get(cons0_lookup, key4, nothing)
        if cons0 === nothing
            @warn "Sector $name: no baseline electricity (Cons0) for $key4; phi=0 for this row"
            continue
        end
        if own == 0.0 || emis0 == 0.0
            @warn "Sector $name: own elasticity or baseline emissions is zero for $key4; phi=0 for this row"
            continue
        end

        phi[key4] = (cross * cons0) / (own * emis0)
    end
    data[Symbol("sector_$(name)_phi")] = phi

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


    sort!(mac, [:area, :subarea, :subsector, :price_per_ton])
    mac.step_idx = 1:nrow(mac)

    # Lookup MAC steps per baseline row. The key is (area, subarea, subsector);
    # year is handled separately via the variable's year index.
    gdf_mac = groupby(mac, [:area, :subarea, :subsector])
    mac_index = Vector{Vector{Int}}(undef, nrow(base))
    for (i, row) in enumerate(eachrow(base))
        key = (area = row.area, subarea = row.subarea, subsector = row.subsector)
        if haskey(gdf_mac, key)
            mac_index[i] = collect(gdf_mac[key].step_idx)
        else
            mac_index[i] = Int[]
            @warn "Sector $name: no MAC steps found for area=$(row.area), subarea=$(row.subarea), subsector=$(row.subsector)"
        end
    end
    data[Symbol("sector_$(name)_mac_index")] = mac_index

    # Load-profile lookup by (area, subarea, subsector, year) -> row index in lp.
    lp_index = Dict{NTuple{4, String}, Int}()
    for (i, row) in enumerate(eachrow(lp))
        lp_index[(string(row.area), string(row.subarea), string(row.subsector), string(row.year))] = i
    end
    data[Symbol("sector_$(name)_lp_index")] = lp_index

    return nothing
end


"""
    modify_model!(sec::Sector, config, data, model)

Implements the sector's abatement and residual emissions variables, 
constraints (non-negativity), objective function contribution, and emissions cap contribution via [`add_resid_emis_to_caps!`](@ref).  
If `sec.add_to_pbal` is true, Feeds residual
emissions into any covering `EmissionCap`, and adds the
sector's baseline and responsive electric load to `plserv_bus` via
[`add_sector_baseline_load!`](@ref) and
[`add_sector_electrification_load!`](@ref).

"""

function modify_model!(sec::Sector, config, data, model)
    name = sector_name(sec)
    @info "Adding Sector $name to the model"

    mac       = get_table(data, Symbol("sector_$(name)_mac_steps"))
    base      = get_table(data, Symbol("sector_$(name)_emis_baseline"))
    mac_index = data[Symbol("sector_$(name)_mac_index")]::Vector{Vector{Int}}
    years = get_years(data)
    year_to_idx = Dict(y => i for (i, y) in enumerate(years))
    base_year_idx = [year_to_idx[y] for y in base.year]
    nyear = length(years)
    nstep = nrow(mac)
    nbase = nrow(base)

    if nstep == 0 || nbase == 0
        @warn "Sector $name: empty MAC or baseline table, skipping model modification"
        return nothing
    end

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
        upper_bound = isfinite(mac.quantity_tons[k]) ? mac.quantity_tons[k] : 1e12,
        base_name = String(abate_sym)
    )
    abate = model[abate_sym]

    # Each baseline row g = (area, subarea, subsector, year). The subsector
    # dimension is carried implicitly: mac_index[g] (built in modify_setup_data!
    # by grouping mac on [:area, :subarea, :subsector]) returns exactly the MAC
    # step indices belonging to row g's (area, subarea, subsector), and
    # base_year_idx[g] picks the column of the abate variable for row g's year.
    # So abate_total[g] sums only the abatement that "belongs" to row g.
    # The same indirection makes emissions and induced electricity outputs
    # subsector-resolved automatically — see modify_results!.

    model[abate_total_sym] = @expression(model,
        [g in 1:nbase],
        sum(abate[k, base_year_idx[g]] for k in mac_index[g]; init = AffExpr(0.0))
    )
    abate_total = model[abate_total_sym]

        # Equation 7 in HAIKU documentation
    model[resid_sym] = @expression(model,
        [g in 1:nbase],
        base.baseline_emis[g] - abate_total[g]
    )
    resid_emis = model[resid_sym]

        # Equation 8 in HAIKU documentation
    model[cons_sym] = @constraint(model,
        [g in 1:nbase],
        abate_total[g] <= base.baseline_emis[g]
    )

    # Feed residual sector emissions into any EmissionCap whose bus-filter
    # region contains this baseline row's (area, subarea). Spread uniformly
    # across hours so the annual total the cap sees equals resid_emis[g].
    # see the function `add_resid_emis_to_caps!` for details of adding to emissions cap 

    # Sectoral abatement is only meaningful when there is a price signal on
    # residual emissions -- either from an EmissionCap that covers at least
    # one of this sector's baseline rows, or from a positive `emis_price`.
    # Absent both, every MAC step has strictly positive cost with zero
    # offsetting benefit, so the LP picks abate = 0 at every step and the
    # modification is dormant, issues a warning when true. 
    cap_rows_added = add_resid_emis_to_caps!(sec, config, data, model, base, base_year_idx, resid_emis)
    if cap_rows_added == 0 && sec.emis_price == 0.0
        @warn "Sector $name: no EmissionCap covers this sector's region and emis_price=0. Abatement will be zero for every MAC step in every year; the modification will not affect the LP."
    end

     # Power-balance coupling: add ONLY the responsive electrification load
    # induced by abatement (affine in abate_total, per Haiku eq. 9/10) into
    # plserv_bus. The sector's baseline electricity (Cons0) is NOT added here --
    # E4ST already ingests total baseline electric demand as a primary input, so
    # adding it again would double-count in the power-balance constraint.
    if sec.add_to_pbal
        add_sector_electrification_load!(sec, config, data, model, base, base_year_idx, abate_total)
    end

    model[cost_sym] = @expression(model,
        [y in 1:nyear],
        sum(abate[k, y] * mac.price_per_ton[k] for k in 1:nstep) +
        sum(resid_emis[g] * sec.emis_price
            for g in 1:nbase if base_year_idx[g] == y;
            init = AffExpr(0.0))
    )

    # sector term is in $/short ton of emissions 
    add_obj_exp!(data, model, SectorTerm(), cost_sym; oper = +)
    return nothing
end

"""
    named `SectorTerm` for the sector's contribution to the objective function. 
Used in `add_obj_term!` to add the sector's abatement and residual emissions costs to the objective function.

    look at emissions price modification -- might use per MWh term, might be reusable if it's just per unit of emissions
"""

  struct SectorTerm <: Term end

"""
    add_resid_emis_to_caps!(sec::Sector, config, data, model, base, base_year_idx, resid_emis)

Appends this sector's residual (non-abated) emissions into every
[`EmissionCap`](@ref) policy in `config[:mods]`. Each baseline row `g` is
included in a cap if every bus in row `g`'s `(area, subarea)` set is inside
the cap's `bus_filters`-defined region. Partially overlapping rows are
skipped with a warning. Empty `bus_filters` is treated as grid-wide.

Residual emissions are spread uniformly across the `nhour` hours of the year
(coefficient `1/nhour` per hour), so `sum_h emis_expr[y,h]` — the quantity
the cap's `<=` constraint compares against `target[y]` — receives exactly
`resid_emis[g]` per year.

Currently runs unconditionally: any Sector modification whose residual emissions
overlap an active cap contributes to that cap. There is no config knob to
opt out — remove the cap or narrow its `bus_filters` if you don't want the
sector to be captured.

### might need to add a check for the case where the sector is not in the bus filter of any emission cap / there is no emission cap
### in that case, the sector will not be abated at all, should issue warning sector isn't being captured

"""
function add_resid_emis_to_caps!(sec::Sector, config, data, model,
                                  base, base_year_idx, resid_emis)
    name = sector_name(sec)
    bus = get_table(data, :bus)
    nbus = nrow(bus)
    nhr  = get_num_hours(data)
    nbase = nrow(base)
    total_added =0

    # Bus set per baseline row: buses where bus[!, Symbol(area)] == subarea.
    base_bus_sets = Vector{Set{Int}}(undef, nbase)
    for g in 1:nbase
        col = Symbol(base.area[g])
        if !hasproperty(bus, col)
            base_bus_sets[g] = Set{Int}()
        else
            target = string(base.subarea[g])
            base_bus_sets[g] = Set(b for b in 1:nbus if string(bus[b, col]) == target)
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
        for g in 1:nbase
            bs = base_bus_sets[g]
            isempty(bs) && continue

            if issubset(bs, cap_bus_set)
                y = base_year_idx[g]
                for h in 1:nhr
                    add_to_expression!(emis_expr[y, h], coef, resid_emis[g])
                end
                n_added += 1
            elseif !isdisjoint(bs, cap_bus_set)
                @warn "Sector $name: baseline row g=$g (area=$(base.area[g]), subarea=$(base.subarea[g])) partially overlaps EmissionCap $(pol.name); not counted."
            end
        end
        @info "Sector $name: added residual emissions from $n_added baseline rows to EmissionCap $(pol.name)"
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
                                     base, base_year_idx, abate_total)

Adds the *responsive* electrification load induced by abatement into
`plserv_bus`, implementing the consumption/abatement linkage of Haiku eq. 9:

    Cons_{y,r,sec} = Cons0_{y,r,sec} + Σ_k EmisAbatement_{y,r,sec,k} · phi_{y,r,sec}

where `phi` (short tons -> MWh) is computed in `modify_setup_data!` per Haiku
eq. 10, `phi = (cross · Cons0) / (own · EmisSector0)`, and looked up here.
`Cons0` (baseline electricity) is NOT added by the Sector modification — E4ST
already carries total baseline electric demand as a primary input, so this
function adds only the second (responsive) term to avoid double-counting.

For each baseline row `g = (area, subarea, subsector, year)`:
* `annual_responsive_MWh = abate_total[g] · phi[g]` (an affine expression in the
  `abate` variables).
* This annual energy is distributed over hours following the *shape* of the
  sector's load profile (so the responsive load has the same hourly pattern as
  baseline demand), and equally across the buses in `(area, subarea)`:

      plserv_bus[b, y, h] += (1/n_buses) · phi[g] · profile[h] / Σ_h' profile[h']·w_h' · abate_total[g]

Because the coefficient multiplies the JuMP expression `abate_total[g]`, the
LP is forced to serve more electric load whenever it chooses to abate more —
the endogenous electrification feedback.
"""
function add_sector_electrification_load!(sec::Sector, config, data, model,
                                          base, base_year_idx, abate_total)
    name = sector_name(sec)
    plserv_bus = model[:plserv_bus]::Array{AffExpr,3}
    lp = get_table(data, Symbol("sector_$(name)_load_profile"))
    lp_index = data[Symbol("sector_$(name)_lp_index")]::Dict{NTuple{4,String},Int}
    phi = data[Symbol("sector_$(name)_phi")]::Dict{NTuple{4,String},Float64}
    bus = get_table(data, :bus)
    nbus = nrow(bus)
    nhr = get_num_hours(data)
    hour_cols = [Symbol("hour$h") for h in 1:nhr]
    hour_weights = get_hour_weights(data)
    buses_for = _sector_region_buses(bus, nbus)

    n_rows_applied = 0
    for g in 1:nrow(base)
        key = (string(base.area[g]), string(base.subarea[g]),
               string(base.subsector[g]), string(base.year[g]))

        phi = get(phi, key, NaN)
        if isnan(phi)
            @warn "Sector $name: no phi (eq. 10) for $key; responsive load skipped"
            continue
        end
        phi == 0.0 && continue   # no electrification response for this row

        lp_row_idx = get(lp_index, key, nothing)
        if lp_row_idx === nothing
            @warn "Sector $name: no load profile for $key; responsive load skipped"
            continue
        end
        lp_row = lp[lp_row_idx, :]

        # Normalize the profile to a distribution over the year (energy basis)
        # so the responsive MW at each hour integrates to abate_total·phi MWh.
        annual_shape = sum(lp_row[hour_cols[h]] * hour_weights[h] for h in 1:nhr)
        annual_shape > 0 || continue

        buses = buses_for(base.area[g], base.subarea[g])
        isempty(buses) && continue
        share = 1.0 / length(buses)
        y = base_year_idx[g]

        for h in 1:nhr
            # MW added per unit abate_total at (bus, hour):
            coef = share * phi * lp_row[hour_cols[h]] / annual_shape
            coef == 0.0 && continue
            for b in buses
                add_to_expression!(plserv_bus[b, y, h], coef, abate_total[g])
            end
        end
        n_rows_applied += 1
    end
    @info "Sector $name: added responsive electrification load from $n_rows_applied baseline rows to plserv_bus"
    return nothing
end
export add_sector_electrification_load!

"""
modify_results!(sec::Sector, config, data)

modifies results for the sector.  Currently does nothing, placeholder. 

"""
function modify_results!(sec::Sector, config, data)
    return nothing
  end