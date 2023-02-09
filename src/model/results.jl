"""
    parse_results(config, data, results_raw) -> results

Retrieves results from the results_raw, including:
* Area/Annual results (?)
* Raw policy results (?)
* Welfare 
"""
function process_results(config, data, results_raw)

    results_user = OrderedDict{Symbol, Any}()

    process_lmp!(config, data, results_raw)
    process_power!(config, data, results_raw)
    
    for (name, mod) in getmods(config)
        modify_results!(mod, config, data, results_raw, results_user)
    end

    return results_user
end

"""
    parse_results(config, data, model) -> results_raw
    
Simply gathers the values and shadow prices of each variable, expression, and constraint stored in the model and dumps them into `results_raw::Dict`.

Saves them to `out_path(config,"results_raw.jls")` unless `config[:save_results_raw]` is `false` (true by default).
"""
function parse_results(config, data, model)
    results_raw = Dict(k => value_or_shadow_price(v) for (k,v) in object_dictionary(model))
    # Don't add anything else here, we want to preserve the purity of these raw results, so that we can get rid of the model.  Add any standard processing to process_results.
    if get(config, :save_results_raw, true)
        serialize(out_path(config,"results_raw.jls"), results_raw)
    end

    return results_raw
end

"""
    value_or_shadow_price(constraints) -> shadow_prices

    value_or_shadow_price(variables) -> values

    value_or_shadow_price(expressions) -> values

Returns a value or shadow price depending on what is passed in.  Used in [`results_raw!`](@ref)
"""
function value_or_shadow_price(ar::AbstractArray{<:ConstraintRef})
    shadow_price.(ar)    
end
function value_or_shadow_price(ar::AbstractArray{<:AbstractJuMPScalar})
    value.(ar)
end
function value_or_shadow_price(cons::ConstraintRef)
    shadow_price(cons)
end
function value_or_shadow_price(x::AbstractJuMPScalar)
    value(x)
end
export value_or_shadow_price


# ECR: I don't think we'll ever use the function below, commenting out for now.
# """
#     weight_hourly!(data, ar)
#     weight_hourly!(data, ar, sign=+)

# Multiplies (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
# """
# function weight_hourly!(data, ar, s=+)
#     weights = get_hour_weights(data)
#     for (hr_idx, hr_wgt) in enumerate(weights)
#         v = view(ar, :, :, hr_idx)
#         _hr_wgt = s(hr_wgt)
#         v .*= _hr_wgt
#     end
#     return
# end
# export weight_hourly!

"""
    weight_hourly(data, ar, sign=+)

Multiplies each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function weight_hourly(data, ar::AbstractArray{<:Any, I}, s=+) where I
    w = get_hour_weights(data)
    return [s(ar[ci]) * w[ci[I]] for ci in CartesianIndices(ar)]
end
export weight_hourly


# ECR: I don't think we'll ever use the function below, commenting out for now.
# """
#     unweight_hourly!(data, ar, sign=+)

# Divides (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
# """
# function unweight_hourly!(data, ar, s=+)
#     weights = get_hour_weights(data)
#     for (hr_idx, hr_wgt) in enumerate(weights)
#         v = view(ar, :, :, hr_idx)
#         inv_hr_weight = s(1/hr_wgt)
#         v .*= inv_hr_weight
#     end
#     return
# end
# export unweight_hourly!

"""
    unweight_hourly(data, ar, sign=+)

Multiplies each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function unweight_hourly(data, ar::AbstractArray{<:Any, I}, s=+) where I
    w = get_hour_weights(data)
    return [s(ar[ci]) / w[ci[I]] for ci in CartesianIndices(ar)]
end
export unweight_hourly

@doc raw"""
    process_power!(config, data, res_raw)

Adds power-based results.  See also [`get_table_summary`](@ref) for the below summaries.

