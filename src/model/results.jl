"""
    parse_results(config, data, model) -> results

Retrieves results from the model, including:
* Raw results (anything you could possibly need from the model like decision variable values and shadow prices)
* Area/Annual results (?)
* Raw policy results (?)
* Welfare 
"""
function process_results(config, data, results_raw)

    results_user = OrderedDict{Symbol, Any}()
    
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

"""
    sum_yearly_and_total(ar) -> (yearly, total)

Sums up 3D array `ar` across hours, then across years.
"""
function sum_yearly_and_total(ar::AbstractArray{<:Real, 3})
    ni, ny, nh = size(ar)
    yearly = [sum(ar[i,y,h] for h in 1:nh) for i in 1:ni, y in 1:ny]
    total = [sum(yearly[i,y] for y in 1:ny) for i in 1:ni]
    return yearly, total
end
export sum_yearly_and_total


"""
    weight_hourly!(data, ar)

Multiplies (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function weight_hourly!(data, ar)
    weights = get_hour_weights(data)
    for (hr_idx, hr_wgt) in enumerate(weights)
        v = view(ar, :, :, hr_idx)
        v .*= hr_wgt
    end
    return
end
export weight_hourly!

"""
    weight_hourly(data, ar)

Multiplies each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function weight_hourly(data, ar::AbstractArray{<:Any, I}) where I
    w = get_hour_weights(data)
    return [ar[ci] * w[ci[I]] for ci in CartesianIndices(ar)]
end
export weight_hourly



"""
    unweight_hourly!(data, ar)

Divides (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function unweight_hourly!(data, ar)
    weights = get_hour_weights(data)
    for (hr_idx, hr_wgt) in enumerate(weights)
        v = view(ar, :, :, hr_idx)
        inv_hr_weight = 1/hr_wgt
        v .*= inv_hr_weight
    end
    return
end
export unweight_hourly!

"""
    results_egen!(config, data, model, results)
    
Adds energy generation to results.  That includes:
* `results[:egen_gen]` = (ngen × nyr × nhr) matrix of energy generated, in MWh
"""
function results_egen!(config, data, model, results)
    egen_gen_hourly = results[:raw][:egen_gen]::Array{Float64,3}
    egen_gen_yearly, egen_gen_total = sum_yearly_and_total(egen_gen_hourly)
    results[:egen_gen_hourly] = egen_gen_hourly
    results[:egen_gen_yearly] = egen_gen_yearly
    results[:egen_gen_total] = egen_gen_total

    # Compute egen_bus_hourly from pgen_bus and weighting hourly
    pgen_bus_hourly = results[:raw][:pgen_bus]::Array{Float64,3}
    egen_bus_hourly = weight_hourly(data, egen_bus_hourly)

    egen_bus_yearly, egen_bus_total = sum_yearly_and_total(egen_bus_hourly)
    results[:egen_bus_hourly] = egen_bus_hourly
    results[:egen_bus_yearly] = egen_bus_yearly
    results[:egen_bus_total] = egen_bus_total
    return results
end
export results_egen!

@doc raw"""
    results_lmp!(config, data, model, results)

Adds the locational marginal price of electricity (\$/MWh) for each bus at each year during each hour.  That includes:
* `results[:lmp_hourly]` = (nbus × nyr × nhr) array of locational marginal prices, in (\$/MWh)
* `results[:lmp_yearly]` = (nbus × nyr) matrix of locational marginal prices, in (\$/MWh)
* `results[:lmp_total]`  = (nbus) vector of locational marginal prices, in (\$/MWh)
* `results[:lmp_table]` = DataFrame with a row for each bus, and a "total" column as well as columns for each year, (i.e. `"y2020"`), and for each year-hour combo (i.e. `"y2020_h1"`)
* Saves `lmp_table` to `out_path(config, "lmp.csv")`
"""
function results_lmp!(config, data, model, results)
    # Get the shadow price of the average power flow constraint
    lmp_hourly = results[:raw][:cons_pflow]::Array{Float64,3}

    # To convert from price of each marginal average MW of power, we need to divide by the hour weights
    unweight_hourly!(data, lmp_hourly)

    
    egen_bus_hourly = results[:egen_bus_hourly]::Array{Float64,3}
    egen_bus_yearly = results[:egen_bus_yearly]::Array{Float64,2}
    egen_bus_total = results[:egen_bus_total]::Vector{Float64}

    # Compute total consumer payments from hourly LMP's and energy generated
    consumer_payments_hourly = lmp_hourly .* egen_bus_hourly
    consumer_payments_yearly, consumer_payments_total = sum_yearly_and_total(consumer_payments_hourly)

    # Compute average yearly and total LMP's
    lmp_yearly = consumer_payments_yearly ./ egen_bus_yearly
    lmp_total = consumer_payments_total ./ egen_bus_total

    results[:lmp_hourly] = lmp_hourly
    results[:lmp_yearly] = lmp_yearly
    results[:lmp_total] = lmp_total


    # years = get_years(data)
    # lmp_table = DataFrame("total"=>lmp_total)
    # for (yr_idx, y) in enumerate(years)
    #     lmp_table[!, y] = lmp_yearly[:, yr_idx]
    # end
    # for hr_idx in 1:get_num_hours(data), yr_idx in 1:get_num_years(data)
    #     lmp_table[!, "$(years[yr_idx])_h$hr_idx"] = lmp_hourly[:,yr_idx, hr_idx] 
    # end
    # results[:lmp_hourly] = lmp_hourly
    # results[:lmp_table] = lmp_table
    # # CSV.write(joinpath(config[:out_path], "lmp.csv"), lmp_table)
    return results
end
export results_lmp!

"""
    process!(config, results)

Process the `results` according to the instructions in `config`
"""
function process!(config, results)
    # TODO: Implement this
    return nothing
end

function print_binding_cons(model)
    df = DataFrame(:constraint=>get_all_cons(model))
    df.base_name = map(df.constraint) do cons
        first(split(name(cons),'['))
    end

    df.is_binding = map(df.constraint) do cons
        abs(dual(cons)) <= 1e-6
    end
    df.lhs = map(value, df.constraint)
    df.rhs = map(normalized_rhs, df.constraint)

    return df

    gdf = groupby(df, :base_name)
    return sort!(combine(gdf, :is_binding=>count=>:num_binding, :is_binding=>length=>:num_cons), :base_name)
end
export print_binding_cons

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
