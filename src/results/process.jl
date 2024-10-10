"""
    process_results!(config::OrderedDict, data::OrderedDict) -> data

Calls [`modify_results!(mod, config, data)`](@ref) for each `Modification` in `config`.  Stores the results into `get_out_path(config, "data_processed.jls")` if `config[:save_data_processed]` is `true` (default).
"""
function process_results!(config::OrderedDict, data::OrderedDict)
    log_header("PROCESSING RESULTS")

    for (name, m) in get_mods(config)
        @info "Modifying results with Modification $name of type $(typeof(m))"
        _try_catch(modify_results!, name, m, config, data)
    end

    # Save the summary table and results formulas
    save_summary_table(config, data)
    save_results_formulas(config, data)

    if get(config, :save_data_processed, true)
        serialize(get_out_path(config,"data_processed.jls"), data)
    end

    return data
end

"""
    process_results!(config; processed=true) -> data

This reads `data` in, then calls [`process_results!(config, data)`](@ref).  
* `processed=false` - reads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - reads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(config; processed=true)
    if processed
        data = read_processed_results(config)
    else
        data = read_parsed_results(config)
    end
    return process_results!(config, data)
end
export process_results!

"""
    process_results!(mod_file::String, out_path::String; processed=true) -> data

Processes the results the [`Modification`](@ref)s found in `mod_file`, a .yml file similar to a `config` file (see [`read_config`](@ref)), only requiring the `mods` field.
* `processed=false` - reads in `data` via [`read_parsed_results`](@ref)
* `processed=true` - reads in `data` via [`read_processed_results`](@ref)
"""
function process_results!(mod_file::String, out_path::String; processed=true)

    # Load the config, and the modifications
    config = read_config(out_path)
    mods = _read_config(mod_file)
    convert_mods!(mods)

    # Merge the mods into config, overwriting anything in config
    merge!(config, mods)

    # Make sure we are using the right out_path.
    config[:out_path] = out_path

    # Now call process_results!
    process_results!(config; processed)
end
export process_results!

function save_summary_table(config, data)
    table = get_table(data, :summary_table)

    st = filter(row->has_table(data, row.table_name) && hasproperty(get_table(data, row.table_name), row.column_name), table)

    for row in eachrow(st)
        row.data_type = eltype(get_table_col(data, row.table_name, row.column_name))
    end

    out_file = get_out_path(config, "summary_table.csv")
    CSV.write(out_file, st)
end


function save_results_formulas(config, data)
    results_formulas = get_results_formulas(data)
    table = make_results_formulas_table(results_formulas)
    out_file = get_out_path(config, "results_formulas.csv")
    CSV.write(out_file, table)
end

"""
    make_results_formulas_table(results_formulas::OrderedDict{Tuple{Symbol, Symbol},ResultsFormula}) -> df


"""
function make_results_formulas_table(results_formulas::OrderedDict{Tuple{Symbol, Symbol},ResultsFormula})
    table = DataFrame(;
        table_name=Symbol[],
        result_name=Symbol[],
        formula=String[],
        unit=Type[],
        description = String[]
    )
    for (k,v) in results_formulas
        (table_name, result_name) = k
        formula = v.formula
        unit = v.unit
        description = v.description
        push!(table, (;table_name, result_name, formula, unit, description))
    end
    return table
end