| table_name | col_name | unit | description |
| :-- | :-- | :-- | :-- |
| :bus | :pgen | MWGenerated | Average Power Generated at this bus |
| :bus | :egen | MWhGenerated | Electricity Generated at this bus for the weighted representative hour |
| :bus | :pflow | MWFlow | Average power flowing out of this bus |
| :bus | :pserv | MWServed | Average power served at this bus |
| :bus | :eserv | MWhServed | Electricity served at this bus for the weighted representative hour |
| :bus | :pcurt | MWCurtailed | Average power curtailed at this bus |
| :bus | :ecurt | MWhCurtailed | Electricity curtailed at this bus for the weighted representative hour |
| :gen | :pgen | MWGenerated | Average power generated at this generator |
| :gen | :egen | MWhGenerated | Electricity generated at this generator for the weighted representative hour |
| :gen | :pcap | MWCapacity | Power capacity of this generator generated at this generator for the weighted representative hour |
| :gen | :cf | MWhGeneratedPerMWhCapacity | Capacity Factor, or average power generation/power generation capacity, 0 when no generation |
| :branch | :pflow | MWFlow | Average Power flowing through branch |
"""
function process_power!(config, data, res_raw)
    pgen_gen = res_raw[:pgen_gen]::Array{Float64, 3}
    egen_gen = res_raw[:egen_gen]::Array{Float64, 3}
    pcap_gen = res_raw[:pcap_gen]::Array{Float64, 2}

    pflow_branch = res_raw[:pflow_branch]::Array{Float64, 3}
    
    pserv_bus = res_raw[:pserv_bus]::Array{Float64, 3}
    pcurt_bus = res_raw[:pcurt_bus]::Array{Float64, 3}
    pgen_bus = res_raw[:pgen_bus]::Array{Float64, 3}
    pflow_bus = res_raw[:pflow_bus]::Array{Float64, 3}

    # Weight things by hour as needed
    egen_bus = weight_hourly(data, pgen_bus)
    eserv_bus = weight_hourly(data, pserv_bus)
    ecurt_bus = weight_hourly(data, pcurt_bus)
    
    # Create new things as needed
    cf = pgen_gen ./ pcap_gen
    replace!(cf, NaN=>0.0)

    # Add things to the bus table
    add_table_col!(data, :bus, :pgen,  pgen_bus,  MWGenerated,"Average Power Generated at this bus")
    add_table_col!(data, :bus, :egen,  egen_bus,  MWhGenerated,"Electricity Generated at this bus for the weighted representative hour")   
    add_table_col!(data, :bus, :pflow, pflow_bus, MWFlow,"Average power flowing out of this bus")
    add_table_col!(data, :bus, :pserv, pserv_bus, MWServed,"Average power served at this bus")
    add_table_col!(data, :bus, :eserv, eserv_bus, MWhServed,"Electricity served at this bus for the weighted representative hour")      
    add_table_col!(data, :bus, :pcurt, pcurt_bus, MWCurtailed,"Average power curtailed at this bus")
    add_table_col!(data, :bus, :ecurt, ecurt_bus, MWhCurtailed,"Electricity curtailed at this bus for the weighted representative hour")   

    # Add things to the gen table
    add_table_col!(data, :gen, :pgen,  pgen_gen,  MWGenerated,"Average power generated at this generator")
    add_table_col!(data, :gen, :egen,  egen_gen,  MWhGenerated,"Electricity generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :pcap,  pcap_gen,  MWCapacity,"Power capacity of this generator generated at this generator for the weighted representative hour")
    add_table_col!(data, :gen, :cf,    cf,        MWhGeneratedPerMWhCapacity, "Capacity Factor, or average power generation/power generation capacity, 0 when no generation")

    # Add things to the branch table
    add_table_col!(data, :branch, :pflow, pflow_branch, MWFlow,"Average Power flowing through branch")    

    return
end
export process_power!

@doc raw"""
    process_lmp!(config, data, res_raw)

Adds the locational marginal prices of electricity and power flow.

