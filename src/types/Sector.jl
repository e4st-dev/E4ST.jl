
"""
    Sector <: Modification

    sector is a supertype for the industrial, transportation, and building sectors. Non-electricity sectors are modeled through emissions and electricity demand baselines 
    whose emissions can be abated through paying a cost (as determined by MAC curves) and whose abatement impacts electricity demand. 

    'sector' subtypes (e.g. `Transportation`, `Buildings`, `Industrial`) are located in "src/types/sectors"

Abstract supertype for sectors.  Must implement the following interfaces:
* (required) [`sector!(sec::Sector)`](@ref)` 

####

## Sectors (Sector subtypes)
* [`Transportation`](@ref)
* [`Buildings`](@ref)
* [`Industrial`](@ref)


The following methods are defined for `Sector`.
* ['modify_raw_data!(sec::Sector, config, data)'](@ref)   
* [`modify_setup_data!(sec::Sector, config, data)`](@ref)
* [`modify_model!(sec::Sector, config, data, model)`](@ref)


"""


abstract type Sector <: Modification end
export Sector



# Comes after policy (needs emissions cap to work)
mod_rank(::Type{<Sector}) = 1.1

### All sector subtypes 

"""
    modify_raw_data!(mod::SectorEmissions, config, data)

Loads input files into tables:
':sector_<name>_mac_steps', ':sector_<name>_baseline_emissions', ':sector_<name>_baseline_electricity', and ':sector_<name>_baseline_load_profile'

# sector_mac_steps
# edit table to append MAC curves from the preprocessing step by subsector 
# :region - string, region name to match to bus table (state should be fine?)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
# :step_id - int, step id for MAC curve, ordered by price 
# :price_per_ton - float, MAC for given step
# :quantity_tons - float, abatement quantity for given step

# sector_emis_baseline 
# :region - string, region name to match to bus table (state)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
# :year - int, year of baseline emissions
# :emissions_tons - float, baseline emissions for given region and year

# sector_elec_baseline 
# :region - string, region name to match to bus table (state)
# :subsector - string, sub-sector id (e.g., NAICS code for industrial sector, LDV / MHDV / transit for transportation)
# :year - int, year of baseline electricity demand
# :baseline_elec_use - baseline electricity demand for given region and year

# sector_baseline_load_profile 
#

"""

"""
read in necessary data tables for the sector

"""

  function modify_raw_data!(sec::Sector, config, data)
      name = sector_name(sec)
      mac_key = Symbol("sector_$(name)_mac_steps")
      emis_key = Symbol("sector_$(name)_baseline_emissions")
      elec_key = Symbol("sector_$(name)_baseline_electricity")
      # load profile 
      lp_key = Symbol("sector_$(name)_baseline_load_profile")

      config[mac_key] = mod.mac_steps
      config[emis_key] = mod.baseline_emissions
      config[elec_key] = mod.baseline_electricity
      config[lp_key] = mod.load_profile 

        read_table!(config, data, mac_key => Symbol("sector_$(name)_mac_steps)"))
        read_table!(config, data, emis_key => Symbol("sector_$(name)_baseline_emissions"))
        read_table!(config, data, elec_key => Symbol("sector_$(name)_baseline_electricity"))
        read_table!(config, data, lp_key => Symbol("sector_$(name)_baseline_load_profile"))
        return nothing
  end

"""
    modify_setup_data!(s::Sector, config, data)

Attaches `year_idx` to the emissions baseline, validates regions against the
bus table, sorts MAC steps ascending in price, and builds a lookup from each
baseline row to its MAC step indices.
"""
"""
  creates and attaches year-index mapping for MAC steps to the bus table
"""

function modify_setup_data!(s::Sector, config, data)
    name = sector_name(sec)
    @info "Setting up Sector: $name"

    mac  = get_table(data, Symbol("sector_$(name)_mac_steps"))
    base = get_table(data, Symbol("sector_$(name)_emis_baseline"))
    elec = get_table(data, Symbol("sector_$(name)_elec_baseline"))

    # Default subsector to "all" when the column is omitted, so single-subsector
    # sectors and disaggregated sectors share the same grouping logic below.
    for tbl in (mac, base, elec)
        hasproperty(tbl, :subsector) || (tbl.subsector = fill("all", nrow(tbl)))
    end

    years = get_years(data)
    year_to_idx = Dict(y => i for (i, y) in enumerate(years))
    filter!(:year => in(keys(year_to_idx)), base)

    # Validate per-row (area, subarea) against the bus table. `area` names a bus
    # column ("state", "bus_idx", ...); `subarea` is one of that column's
    # values. This mirrors the load_shape/load_match pattern in `load.jl` and
    # lets a single file mix nodal rows with state-aggregated rows.
    bus = get_table(data, :bus)
    for tbl_name in (:mac, :base, :elec)
        tbl = tbl_name === :mac ? mac : tbl_name === :base ? base : elec
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
    return nothing
