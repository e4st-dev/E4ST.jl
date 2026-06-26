
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



# Less than 1 so that it comes before policy? 
mod_rank(::Type{<Sector}) = 0.9

### All sector subtypes 

"""
    modify_raw_data!(mod::SectorEmissions, config, data)

Loads input files into tables:
':sector_<name>_mac_steps', ':sector_<name>_baseline_emissions', ':sector_<name>_baseline_electricity', and ':sector_<name>_baseline_load_profile'

# sector_mac_steps
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

  function modify_raw_data!(sec::Sector, config, data)
      data[mod.name] = read_table(data, mod.file, mod.name)
      mac_key = Symbol("sector_$(name)_mac_steps")
      emis_key = Symbol("sector_$(name)_baseline_emissions")
      elec_key = Symbol("sector_$(name)_baseline_electricity")
      # load profile 
      lp_key = Symbol("sector_$(name)_baseline_load_profile")

      config[mac_key] = mod.mac_steps
      config[emis_key] = mod.baseline_emissions
      config[elec_key] = mod.baseline_electricity
      config[lp_key] = mod.load_profile 

        read_table!(config, data, mac_key => Symbol("sector_$(name)_mac_steps)")
        read_table!(config, data, emis_key => Symbol("sector_$(name)_baseline_emissions"))
        read_table!(config, data, elec_key => Symbol("sector_$(name)_baseline_electricity"))
        read_table!(config, data, lp_key => Symbol("sector_$(name)_baseline_load_profile"))
        return nothing
  end

  function modify_setup_data!(sec::Sector, config, data)
      # Attach industrial loads to bus / nominal_load tables here, OR
      # tag relevant gens, depending on your formulation.
      # MAC steps as vector 
      # build region into bus_idx mapping for pbal 

      #
      # 
      #

      name = sector_name(sec)
      # get Transport, Industrial, Residential
      mac = get_table(data, Symbol("sector_$(name)_mac_steps"))
      base = get_table(data, Symbol("sector_$(name)_baseline_emissions"))
      elec = get_table(data, Symbol("sector_$(name)_baseline_electricity"))
     # Year ears into year index

        # Default subsector to "all" when the column is omitted. For example, with buildings. 
    for tbl in (mac, base, elec)
        hasproperty(tbl, :subsector) || (tbl.subsector = fill("all", nrow(tbl)))
    end

    years = get_years(data)
    year_to_idx = Dict(years[i] => i for i in 1:length(years))

    filter!(:year => in(keys(year_to_idx)), base)
    base.year_idx = [year_to_idx[y] for y in base.year]

    # bus needs a region column for sector compatibility
    bus = get_table(data, :bus)
    @assert hasproperty(bus, :region) "bus table must have a region column for sector compatibility"

    bus_regions = Set(string.(bus[!, Symbol(s.groupby)]))
    #
    # 
    #
    sort!(mac, [:region, :price_per_ton])
    mac.step_idx = 1:nrow(mac)
    
    gdf_mac = groupby(mac, :region)
    mac_index = Vector{Vector{Int}}(undef, nrow(bus))
    for (i, row) in enumerate(eachrow(bus))
        key =(region = row.region, )
        if haskey(gdf_mac, key)
            mac_index[i] = collect(gdf_mac[key].step_idx)
        else
            mac_index[i] = Int[]
        end
    end
    data[Symbol("sector_$(name)_mac_index")] = mac_index
    return nothing

  end

"""
modify_model!(sec::Sector, config, data, model)

Implements the sector's abatement and residual emissions variables, constraints (non-negativity), and objective function contribution.  
Stub for adding electrification loads to the power balancing equation. 

