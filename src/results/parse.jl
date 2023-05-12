"""
    parse_results!(config, data, model) -> nothing
    
* Gathers the values and shadow prices of each variable, expression, and constraint stored in the model and dumps them into `data[:results][:raw]` (see [`get_raw_results`](@ref) and [`get_results`](@ref)).  
* Adds relevant info to `gen`, `bus`, and `branch` tables.  See [`parse_lmp_results!`](@ref) and [`parse_power_results!`](@ref) for more information.
* Saves updated `gen` table via [`save_updated_gen_table`](@ref)
* Saves `data` to `get_out_path(config,"data_parsed.jls")` unless `config[:save_data_parsed]` is `false` (true by default).
"""
function parse_results!(config, data, model)
    log_header("PARSING RESULTS")

    obj_scalar = config[:objective_scalar]

    results_raw = Dict(k => (@info "Parsing Result $k"; value_or_shadow_price(v, obj_scalar)) for (k,v) in object_dictionary(model))
    
    # Empty the model now that we have retrieved all info, to save RAM and prevent the user from accidentally accessing un-scaled data.
    empty!(model)
    
    results = OrderedDict{Symbol, Any}()
    data[:results] = results
    results[:raw] = results_raw

    parse_lmp_results!(config, data)
    parse_power_results!(config, data)

    #change build_status to 'new' for generators built in the sim
    update_build_status!(config, data, :gen)

    save_updated_gen_table(config, data)

    # Save the parsed data
    if config[:save_data_parsed] === true
        serialize(get_out_path(config, "data_parsed.jls"), data)
    end

    return nothing
end

"""
    value_or_shadow_price(constraints, obj_scalar) -> shadow_prices*obj_scalar

    value_or_shadow_price(variables, obj_scalar) -> values

    value_or_shadow_price(expressions, obj_scalar) -> values

Returns a value or shadow price depending on what is passed in.  Used in [`results_raw!`](@ref).  Scales shadow prices by `obj_scalar` to restore to units of dollars (per applicable unit).
"""
function value_or_shadow_price(ar::AbstractArray{<:ConstraintRef}, obj_scalar)
    value_or_shadow_price.(ar, obj_scalar)
end
function value_or_shadow_price(ar::AbstractArray{<:AbstractJuMPScalar}, obj_scalar)
    value.(ar)
end
function value_or_shadow_price(cons::ConstraintRef, obj_scalar)
    shadow_price(cons) * obj_scalar
end
function value_or_shadow_price(x::AbstractJuMPScalar, obj_scalar)
    value(x)
end
function value_or_shadow_price(x::Float64, obj_scalar)
    return x
end
function value_or_shadow_price(ar::AbstractArray, obj_scalar)
    value_or_shadow_price.(ar, obj_scalar)
end
function value_or_shadow_price(v::Number, obj_scalar)
    return v
end
export value_or_shadow_price


