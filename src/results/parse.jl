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

    od = object_dictionary(model)

    # Pull out all the shadow prices or values for each of the variables/constraints
    results_raw = Dict(k => (@info "Parsing Result $k"; value_or_shadow_price(v, obj_scalar)) for (k,v) in od)
    pgen_scalar = config[:pgen_scalar] |> Float64
    results_raw[:cons_pgen_max] ./= pgen_scalar
    
    # Gather each of the objective function coefficients
    obj = model[:obj]::AffExpr
    obj_coef = OrderedDict{Symbol, Any}()
    for (k,v) in od
        if v isa AbstractArray{<:VariableRef}
            obj_coef[k] = map(x->obj[x], v)
        end
    end
    obj_coef[:pcap_gen_inv_sim] = map(x->obj[x], model[:pcap_gen_inv_sim])
    results_raw[:obj_coef] = obj_coef

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

"""
    get_shadow_price_as_ByYear(data, cons_name::Symbol) -> 

Returns a ByYear Container of the shadow price of a constraint. The shadow price is set to 0 for years where there is no constraint. 
"""
function get_shadow_price_as_ByYear(data, cons_name::Symbol)
    years = Symbol.(get_years(data))
    shadow_prc = get_raw_result(data, cons_name)

    # set the shadow prices in array form with all sim years, set to 0 if no shadow price in that year
    if typeof(shadow_prc) <: JuMP.Containers.DenseAxisArray #DenseAxisArray and SparseAxisArray are container types for JuMP (not E4ST Containers) and need to be accessed in different ways
        # get the years where the shadow price has a value
        cons_years = (axes(shadow_prc)[1])
        # set values 
        shadow_prc_array  = [year in cons_years ? shadow_prc[year] : 0 for year in years]
    elseif typeof(shadow_prc) <: JuMP.Containers.SparseAxisArray
        shadow_prc_array = []
        for year_idx in 1:length(years)
            # check if shadow_prc has the year and then set value
            haskey(shadow_prc, year_idx) ? push!(shadow_prc_array, shadow_prc[year_idx]) : push!(shadow_prc_array, 0)
        end
    else 
        @error "shadow_prc is not a DenseAxisArray or SparseAxisArray and so the sim years are not tied to the shadow price. No way of mapping shadow price to years currently defined"
        # If you are getting this error, go and look at the JuMP documentation for Containers (different then E4ST Constainers). There is currently no option written for shadow prices that are Arrays but there could be. 
    end

    return ByYear(shadow_prc_array)