"""

  function modify_model!(sec::Sector, config, data, model)
      # Add industrial demand to pflow_bus (or constrain electrified
      # industrial process variables) and add operating costs via
      # add_obj_term!(data, model, PerMWhGen(), some_col, oper = +).
      name = sector_name(sec)
      mac  = get_table(data, Symbol("sector_$(name)_mac_steps"))
      base_emissions = get_table(data, Symbol("sector_$(name)_baseline_emissions"))
      # base_electricity = get_table(data, Symbol("sector_$(name)_baseline_electricity"))
      mac_index = data[Symbol("sector_$(name)_mac_index")]::Vector{Vector{Int}}
      nyear = get_num_years(data)
      nstep = nrow(mac)
      nbaseline = nrow(base_emissions)

      abate_sym = Symbol("sector_$(name)_abate")
      abate_total_sym = Symbol("sector_$(name)_abate_total")
      resid_sym = Symbol("sector_$(name)_residual")
      cons_sym = Symbol("sector_$(name)_cons")
      cost_sym = Symbol("sector_$(name)_cost")

      model[abate_sym] = @varaiable(model, [k in 1:nstep, y in 1:nyear], 
                 lower_bound = 0.0, 
                 upper_bound = isfinite(mac.quantity_tons[k]) ? mac.quantity_tons[k] : 1e12,
                 base_name = String(abate_sym)
                 )
            
        abate = model[abate_sym]

      model[abate_total_sym] = @expression(model, [g in 1:nbase],
                                sum(abate[k, base.year_dx[g]] for k in mac_index[g]; init = AffExpr(0.0))
                                )
      abate_total = model[abate_total_sym]

      model[resid_sym] = @expression(model, 
                                [g in 1:nbase],
                                base_emissions[g].emissions_tons - abate_total[g]
                                )
      resid_emis = model[resid_sym]
      
      model[cons_sym] = @expression(model, 
                                [g in 1:nbase],
                                abate_total[g] <= base_emissions[g].emissions_tons
                                )

       # placeholder for addition to power balancing equation                              
       #if sec.add_to_pbal
       # add_sector_electricfication_loads!(sec, data, abate_total)
       # end 

       model[cost_sym] = @expression(model, 
                                [y in 1:nyear],
                                sum(abate[k, y] * mac.price_per_ton[k] for k in 1:nstep) +
                                sum(resid_emis[g] * sec.emis_price
                                    for g in 1:nbaseline if base_emissions[g].year_idx == y;
                                    init = AffExpr())
                                )

        add_obj_term!(data, model, SectorTerm(), cost_sym, oper = +)
        return nothing

  end


""" 
modify_results!(sec::Sector, config, data)

Writes per-`(region, year)` abatement and residual-emissions totals onto the
sector's emissions baseline table.
"""
function modify_results!(sec::Sector, config, data)
    name = sector_name(sec)
    base_sym = Symbol("sector_$(name)_emis_baseline")
    abate_sym = Symbol("abate_$(name)")

    base  = get_table(data, base_sym)
    nbase = nrow(base)
    raw   = get_raw_results(data)

    if !haskey(raw, abate_sym) || nbase == 0
        return nothing
    end

    abate = raw[abate_sym]::Matrix{Float64}
    mac_index = data[Symbol("sector_$(name)_mac_index")]::Vector{Vector{Int}}
    year_to_idx = Dict(y => i for (i, y) in enumerate(get_years(data)))
    base_year_idx = [year_to_idx[y] for y in base.year]

    abate_totals = [sum(abate[k, base_year_idx[g]] for k in mac_index[g]; init = 0.0) for g in 1:nbase]
    resid_totals = base.baseline_emis .- abate_totals

    add_table_col!(data, base_sym, :abate_total,
        abate_totals, ShortTons,
        "Total non-electric sector emissions abated in this (region, year)")
    add_table_col!(data, base_sym, :resid_emis_total,
        resid_totals, ShortTons,
        "Residual (non-abated) non-electric sector emissions in this (region, year)")
    add_table_col!(data, base_sym, :induced_elec_load,
        zeros(nbase), MWhGenerated,
        "Electric load (MWh) added by sector electrification implied by abatement; zero until load mapping is implemented")
    return nothing
  end