end


"""
modify_model!(sec::Sector, config, data, model)

Implements the sector's abatement and residual emissions variables, 
constraints (non-negativity), objective function contributio, and emissions cap contribution.  
Stub for adding electrification loads to the power balancing equation. 

"""

function modify_model!(s::Sector, config, data, model)
    name = sector_name(s)
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

        # like equation 7 in Nick's HAIKU documentation
    model[resid_sym] = @expression(model,
        [g in 1:nbase],
        base.baseline_emis[g] - abate_total[g]
    )
    resid_emis = model[resid_sym]

        # like equation 8 in Nick's HAIKU documentation
    model[cons_sym] = @constraint(model,
        [g in 1:nbase],
        abate_total[g] <= base.baseline_emis[g]
    )

    # Feed residual sector emissions into any EmissionCap whose bus-filter
    # region contains this baseline row's (area, subarea). Spread uniformly
    # across hours so the annual total the cap sees equals resid_emis[g].
    # see the function `add_resid_emis_to_caps!` for adding to emissions cap 
    add_resid_emis_to_caps!(s, config, data, model, base, base_year_idx, resid_emis)

    # see the function `add_sector_electrification_load!` for adding to the power balancing equation
    if s.add_to_pbal
        add_sector_electrification_load!(s, config, data, model, abate_total)
    end

    model[cost_sym] = @expression(model,
        [y in 1:nyear],
        sum(abate[k, y] * mac.price_per_ton[k] for k in 1:nstep) +
        sum(resid_emis[g] * s.emis_price
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
    add_resid_emis_to_caps!(s::Sector, config, data, model, base, base_year_idx, resid_emis)

Appends this sector's residual (non-abated) emissions into every
[`EmissionCap`](@ref) policy in `config[:mods]`. Each baseline row `g` is
included in a cap iff every bus in row `g`'s `(area, subarea)` set is inside
the cap's `bus_filters`-defined region. Partially overlapping rows are
skipped with a warning. Empty `bus_filters` is treated as grid-wide.

Residual emissions are spread uniformly across the `nhour` hours of the year
(coefficient `1/nhour` per hour), so `sum_h emis_expr[y,h]` — the quantity
the cap's `<=` constraint compares against `target[y]` — receives exactly
`resid_emis[g]` per year.

Runs unconditionally: any Sector modification whose residual emissions
overlap an active cap contributes to that cap. There is no config knob to
opt out — remove the cap or narrow its `bus_filters` if you don't want the
sector to be captured.
"""
function add_resid_emis_to_caps!(s::Sector, config, data, model,
                                  base, base_year_idx, resid_emis)
    name = sector_name(s)
    bus = get_table(data, :bus)
    nbus = nrow(bus)
    nhr  = get_num_hours(data)
    nbase = nrow(base)

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
    end
    return nothing
end
export add_resid_emis_to_caps!



"""
    add_sector_electrification_load!(s::Sector, config, data, model, abate_total)

Stub for distributing abatement-induced electric load into `plserv_bus`
(driving `cons_pbal_geq/leq` in `setup.jl`).

Implementation outline once disaggregation is decided:
  for each baseline row g = (region, year):
      for each bus b in region, hour h:
          add_to_expression!(plserv_bus[b, year_idx, h],
                             abate_total[g] * load_per_ton_profile[b, year_idx, h])
"""
function add_sector_electrification_load!(s::Sector, config, data, model, abate_total)
    @info "Sector $(sector_name(s)): pbal coupling stub — load mapping not yet implemented"
    return nothing
end
export add_sector_electrification_load!



""" 
modify_results!(sec::Sector, config, data)

Writes per-`(region, year)` abatement and residual-emissions totals onto the
sector's emissions baseline table.
"""
function modify_results!(sec::Sector, config, data)
    return nothing
  end