| table_name | col_name | unit | description |
| :-- | :-- | :-- | :-- |
| :bus | :lmp_eserv | DollarsPerMWhServed | Locational Marginal Price of Energy Served |
| :branch | :lmp_pflow | DollarsPerMWFlow | Locational Marginal Price of Power Flow |
"""
function process_lmp!(config, data, res_raw)
    # Get the shadow price of the average power flow constraint ($/MW flowing)
    cons_pflow = res_raw[:cons_pflow]::Array{Float64,3}
    # Divide by number of hours because we want $/MWh, not $/MW
    lmp_eserv = unweight_hourly(data, cons_pflow, -)
    
    # Add the LMP's to the results and to the bus table
    res_raw[:lmp_eserv_bus] = lmp_eserv
    add_table_col!(data, :bus, :lmp_eserv, lmp_eserv, DollarsPerMWhServed,"Locational Marginal Price of Energy Served")

    # Get the shadow price of the positive and negative branch power flow constraints ($/(MW incremental transmission))      
    cons_branch_pflow_neg = res_raw[:cons_branch_pflow_neg]::Array{Float64, 3}
    cons_branch_pflow_pos = res_raw[:cons_branch_pflow_pos]::Array{Float64, 3}
    lmp_pflow = -cons_branch_pflow_neg - cons_branch_pflow_pos
    
    # Add the LMP's to the results and to the branch table
    res_raw[:lmp_pflow_branch] = lmp_pflow
    add_table_col!(data, :branch, :lmp_pflow, lmp_pflow, DollarsPerMWFlow,"Locational Marginal Price of Power Flow")
    return
end
export process_lmp!

function get_all_cons(model)
    return all_constraints(model, include_variable_in_set_constraints=false)
end
export get_all_cons

function get_model_val_by_gen(data, model, name::Symbol, idxs = :, year_idxs = :, hour_idxs = :)
    _idxs, _year_idxs, _hour_idxs = get_gen_array_idxs(data, idxs, year_idxs, hour_idxs)
    v = _view_model(model, name, _idxs, _year_idxs, _hour_idxs)
    isempty(v) && return 0.0
    return sum(value, v)
end
export get_model_val_by_gen

function get_gen_result(data, model, ::PerMWhGen, gen_idxs = :, year_idxs = :, hour_idxs = :)
    _gen_idxs = get_gen_array_idxs(data, gen_idxs)
    _year_idxs = get_year_idxs(data, year_idxs)
    _hour_idxs = get_hour_idxs(data, hour_idxs)
    var = model[:egen_gen]::Array{AffExpr, 3}
    v = view(var, _gen_idxs, _year_idxs, _hour_idxs)
    isempty(v) && return 0.0
    return sum(value, v)
end

function get_gen_result(data, model, ::PerMWhGen, col_name::Union{Symbol, String}, gen_idxs = :, year_idxs = :, hour_idxs = :)
    _gen_idxs = get_gen_array_idxs(data, gen_idxs)
    _year_idxs = get_year_idxs(data, year_idxs)
    _hour_idxs = get_hour_idxs(data, hour_idxs)
    var = model[:egen_gen]::Array{AffExpr, 3}
    # v = view(var, _gen_idxs, _year_idxs, _hour_idxs)
    # isempty(v) && return 0.0

    isempty(_gen_idxs)  && return 0.0
    isempty(_year_idxs) && return 0.0
    isempty(_hour_idxs) && return 0.0

    return sum(value(var[g,y,h]) * get_gen_value(data, col_name, g, y, h) for g in _gen_idxs, y in _year_idxs, h in _hour_idxs)
end
export get_gen_result

function _view_model(model, name, idxs, year_idxs, hour_idxs)
    var = model[name]::Array{<:Any, 3}
    return view(var, idxs, year_idxs, hour_idxs)
end

function get_gen_array_idxs(data, idxs, year_idxs, hour_idxs)
    _idxs = get_gen_array_idxs(data, idxs)
    _year_idxs = get_year_idxs(data, year_idxs)
    _hour_idxs = get_hour_idxs(data, hour_idxs)
    return _idxs, _year_idxs, _hour_idxs
end


function get_gen_array_idxs(data, idxs)
    return get_row_idxs(get_table(data, :gen), idxs)
end

export get_gen_array_idxs

"""
    aggregate_result(f::Function, data, res_raw, table_name, col_name, idxs=(:), yr_idxs=(:), hr_idxs=(:)) -> x::Float64
