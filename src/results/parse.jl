"""
    parse_results!(config, data, model) -> nothing
    
* Gathers the values and shadow prices of each variable, expression, and constraint stored in the model, unscales the shadow prices, and dumps them into `data[:results][:raw]` (see [`get_raw_results`](@ref) and [`get_results`](@ref)).
* Adds relevant info to `gen`, `bus`, and `branch` tables.  See [`parse_lmp_results!`](@ref) and [`parse_power_results!`](@ref) for more information.
* Saves updated `gen` table via [`save_updated_gen_table`](@ref)
* Saves `data` to `get_out_path(config,"data_parsed.jls")` unless `config[:save_data_parsed]` is `false` (true by default).
"""
function parse_results!(config, data, model)
    log_header("PARSING RESULTS")

    obj_scalar = config[:objective_scalar]
    yearly_obj_scalars = config[:yearly_objective_scalars]::Vector{<:Float64}

    model_keys_not_parsed = data[:do_not_parse_model_keys]::Set{Symbol}
    should_parse = !in(model_keys_not_parsed)

    # Pull out all the shadow prices or values for each of the variables/constraints
    results_raw = Dict{Symbol, Any}()
    od = object_dictionary(model)
    for (k,v) in od
        should_parse(k) && store_value_or_shadow_price!(results_raw, k, v, obj_scalar, yearly_obj_scalars)
    end

    # Scale cons_pgen_max if it has been parsed
    if haskey(results_raw, :cons_pgen_max)
        pgen_scalar = config[:pgen_scalar] |> Float64
        results_raw[:cons_pgen_max] ./= pgen_scalar
    end
    
    # Gather each of the objective function coefficients
    obj = sum(model[:obj])::AffExpr
    obj_coef = OrderedDict{Symbol, Any}()
    for (k,v) in od
        if v isa AbstractArray{<:VariableRef}
            obj_coef[k] = map(x->obj[x], v)
        end
    end
    obj_coef[:pcap_gen_inv_sim] = map(x->obj[x], model[:pcap_gen_inv_sim])
    results_raw[:obj_coef] = obj_coef

    # Gather each of the objective function coefficients unscaled for tests
    obj_unscaled = sum(model[:obj_unscaled])::AffExpr
    obj_coef_unscaled = OrderedDict{Symbol, Any}()
    for (k,v) in od
        if v isa AbstractArray{<:VariableRef}
            obj_coef_unscaled[k] = map(x->obj_unscaled[x], v)
        end
    end
    obj_coef_unscaled[:pcap_gen_inv_sim] = map(x->obj_unscaled[x], model[:pcap_gen_inv_sim])
    results_raw[:obj_coef_unscaled] = obj_coef_unscaled

    # Empty the model now that we have retrieved all info, to save RAM and prevent the user from accidentally accessing un-scaled data.
    empty!(model)
    
    results = OrderedDict{Symbol, Any}()
    data[:results] = results
    results[:raw] = results_raw

    check_voltage_angle_bounds(config, data)
    parse_lmp_results!(config, data)
    parse_power_results!(config, data)

    #change build_status to 'new' for generators built in the sim
    update_build_status!(config, data, :gen)

    # Save the parsed data
    if config[:save_data_parsed] === true
        serialize(get_out_path(config, "data_parsed.jls"), data)
    end

    save_updated_gen_table(config, data)

    return nothing
end

"""
    check_voltage_angle_bounds(config, data)

errors if the voltage angles are too close to the bounds (they should never be binding)
"""
function check_voltage_angle_bounds(config, data)
    θ_bound = config[:voltage_angle_bound] |> Float64
    res_raw = get_raw_results(data)
    θ = res_raw[:θ_bus]::Array{Float64, 3}

    (Θ_min, θ_max) = extrema(θ)

    if max(abs(Θ_min), θ_max) >= (θ_bound * (1 - 0.01))
        if config[:error_if_voltage_angle_at_bound] == true
            error("Voltage angle is within 1% of the bounds, that indicates something is wrong with the grid representation, or that config[:voltage_angle_bound] needs to be increased.")
        else
            @warn "Voltage angle is within 1% of the bounds, that indicates something is wrong with the grid representation, or that config[:voltage_angle_bound] needs to be increased."
        end
    end