@doc raw"""
    parse_power_results!(config, data, res_raw)

Adds power-based results.  See also [`get_table_summary`](@ref) for the below summaries.

| table_name | col_name | unit | description |
| :-- | :-- | :-- | :-- |
| :bus | :pgen | MWGenerated | Average Power Generated at this bus |
| :bus | :egen | MWhGenerated | Electricity Generated at this bus for the weighted representative hour |
| :bus | :pflow | MWFlow | Average power flowing out of this bus |
| :bus | :eflow | MWhFlow | Electricity flowing out of this bus |
| :bus | :pflow_in | MWFlow | Average power flowing into this bus |
| :bus | :eflowin | MWhFlow | Electricity flowing out of this bus |
| :bus | :pflow_out | MWFlow | Average power flowing into this bus |
| :bus | :eflow_out | MWhFlow | Electricity flowing out of this bus |
| :bus | :plserv | MWServed | Average power served at this bus |
| :bus | :elserv | MWhServed | Electricity served at this bus for the weighted representative hour |
| :bus | :plcurt | MWCurtailed | Average power curtailed at this bus |
| :bus | :elcurt | MWhCurtailed | Electricity curtailed at this bus for the weighted representative hour |
| :bus | :elnom  | MWhLoad | Electricity load at this bus for the weighted representative hour |
| :gen | :pgen | MWGenerated | Average power generated at this generator |
| :gen | :egen | MWhGenerated | Electricity generated at this generator for the weighted representative hour |
| :gen | :pcap | MWCapacity | Power capacity of this generator generated at this generator for the weighted representative hour |
| :gen | :cf | MWhGeneratedPerMWhCapacity | Capacity Factor, or average power generation/power generation capacity, 0 when no generation |
| :branch | :pflow | MWFlow | Average Power flowing through branch |
| :branch | :eflow | MWFlow | Total energy flowing through branch for the representative hour |
"""
function parse_power_results!(config, data)
    res_raw = get_raw_results(data)

    pgen_gen = res_raw[:pgen_gen]::Array{Float64, 3}
    egen_gen = res_raw[:egen_gen]::Array{Float64, 3}
    pcap_gen = res_raw[:pcap_gen]::Array{Float64, 2}

    pflow_branch = res_raw[:pflow_branch]::Array{Float64, 3}
    
    plserv_bus = res_raw[:plserv_bus]::Array{Float64, 3}
    plcurt_bus = res_raw[:plcurt_bus]::Array{Float64, 3}
    pgen_bus = res_raw[:pgen_bus]::Array{Float64, 3}
    pflow_bus = res_raw[:pflow_bus]::Array{Float64, 3}

    # Weight things by hour as needed
    egen_bus = weight_hourly(data, pgen_bus)
    elserv_bus = weight_hourly(data, plserv_bus)
    elcurt_bus = weight_hourly(data, plcurt_bus)
    elnom_bus = weight_hourly(data, get_table_col(data, :bus, :plnom))
    eflow_bus = weight_hourly(data, pflow_bus)
    eflow_branch = weight_hourly(data, pflow_branch)

    pflow_out_bus = map(x-> max(x,0), pflow_bus)
    pflow_in_bus = map(x-> max(-x,0), pflow_bus)
    eflow_out_bus = map(x-> max(x,0), eflow_bus)
    eflow_in_bus = map(x-> max(-x,0), eflow_bus)

    
    # Create new things as needed
    cf = pgen_gen ./ pcap_gen
    replace!(cf, NaN=>0.0)

    # Add things to the bus table
    add_table_col!(data, :bus, :pgen,  pgen_bus,  MWGenerated,"Average Power Generated at this bus")
    add_table_col!(data, :bus, :egen,  egen_bus,  MWhGenerated,"Electricity Generated at this bus for the weighted representative hour")   
    add_table_col!(data, :bus, :pflow, pflow_bus, MWFlow,"Average power flowing out of this bus, positive or negative")
    add_table_col!(data, :bus, :eflow, eflow_bus, MWhFlow,"Electricity flowing out of this bus, positive or negative")
    add_table_col!(data, :bus, :pflow_out, pflow_out_bus, MWFlow,"Average power flowing out of this bus, positive")
    add_table_col!(data, :bus, :pflow_in, pflow_in_bus, MWFlow,"Average power flowing into this bus, positive")
    add_table_col!(data, :bus, :eflow_out, eflow_out_bus, MWhFlow,"Electricity flowing out of this bus, positive")
    add_table_col!(data, :bus, :eflow_in, eflow_in_bus, MWhFlow,"Electricity flowing into this bus, positive")
    add_table_col!(data, :bus, :plserv, plserv_bus, MWServed,"Average power served at this bus")
    add_table_col!(data, :bus, :elserv, elserv_bus, MWhServed,"Electricity served at this bus for the weighted representative hour")      
    add_table_col!(data, :bus, :plcurt, plcurt_bus, MWCurtailed,"Average power curtailed at this bus")
    add_table_col!(data, :bus, :elcurt, elcurt_bus, MWhCurtailed,"Electricity curtailed at this bus for the weighted representative hour")   
    add_table_col!(data, :bus, :elnom,  elnom_bus,  MWhLoad,"Electricity load at this bus for the weighted representative hour")   

    # Add things to the gen table
    add_table_col!(data, :gen, :pgen,  pgen_gen,  MWGenerated,"Average power generated at this generator")
    add_table_col!(data, :gen, :egen,  egen_gen,  MWhGenerated,"Electricity generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :pcap,  pcap_gen,  MWCapacity,"Power capacity of this generator generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :cf,    cf,        MWhGeneratedPerMWhCapacity, "Capacity Factor, or average power generation/power generation capacity, 0 when no generation")

    # Add things to the branch table
    add_table_col!(data, :branch, :pflow, pflow_branch, MWFlow,"Average Power flowing through branch")    
    add_table_col!(data, :branch, :eflow, eflow_branch, MWhFlow,"Electricity flowing through branch")    

    return
