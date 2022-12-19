"""
    parse_results(config, data, model) -> results

Retrieves results from the model, including:
* Raw results (anything you could possibly need from the model like decision variable values and shadow prices)
* Area/Annual results (?)
* Raw policy results (?)
* Welfare 
"""
function parse_results(config, data, model)

    results = Dict()
    # TODO: any general results gathering
    
    for mod in getmods(config)
        results!(mod, config, data, model, results)
    end

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


function get_result_bus(data, model, n::Symbol)#, bus_idx, year_idx, hour_idx)
    v = map(1:nrow(get_bus_table(data))) do bus_idx
        vcat((round.(value.(model[n][bus_idx, year_idx, :]),digits=2) for year_idx in 1:get_num_years(data))...)
    end
    return v
end
export get_result_bus

function get_result_branch(data, model, n::Symbol)#, bus_idx, year_idx, hour_idx)
    v = map(1:nrow(get_branch_table(data))) do br_idx
        vcat((round.(value.(model[n][br_idx, year_idx, :]),digits=2) for year_idx in 1:get_num_years(data))...)
    end
    return v
end

export get_result_branch