end
export check_voltage_angle_bounds


"""
    store_value_or_shadow_price!(results_raw, k, v, obj_scalar)

Stores the value or shadow price if it is reasonable to do so.  Will not store shadow price for equality constraints
"""
function store_value_or_shadow_price!(results_raw, k, v, obj_scalar, yearly_obj_scalars)
    if is_equality_constraint(v)
        @warn "Cannot compute shadow price for equality constraint $k, because its value is ambiguous.  Consider seperating into two inequality constraints"
        return
    end

    @info "Parsing results for $k"
    results_raw[k] = value_or_shadow_price(v, obj_scalar, yearly_obj_scalars)
    return
end
export store_value_or_shadow_price!

is_equality_constraint(cons::ConstraintRef{M, CI}) where {F, M <: AbstractModel, CI<:MOI.ConstraintIndex{F, MOI.EqualTo{Float64}}} = true
is_equality_constraint(cons::ConstraintRef) = false
is_equality_constraint(cons::AbstractJuMPScalar) = false
is_equality_constraint(cons::Number) = false
is_equality_constraint(cons::AbstractArray) = isempty(cons) ? false : is_equality_constraint(first(cons))

"""
    value_or_shadow_price(constraints, obj_scalar) -> shadow_prices*obj_scalar

    value_or_shadow_price(variables, obj_scalar) -> values

    value_or_shadow_price(expressions, obj_scalar) -> values

Returns a value or shadow price depending on what is passed in.  Used in [`results_raw!`](@ref).  Scales shadow prices by `obj_scalar` to restore to units of dollars (per applicable unit).
"""
function value_or_shadow_price(ar::AbstractArray{<:ConstraintRef}, obj_scalar, yearly_obj_scalars) 
    n_dims = ndims(ar)
    nyr =  length(yearly_obj_scalars)

    if n_dims == 1 && size(ar,1) == nyr
        [value_or_shadow_price(ar[i], obj_scalar, yearly_obj_scalars[i]) for i in axes(ar, 1)]
    elseif n_dims == 2 && size(ar,2) == nyr
        [value_or_shadow_price(ar[i, j], obj_scalar, yearly_obj_scalars[j]) for i in axes(ar, 1), j in axes(ar, 2)]
    elseif n_dims == 3 && size(ar,2) == nyr
        [value_or_shadow_price(ar[i, j, k], obj_scalar, yearly_obj_scalars[j]) for i in axes(ar, 1), j in axes(ar, 2), k in axes(ar, 3)]
    else
        @warn "Year is not in expected dimension, shadow price has not been unscaled."
        value_or_shadow_price.(ar, obj_scalar)
    end
end
function value_or_shadow_price(ar::JuMP.Containers.SparseAxisArray{<:ConstraintRef}, obj_scalar, yearly_obj_scalars)
    n_dims = length(first(eachindex(ar)))
    nyr = length(yearly_obj_scalars)

    sp = shadow_price.(ar) * obj_scalar
    if n_dims ==1 
        for yr_idx in 1:nyr
            yr_scalar = yearly_obj_scalars[yr_idx]
            for idx in eachindex(sp)
                if idx[1] == yr_idx
                    sp[idx] = sp[idx]/yr_scalar
                end
            end
        end
    elseif n_dims == 2 || n_dims ==3
        for yr_idx in 1:nyr
            yr_scalar = yearly_obj_scalars[yr_idx]
            for idx in eachindex(sp)
                if idx[2] == yr_idx
                    sp[idx] = sp[idx]/yr_scalar
                end
            end
        end
    else
        @warn "Year is not in expected dimension, shadow price has not been unscaled."
    end
    return sp
end
function value_or_shadow_price(ar::AbstractArray{<:AbstractJuMPScalar}, obj_scalar)
    value.(ar)
end
function value_or_shadow_price(cons::ConstraintRef{M, CI}, obj_scalar) where {F, M <: AbstractModel, CI<:MOI.ConstraintIndex{F, MOI.EqualTo{Float64}}}
    @warn "Shadow price is misleading for equality constraints!"
    shadow_price(cons) * obj_scalar
