"""
    parse_results(config, data, model) -> results

Retrieves results from the model, including:
* Raw results (anything you could possibly need from the model like decision variable values and shadow prices)
* Area/Annual results (?)
* Raw policy results (?)
* Welfare 
"""
function parse_results!(config, data, model, all_results)

    results = Dict()
    # TODO: any general results gathering
    
    for mod in getmods(config)
        results!(mod, config, data, model, results)
    end

    push!(all_results, results)

    return nothing
end

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
    return table_rows(get_gen_table(data), idxs)
end

export get_gen_array_idxs
