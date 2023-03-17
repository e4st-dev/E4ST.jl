
"""
    struct YearlyTable <: Modification

    YearlyTable(;name, table_name, groupby=Symbol[], group_hours_by=Symbol[])

This modification creates an agregated table for each year in the simulation.  It includes all of the relevant columns from table `get_table(data, table_name)`, aggregated with [`aggregate_result`](@ref), grouped by column names in `groupby`.  The hours are grouped by columns from the `group_hours_by` field.

# Fields:
* `name` - the name of the Modification, (don't need to specify this field in config file).  The outputed table will be saved to [`get_out_path(config, "<name>_<year>.csv")`](@ref)
* `table_name` - the name of the table to export.  I.e. `gen`, `bus`, or `branch`
* `groupby = Symbol[]` - the name(s) of the columns of the table specified by `table_name` to group by. I.e. `state`, `country`, `genfuel`, `gentype`, etc.  Leave blank to group the whole table together.  To prevent any grouping and show every row, give a `:`
* `group_hours_by = Symbol[]` - the name(s) of the columns of the hours table to group by.  I.e. `season`.  Leave blank to group the whole table together. To prevent any grouping and show every hour, give a `:`
"""
struct YearlyTable{G,H} <: Modification
    name::Symbol
    table_name::Symbol
    groupby::G
    group_hours_by::H
end
export YearlyTable
function YearlyTable(;name, table_name, groupby = Symbol[], group_hours_by = Symbol[])
    return YearlyTable(Symbol(name), Symbol(table_name), groupby, group_hours_by)
end

"""
    modify_results!(mod::YearlyTable, config, data) -> nothing


"""
function modify_results!(mod::YearlyTable, config, data)

    # Retrieve the table and group it
    table = get_table(data, mod.table_name)
    gdf = groupby(table, mod.groupby)
    idx_sets = [getfield(sdf, :rows) for sdf in gdf]

    # Retrieve the hours table and group it
    hours_table = get_table(data, :hours)
    gdf_hours = groupby(hours_table, mod.group_hours_by)
    hour_idx_sets = [getfield(sdf, :rows) for sdf in gdf_hours]

    for (yr_idx, yr) in enumerate(get_years(data))
        out_file = "$(mod.name)_$yr.csv"
        # TODO: some very fancy combine operation, or some custom for loop iteration

        for (i, idxs) in enumerate(idx_sets)
            for (i, hr_idxs) in enumerate(hour_idx_sets)


            end
        end


        
        
    end
end
export modify_results!