end
function value_or_shadow_price(cons::ConstraintRef{M, CI}, obj_scalar, yr_scalar) where {F, M <: AbstractModel, CI<:MOI.ConstraintIndex{F, MOI.EqualTo{Float64}}}
    @warn "Shadow price is misleading for equality constraints!"
    shadow_price(cons) * obj_scalar / yr_scalar
end
function value_or_shadow_price(cons::ConstraintRef, obj_scalar)
    shadow_price(cons) * obj_scalar
end
function value_or_shadow_price(cons::ConstraintRef, obj_scalar, yr_scalar)
    shadow_price(cons) * obj_scalar / yr_scalar
end
function value_or_shadow_price(x::AbstractJuMPScalar, obj_scalar)
    value(x)
end
function value_or_shadow_price(x::Float64, obj_scalar)
    return x
end
function value_or_shadow_price(ar::AbstractArray, obj_scalar, yearly_obj_scalars)
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
| :bus | :pflow | MWFlow | Average power flowing out of this bus |
| :bus | :pflow_in | MWFlow | Average power flowing into this bus |
| :bus | :pflow_out | MWFlow | Average power flowing into this bus |
| :bus | :plserv | MWServed | Average power served at this bus |
| :bus | :plcurt | MWCurtailed | Average power curtailed at this bus |
| :gen | :pgen | MWGenerated | Average power generated at this generator |
| :gen | :pcap | MWCapacity | Power generation capacity of this generator generated at this generator for the weighted representative hour |
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
    
    pflow_out_bus = map(x-> max(x, 0.), pflow_bus)
    pflow_in_bus = map(x-> max(-x, 0.), pflow_bus)

    obj_pcap_cost_raw = res_raw[:obj_coef][:pcap_gen]::Array{Float64, 2}
    obj_pcap_cost = obj_pcap_cost_raw ./ hours_per_year
    obj_pgen_cost_raw = res_raw[:obj_coef][:pgen_gen]::Array{Float64, 3}
    obj_pgen_cost = unweight_hourly(data, obj_pgen_cost_raw)
    obj_pcap_inv_price = res_raw[:obj_coef][:pcap_gen_inv_sim]::Vector{Float64}

    # get unscaled objective values for tests
    obj_pcap_cost_raw_unscaled = res_raw[:obj_coef_unscaled][:pcap_gen]::Array{Float64, 2}
    obj_pcap_cost_unscaled = obj_pcap_cost_raw_unscaled ./ hours_per_year
    obj_pgen_cost_raw_unscaled = res_raw[:obj_coef_unscaled][:pgen_gen]::Array{Float64, 3}
    obj_pgen_cost_unscaled = unweight_hourly(data, obj_pgen_cost_raw_unscaled)
    obj_pcap_inv_price_unscaled = res_raw[:obj_coef_unscaled][:pcap_gen_inv_sim]::Vector{Float64}
    
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
    add_table_col!(data, :bus, :pflow_out, pflow_out_bus, MWFlow,"Average power flowing out of this bus, positive")
    add_table_col!(data, :bus, :pflow_in, pflow_in_bus, MWFlow,"Average power flowing into this bus, positive")
    add_table_col!(data, :bus, :plserv, plserv_bus, MWServed,"Average power served at this bus")
    add_table_col!(data, :bus, :plcurt, plcurt_bus, MWCurtailed,"Average power curtailed at this bus")
    
    # Add things to the gen table
    add_table_col!(data, :gen, :pgen,  pgen_gen,  MWGenerated,"Average power generated at this generator")
    add_table_col!(data, :gen, :pcap,  pcap_gen,  MWCapacity,"Power capacity of this generator generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :pcap_retired, pcap_retired, MWCapacity, "Power generation capacity that was retired in each year")
    add_table_col!(data, :gen, :pcap_built,   pcap_built,   MWCapacity, "Power generation capacity that was built in each year")
    add_table_col!(data, :gen, :pcap_inv_sim, pcap_gen_inv_sim, MWCapacity, "Total power generation capacity that was invested for the generator during the sim.  (single value).  Still the same even after retirement")
    add_table_col!(data, :gen, :ecap_inv_sim, ecap_gen_inv_sim, MWhCapacity, "Total annual power generation energy capacity that was invested for the generator during the sim. (pcap_inv_sim * hours per year) (single value).  Still the same even after retirement")
    add_table_col!(data, :gen, :cf,    cf,        MWhGeneratedPerMWhCapacity, "Capacity Factor, or average power generation/power generation capacity, 0 when no generation")
    add_table_col!(data, :gen, :obj_pcap_cost, obj_pcap_cost, DollarsPerMWCapacityPerHour, "Objective function coefficient, in dollars, for one hour of 1MW capacity")
    add_table_col!(data, :gen, :obj_pgen_cost, obj_pgen_cost, DollarsPerMWhGenerated, "Objective function coefficient, in dollars, for one MWh of generation")
    add_table_col!(data, :gen, :obj_pcap_cost_unscaled, obj_pcap_cost_unscaled, DollarsPerMWCapacityPerHour, "Objective function coefficient, in dollars, for one hour of 1MW capacity")
    add_table_col!(data, :gen, :obj_pgen_cost_unscaled, obj_pgen_cost_unscaled, DollarsPerMWhGenerated, "Objective function coefficient, in dollars, for one MWh of generation")
    add_table_col!(data, :gen, :obj_pcap_inv_price, obj_pcap_inv_price, DollarsPerMWBuiltCapacityPerHour, "Objective function coefficient, in dollars, for one MW of capacity invested")

    # Add things to the branch table
    add_table_col!(data, :branch, :pflow, pflow_branch, MWFlow,"Average Power flowing through branch")    

    # Update pcap_inv
    gen.pcap_inv = max.(gen.pcap_inv, gen.pcap_inv_sim)

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
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    res_raw = get_raw_results(data)

    branch = get_table(data, :branch)
    f_bus_idxs = branch.f_bus_idx::Vector{Int64}
    t_bus_idxs = branch.t_bus_idx::Vector{Int64}
    
    # Get the shadow price of the average power flow constraint ($/MW flowing)
    cons_pbal_geq = res_raw[:cons_pbal_geq]::Array{Float64, 3}
    cons_pbal_leq = res_raw[:cons_pbal_leq]::Array{Float64, 3}
    cons_pbal = cons_pbal_geq .- cons_pbal_leq
    res_raw[:cons_pbal] = cons_pbal
    delete!(res_raw, :cons_pbal_geq)
    delete!(res_raw, :cons_pbal_leq)

    # Divide by number of hours because we want $/MWh, not $/MW
    lmp_elserv = unweight_hourly(data, cons_pbal, -)
    
    # Add the LMP's to the results and to the bus table
    res_raw[:lmp_elserv_bus] = lmp_elserv

    # Compensate for line losses for lmp seen by users at buses.
    if config[:line_loss_type] == "plserv"
        line_loss_rate = config[:line_loss_rate]::Float64

        # lmp_elserv is dollars per MWh before losses, so we need to inflate the cost to compensate
        plserv_scalar = 1/(1-line_loss_rate)
        add_table_col!(data, :bus, :lmp_elserv_preloss, lmp_elserv, DollarsPerMWhServed,"Locational Marginal Price of Energy Served, before including T&D losses")
        add_table_col!(data, :bus, :lmp_elserv, lmp_elserv .* plserv_scalar, DollarsPerMWhServed,"Locational Marginal Price of Energy Served (scaled up from lmp_elserv_preloss to include T&D losses)")
    else
        add_table_col!(data, :bus, :lmp_elserv, lmp_elserv, DollarsPerMWhServed,"Locational Marginal Price of Energy Served")
    end

    # Add lmp to generators
    gen = get_table(data, :gen)
    bus_idxs = gen.bus_idx::Vector{Int64}
    lmp_gen = [view(lmp_elserv, i, :, :) for i in bus_idxs]
    add_table_col!(data, :gen, :lmp_egen, lmp_gen, DollarsPerMWhServed, "Locational Marginal Price of Energy Generated (pre-loss)")

    # # Get the shadow price of the positive and negative branch power flow constraints ($/(MW incremental transmission))      
    # cons_branch_pflow_neg = res_raw[:cons_branch_pflow_neg]::Containers.SparseAxisArray{Float64, 3, Tuple{Int64, Int64, Int64}}
    # cons_branch_pflow_pos = res_raw[:cons_branch_pflow_pos]::Array{Float64, 3}
    # lmp_pflow = -cons_branch_pflow_neg - cons_branch_pflow_pos

    pflow_branch = res_raw[:pflow_branch]::Array{Float64, 3}
    hour_weights = get_hour_weights(data)
    hour_weights_mat = [hour_weights[hr_idx] for yr_idx in 1:nyr, hr_idx in 1:nhr]

    # Loop through each branch and add the hourly merchandising surplus, in dollars, to the appropriate bus
    ms = zeros(size(lmp_elserv)) # nbus x nyr x nhr
    ms_branch = zeros(size(pflow_branch))
    
    for branch_idx in 1:nrow(branch)
        f_bus_idx = f_bus_idxs[branch_idx]
        t_bus_idx = t_bus_idxs[branch_idx]
        f_bus_lmp = view(lmp_elserv, f_bus_idx, :, :) # nyr x nhr
        t_bus_lmp = view(lmp_elserv, t_bus_idx, :, :) # nyr x nhr
        pflow = view(pflow_branch, branch_idx, :, :) # nyr x nhr
        ms_per_bus = ((t_bus_lmp .- f_bus_lmp) .* pflow) .* hour_weights_mat .* 0.5
        ms[f_bus_idx, :, :] .+= ms_per_bus
        ms[t_bus_idx, :, :] .+= ms_per_bus
        ms_branch[branch_idx, :, :] = ms_per_bus .* 2
    end

    add_table_col!(data, :bus, :merchandising_surplus, ms, Dollars, "Merchandising surplus, in dollars, from selling electricity for a higher price at one end of a line than another.")
    
    add_table_col!(data, :branch, :merchandising_surplus, ms_branch, Dollars, "Merchandising surplus, in dollars, from selling electricity for a higher price at one end of a line than another.")
    
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
    nyr = get_num_years(data)
    year_end = last(years)

    gen = get_table(data, :gen)
    original_cols = data[:gen_table_original_cols]
    unique!(original_cols)

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

    #update pcap_plant_avg, pcap_hist and pgen to -1 instead of -Inf to be excel compatible 
    for row in eachrow(gen_tmp)
        row.build_type == "endog" || continue
        haskey(row, :pcap_plant_avg) && row.pcap_plant_avg == -Inf && (row.pcap_plant_avg = -1.)
        haskey(row, :pcap_hist) && row.pcap_hist == -Inf && (row.pcap_hist = -1.)
        haskey(row, :pgen_hist) && row.pgen_hist == -Inf && (row.pgen_hist = -1.)
    end

    # Gather the past investment costs and subsidies
    @info "updating the past investment cost/subsidy for new generators"
    for i in 1:nrow(gen_tmp)
        gen_tmp.build_status[i] == "new" || continue
        gen_tmp.past_invest_cost[i] =    maximum(yr_idx->compute_result(data, :gen, :invest_cost_permw_perhr, i, yr_idx), 1:nyr)
        gen_tmp.past_invest_subsidy[i] = maximum(yr_idx->compute_result(data, :gen, :invest_subsidy_permw_perhr, i, yr_idx), 1:nyr)
    end

    # Filter anything with capacity below the threshold
    thresh = config[:pcap_retirement_threshold]
    filter!(gen_tmp) do row
        # Keep anything above the threshold
        row.pcap0 > thresh && return true
        row.pcap_inv <= thresh && return false 

        row.build_type == "exog" && return false # We don't care to keep track of exogenous past capex

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

    file_out = get_out_path(config, "gen.csv") 
    CSV.write(file_out, gen_tmp_combined)

    # Update config[:gen_file] to be from the current out_path
    if issequential(get_iterator(config))
        config[:gen_file] = file_out
    end
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
        if bs in ("unbuilt", "unretrofitted")
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
