"""
    struct WelfareTable <: Modification

Outputs a table with a breakdown of each of the terms going into welfare, for each year.

Arguments/keyword arguments:
* name::Symbol
* groupby - empty by default to not group by anything.  Could choose to group by state, county, etc.
"""
struct WelfareTable{G,H} <: Modification
    name::Symbol
    groupby::G
    group_hours_by::H
end
export WelfareTable
function WelfareTable(;name, groupby = Symbol[], group_hours_by = Symbol[])
    if groupby == ":" || groupby == "Colon()"
        groupby = (:)
    end
    return WelfareTable(Symbol(name), groupby, group_hours_by)
end

mod_rank(::Type{<:WelfareTable}) = 5.0

"""
    modify_results!(mod::WelfareTable, config, data) -> nothing
"""
function modify_results!(mod::WelfareTable, config, data)

    welfare = get_welfare(data)
    bus = get_table(data, :bus)

    # Do a check to make sure everything in the welfare dict has units of Dollars
    
    # Calculate all the different index filters to use for this grouping
    gdf = groupby(bus, mod.groupby)
    col_names = keys(first(keys(gdf)))
    col_types = typeof.(values(first(keys(gdf))))
    table_filters = collect.(pairs.(keys(gdf)))

    # Calculate the hours filters to use for this grouping
    hours_table = get_table(data, :hours)
    gdf_hours = groupby(hours_table, mod.group_hours_by)
    hour_col_names = keys(first(keys(gdf_hours)))
    hour_col_types = typeof.(values(first(keys(gdf_hours))))
    hour_idx_filters = collect.(pairs.(keys(gdf_hours)))
    hour_idx_sets = [getfield(sdf, :rows) for sdf in gdf_hours]

    df = DataFrame(
        :welfare_type=>Symbol[],
        :table_name=>Symbol[],
        :result_name=>String[],
        :year=>String[],
        (col_names[i]=>col_types[i][] for i in eachindex(col_names))...,
        (hour_col_names[i]=>hour_col_types[i][] for i in eachindex(hour_col_names))...,
        :value=>Float64[],
    )

    filter_results_formulas!(data)

    out_name = "$(mod.name)"
    out_file = get_out_path(config, "$out_name.csv")

    # Loop over each year in data
    for (welfare_type, table_names) in welfare,
            (table_name, result_names) in table_names
        for filts in table_filters
            row_idxs = get_table_row_idxs(data, table_name, filts)
            for (yr_idx, yr) in enumerate(get_years(data)),
                    (hr_group_idx, hr_filts) in enumerate(hour_idx_filters),
                    (result_name, result_sign) in result_names
                hr_idxs = hour_idx_sets[hr_group_idx]
                res = compute_result(data, table_name, result_name, row_idxs, yr_idx, hr_idxs)
                value = res |> result_sign
                result_name_string = result_sign === (-) ? string(-, result_name) : string(result_name)
                row = Dict(
                    :welfare_type=>welfare_type,
                    :table_name=>table_name,
                    :result_name=>result_name_string,
                    :year=>yr,
                    (col_names[i]=>filts[i][2] for i in eachindex(col_names))...,
                    (hour_col_names[i]=>hr_filts[i][2] for i in eachindex(hour_col_names))...,
                    :value=>value
                )
                push!(df, row)
            end
        end
    end

    CSV.write(out_file, df)
end
export modify_results!