end
export parse_power_results!

@doc raw"""
    parse_lmp_results!(config, data, res_raw)

Adds the locational marginal prices of electricity and power flow.

| table_name | col_name | unit | description |
| :-- | :-- | :-- | :-- |
| :bus | :lmp_elserv | DollarsPerMWhServed | Locational Marginal Price of Energy Served |
| :branch | :lmp_pflow | DollarsPerMWFlow | Locational Marginal Price of Power Flow |
"""
function parse_lmp_results!(config, data)
    res_raw = get_raw_results(data)
    
    # Get the shadow price of the average power flow constraint ($/MW flowing)
    cons_pbal = res_raw[:cons_pbal]::Array{Float64,3}

    # Divide by number of hours because we want $/MWh, not $/MW
    lmp_elserv = unweight_hourly(data, cons_pbal, -)
    
    # Add the LMP's to the results and to the bus table
    res_raw[:lmp_elserv_bus] = lmp_elserv
    add_table_col!(data, :bus, :lmp_elserv, lmp_elserv, DollarsPerMWhServed,"Locational Marginal Price of Energy Served")

    # # Get the shadow price of the positive and negative branch power flow constraints ($/(MW incremental transmission))      
    # cons_branch_pflow_neg = res_raw[:cons_branch_pflow_neg]::Containers.SparseAxisArray{Float64, 3, Tuple{Int64, Int64, Int64}}
    # cons_branch_pflow_pos = res_raw[:cons_branch_pflow_pos]::Array{Float64, 3}
    # lmp_pflow = -cons_branch_pflow_neg - cons_branch_pflow_pos
    
    # # Add the LMP's to the results and to the branch table
    # res_raw[:lmp_pflow_branch] = lmp_pflow
    # add_table_col!(data, :branch, :lmp_pflow, lmp_pflow, DollarsPerMWFlow,"Locational Marginal Price of Power Flow")
    return
end
export parse_lmp_results!


"""
    save_updated_gen_table(config, data) -> nothing

Save the `gen` table to `get_out_path(config, "gen.csv")`
"""
function save_updated_gen_table(config, data)
    gen = get_table(data, :gen)
    original_cols = data[:gen_table_original_cols]

    # Grab only the original columns, and return to their original values for any that may have been modified.
    gen_tmp = gen[:, original_cols]
    for col_name in original_cols
        col = gen_tmp[!, col_name]
        if eltype(col) <: Container
            gen_tmp[!, col_name] = get_original.(gen_tmp[!, col_name])
        end
    end

    # Update pcap0 to be the last value of pcap
    gen_tmp.pcap0 = last.(gen.pcap)

    # Filter anything with capacity below the threshold
    thresh = config[:pcap_retirement_threshold]
    filter!(:pcap0 => >(thresh), gen_tmp)

    # Combine generators that are the same
    gdf = groupby(gen_tmp, Not(:pcap0))
    gen_tmp_combined = combine(gdf,
        :pcap0 => sum => :pcap0
    )
    gen_tmp_combined.pcap_max = copy(gen_tmp_combined.pcap0)


    CSV.write(get_out_path(config, "gen.csv"), gen_tmp_combined)
    return nothing
end
export save_updated_gen_table


"""
    update_build_status!(config, data, table_name)

Change the build_status of generators built in the simulation.
* `unbuilt -> new` if `last(pcap)` is above threshold
* `built -> retired_exog` if retired due to surpassing `year_off`
* `built -> retired_endog` if retired due before `year_off`
"""
function update_build_status!(config, data, table_name)
    years = get_years(data)
    gen = get_table(data, table_name)

    #Threshold capacity to be saved into the next run
    thresh = config[:pcap_retirement_threshold]

    for row in eachrow(gen)
        bs = row.build_status
        if bs == "unbuilt"
            last(row.pcap) >= thresh || continue
            row.build_status = "new"
        elseif bs == "built"
            yr_idx_ret = findfirst(<(thresh), row.pcap)
            isnothing(yr_idx_ret) && continue

            # Check to see if we retired because of being >= year_off
            if years[yr_idx_ret] >= row.year_off
                row.build_status = "retired_exog"
            else
                row.build_status = "retired_endog"
            end
        end
    end
end
export update_build_status!