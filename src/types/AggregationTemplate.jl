struct AggregationTemplate <: Modification
    file::String
    name::Symbol
    table::DataFrame
end
function AggregationTemplate(;file, name)
    table = load_table(file)
    force_table_types!(table, name, 
        :operation=>Aggregation,
        :table_name=>Symbol,
        :column_name=>Symbol,
        :filter_years=>String,
        :filter_hours=>String,
    )
    for i in 1:1000
        col_name = "filter$i"
        hasproperty(table, col_name) || continue
        force_table_types!(table, name, col_name=>String)
    end


    return AggregationTemplate(file, name, table)
end
export AggregationTemplate


fieldnames_for_yaml(::Type{AggregationTemplate}) = (:file,)
function modify_results!(mod::AggregationTemplate, config, data, res_raw, res_user)
    table = mod.table
    table.value = map(eachrow(table)) do row
        op = row.operation
        table_name = row.table_name
        col_name = row.column_name
        idxs = parse_comparisons(row)
        yr_idxs = parse_year_idxs(row.filter_years)
        hr_idxs = parse_hour_idxs(row.filter_hours)
        return aggregate_result(op, data, res_raw, table_name, col_name, idxs, yr_idxs, hr_idxs)
    end    
    CSV.write(out_path(config, string(mod.name, ".csv")), table)
    res_user[mod.name] = table
    return
end

struct Aggregation end
function Aggregation(s::AbstractString)
    s == "total" && return total
    s == "average" && return average
    s == "maximum" && return maximum
    s == "minimum" && return minimum
    error("Cannot aggregate with operation $s")
end