end
export get_shadow_price_as_ByYear

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
| :bus | :eflow_in | MWhFlow | Electricity flowing out of this bus |
| :bus | :pflow_out | MWFlow | Average power flowing into this bus |
| :bus | :eflow_out | MWhFlow | Electricity flowing out of this bus |
| :bus | :plserv | MWServed | Average power served at this bus |
| :bus | :elserv | MWhServed | Electricity served at this bus for the weighted representative hour |
| :bus | :plcurt | MWCurtailed | Average power curtailed at this bus |
| :bus | :elcurt | MWhCurtailed | Electricity curtailed at this bus for the weighted representative hour |
| :bus | :elnom  | MWhLoad | Electricity load at this bus for the weighted representative hour |
| :gen | :pgen | MWGenerated | Average power generated at this generator |
| :gen | :egen | MWhGenerated | Electricity generated at this generator for the weighted representative hour |
| :gen | :pcap | MWCapacity | Power generation capacity of this generator generated at this generator for the weighted representative hour |
| :gen | :ecap | MWhCapacity | Total energy generation capacity of this generator generated at this generator for the weighted representative hour |
| :gen | :pcap_retired | MWCapacity | Power generation capacity that was retired in each year |
| :gen | :pcap_built | MWCapacity | Power generation capacity that was built in each year |
| :gen | :pcap_inv_sim | MWCapacity | Total power generation capacity that was invested for the generator during the sim.  (single value).  Still the same even after retirement |
| :gen | :ecap_inv_sim | MWhCapacity | Total annual power generation energy capacity that was invested for the generator during the sim.  (pcap_inv_sim * hours per year) (single value).  Still the same even after retirement |
| :gen | :cf | MWhGeneratedPerMWhCapacity | Capacity Factor, or average power generation/power generation capacity, 0 when no generation |
| :branch | :pflow | MWFlow | Average Power flowing through branch |
| :branch | :eflow | MWFlow | Total energy flowing through branch for the representative hour |
"""
function parse_power_results!(config, data)
    res_raw = get_raw_results(data)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    gen = get_table(data, :gen)
    hours_per_year = sum(get_hour_weights(data))


    pgen_gen = res_raw[:pgen_gen]::Array{Float64, 3}
    egen_gen = res_raw[:egen_gen]::Array{Float64, 3}
    pcap_gen = res_raw[:pcap_gen]::Array{Float64, 2}

    pcap_gen_inv_sim = res_raw[:pcap_gen_inv_sim]
    ecap_gen_inv_sim = pcap_gen_inv_sim .* hours_per_year

    pflow_branch = res_raw[:pflow_branch]::Array{Float64, 3}
    
    plserv_bus = res_raw[:plserv_bus]::Array{Float64, 3}
    plcurt_bus = res_raw[:plcurt_bus]::Array{Float64, 3}
    pgen_bus = res_raw[:pgen_bus]::Array{Float64, 3}
    pflow_bus = res_raw[:pflow_bus]::Array{Float64, 3}

    # Weight things by hour as needed
    egen_bus = weight_hourly(data, pgen_bus)
    ecap_gen = weight_hourly(data, pcap_gen)
    elserv_bus = weight_hourly(data, plserv_bus)
    elcurt_bus = weight_hourly(data, plcurt_bus)
    elnom_bus = weight_hourly(data, get_table_col(data, :bus, :plnom))
    eflow_bus = weight_hourly(data, pflow_bus)
    eflow_branch = weight_hourly(data, pflow_branch)

    pflow_out_bus = map(x-> max(x,0), pflow_bus)
    pflow_in_bus = map(x-> max(-x,0), pflow_bus)
    eflow_out_bus = map(x-> max(x,0), eflow_bus)
    eflow_in_bus = map(x-> max(-x,0), eflow_bus)

    obj_pcap_price_raw = res_raw[:obj_coef][:pcap_gen]::Array{Float64, 2}
    obj_pcap_price = obj_pcap_price_raw ./ hours_per_year
    obj_pgen_price_raw = res_raw[:obj_coef][:pgen_gen]::Array{Float64, 3}
    obj_pgen_price = unweight_hourly(data, obj_pgen_price_raw)
    obj_pcap_inv_price = res_raw[:obj_coef][:pcap_gen_inv_sim]::Vector{Float64}
    
    # Create new things as needed
    cf = pgen_gen ./ pcap_gen
    replace!(cf, NaN=>0.0)

    # Create capacity retired and added
    pcap_built = similar(pcap_gen)
    pcap_retired = similar(pcap_gen)
    gen = get_table(data, :gen)
    pcap0 = gen.pcap0::Vector{Float64}
    pcap_retired[:, 1] .= max.(pcap0 .- view(pcap_gen, :, 1), 0.0)
    pcap_built[:, 1]   .= max.(view(pcap_gen, :, 1) .- pcap0, 0.0)
    for yr_idx in 2:nyr
        pcap_prev = view(pcap_gen, :, yr_idx-1)
        pcap_cur  = view(pcap_gen, :, yr_idx)
        pcap_retired[:, yr_idx] .= max.( pcap_prev .- pcap_cur, 0.0)
        pcap_built[:, yr_idx]   .= max.( pcap_cur .- pcap_prev, 0.0)
    end


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
    add_table_col!(data, :gen, :ecap,  ecap_gen,  MWhCapacity,"Electricity generation capacity of this generator generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :pcap_retired, pcap_retired, MWCapacity, "Power generation capacity that was retired in each year")
    add_table_col!(data, :gen, :pcap_built,   pcap_built,   MWCapacity, "Power generation capacity that was built in each year")
    add_table_col!(data, :gen, :pcap_inv_sim, pcap_gen_inv_sim, MWCapacity, "Total power generation capacity that was invested for the generator during the sim.  (single value).  Still the same even after retirement")
    add_table_col!(data, :gen, :ecap_inv_sim, ecap_gen_inv_sim, MWhCapacity, "Total annual power generation energy capacity that was invested for the generator during the sim. (pcap_inv_sim * hours per year) (single value).  Still the same even after retirement")
    add_table_col!(data, :gen, :cf,    cf,        MWhGeneratedPerMWhCapacity, "Capacity Factor, or average power generation/power generation capacity, 0 when no generation")
    add_table_col!(data, :gen, :obj_pcap_price, obj_pcap_price, DollarsPerMWCapacityPerHour, "Objective function coefficient, in dollars, for one hour of 1MW capacity")
    add_table_col!(data, :gen, :obj_pgen_price, obj_pgen_price, DollarsPerMWhGenerated, "Objective function coefficient, in dollars, for one MWh of generation")
    add_table_col!(data, :gen, :obj_pcap_inv_price, obj_pcap_inv_price, DollarsPerMWBuiltCapacity, "Objective function coefficient, in dollars, for one MW of capacity invested")

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

    # Compensate for line losses for lmp seen by consumers at buses.
    if config[:line_loss_type] == "plserv"
        line_loss_rate = config[:line_loss_rate]::Float64

        # lmp_elserv is dollars per MWh before losses, so we need to inflate the cost to compensate
        plserv_scalar = 1/(1-line_loss_rate)
        add_table_col!(data, :bus, :lmp_elserv, lmp_elserv .* plserv_scalar, DollarsPerMWhServed,"Locational Marginal Price of Energy Served")
    else
        add_table_col!(data, :bus, :lmp_elserv, lmp_elserv, DollarsPerMWhServed,"Locational Marginal Price of Energy Served")
    end

    # Add lmp to generators
    gen = get_table(data, :gen)
    bus_idxs = gen.bus_idx::Vector{Int64}
    lmp_gen = [view(lmp_elserv, i, :, :) for i in bus_idxs]
    add_table_col!(data, :gen, :lmp_egen, lmp_gen, DollarsPerMWhServed, "Locational Marginal Price of Energy Served")

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
    years = get_years(data)
    year_end = last(years)

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
    gen_tmp.pcap_inv = map(eachrow(gen)) do row
        row.build_status == "new" || return row.pcap_inv
        return row.pcap_inv_sim
    end

    # Filter anything with capacity below the threshold
    thresh = config[:pcap_retirement_threshold]
    filter!(gen_tmp) do row
        # Keep anything above the threshold
        row.pcap0 > thresh && return true
        row.pcap_inv <= thresh && return false 

        row.build_type == "exog" && return false

        # Below the threshold, check to see if we are still within the economic lifetime
        year_econ_life = add_to_year(row.year_on, row.econ_life)
        year_econ_life > year_end && return true

        return false
    end

    # Combine generators that are the same.  This is for things like ccus that get split up.
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
* `built -> retired_exog` if retired due to surpassing `year_shutdown`
* `built -> retired_endog` if retired due before `year_shutdown`
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

            row.year_off = years[yr_idx_ret]

            # Check to see if we retired because of being >= year_off
            if years[yr_idx_ret] >= row.year_shutdown
                row.build_status = "retired_exog"
            else
                row.build_status = "retired_endog"
            end
        end
    end
end
export update_build_status!