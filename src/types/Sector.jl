
"""
    Sector <: Modification

    sector is a supertype for the industrial, transportation, and building sectors. 

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

Loads `mod.mac_file` into `data[:sector_mac_steps]` and `mod.baseline_file`
into `data[:sector_baseline]`. The load profile file is registered on the
config but read lazily by the load-coupling step.
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
     # Year ears into year index
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
        data[Symbol("sector_$(name)_mac_index")] = mac_index
        return nothing

  end

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
       # add_sector_electricfication_loads!(sec, config, data, model, abate_total)
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

  function modify_results!(sec::Sector, config, data)
      # add_results_formula!(data, :gen, :industrial_load_cost, ...)
  end