"""
function aggregate_result(f::Function, data, res_raw, table_name, col_name, idxs=(:), yr_idxs=(:), hr_idxs=(:))
    table = get_table(data, table_name)
    unit = get_table_col_unit(data, table_name, col_name)
    _idxs = get_row_idxs(table, idxs)
    _yr_idxs = get_year_idxs(data, yr_idxs)
    _hr_idxs = get_hour_idxs(data, hr_idxs)
    f(unit, data, res_raw, table, col_name, _idxs, _yr_idxs, _hr_idxs)
end
export aggregate_result

export total

function total(::Type{ShortTonsPerMWhGenerated}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end

function total(::Type{DollarsPerMWhServed}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :eserv], idxs, yr_idxs, hr_idxs)
end
function total(::Type{DollarsPerMWhGenerated}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
function total(::Type{DollarsPerMWCapacity}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_sum(table[!, column_name], table[!, :pcap], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhServed}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhGenerated}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end
function total(::Type{MWhCurtailed}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return total_sum(table[!, column_name], idxs, yr_idxs, hr_idxs)
end

"""
    total(::Type{MWCapacity}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)

The total average demanded power of all elements corresponding to `idxs`
"""
function total(::Type{MWCapacity}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_sum(table[!, column_name], hc, idxs, yr_idxs, hr_idxs) / total_sum(hc, 1, yr_idxs, hr_idxs)
end
"""
    total(::Type{MWDemanded}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)

The total average demanded power of all elements corresponding to `idxs`
"""
function total(::Type{MWDemanded}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_sum(table[!, column_name], hc, idxs, yr_idxs, hr_idxs) / total_sum(hc, 1, yr_idxs, hr_idxs)
end


function average(::Type{ShortTonsPerMWhGenerated}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_avg(table[!, column_name], table[!, :egen], idxs, yr_idxs, hr_idxs)
end
export average
function average(::Type{DollarsPerMWhServed}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    return weighted_avg(table[!, column_name], table[!, :eserv], idxs, yr_idxs, hr_idxs)
end

"""
    average(::Type{MWDemanded}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)

The per-bus average demanded power.
"""
function average(::Type{MWDemanded}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    return weighted_avg(table[!, column_name], hc, idxs, yr_idxs, hr_idxs)
end

function average(::Type{MWhGeneratedPerMWhCapacity}, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    hc = data[:hours_container]::HoursContainer
    num = weighted_sum(table[!, column_name], table[!, :pcap], hc, idxs, yr_idxs, hr_idxs)
    den = weighted_sum(table.pcap, hc, idxs, yr_idxs, hr_idxs)
    return num / den
end


function Base.maximum(::Type, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    return maximum(col, idxs, yr_idxs, hr_idxs)
end

function Base.maximum(v, idxs, yr_idxs, hr_idxs)
    return maximum(v[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
end

function Base.minimum(::Type, data, res_raw, table, column_name, idxs, yr_idxs, hr_idxs)
    col = table[!, column_name]
    return minimum(col, idxs, yr_idxs, hr_idxs)
end

function Base.minimum(v, idxs, yr_idxs, hr_idxs)
    return minimum(v[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
end

#########################################################################
# Aggregation utilities
#########################################################################

"""
    total_sum(v::Vector, idxs, yr_idxs, hr_idxs)

Compute `sum(v[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function total_sum(v, idxs, yr_idxs, hr_idxs)
    sum(v[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
end

"""
    weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)

Compute the `sum(v1[i,y,h]*v2[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)
    sum(v1[i,y,h]*v2[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
end

"""
    weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)

Compute the `sum(v1[i,y,h]*v2[i,y,h]*v3[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)`
"""
function weighted_sum(v1, v2, v3, idxs, yr_idxs, hr_idxs)
    sum(v1[i,y,h]*v2[i,y,h]*v3[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
end

"""
    weighted_avg(v1, v2, idxs, yr_idxs, hr_idxs)

Compute the `v2`-weighted average of `v1`.  I.e. computed [`weighted_sum`](@ref) divided by the sum of `v2`.
"""
function weighted_avg(v1, v2, idxs, yr_idxs, hr_idxs)
    ws = weighted_sum(v1, v2, idxs, yr_idxs, hr_idxs)
    s = sum(v2[i,y,h] for i in idxs, y in yr_idxs, h in hr_idxs)
    return ws/s
end
    