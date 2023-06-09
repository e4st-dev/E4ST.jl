
"""
    struct YearlyTable <: Modification

    YearlyTable(;name, table_name, groupby=Symbol[], group_hours_by=Symbol[])

This modification creates an agregated table for each year in the simulation.  It includes all of the result formulas listed in [`get_results_formulas(data, table_name)`](@ref), grouped by column names in `groupby`.  The hours are grouped by columns from the `group_hours_by` field.

# Fields:
* `name` - the name of the Modification, (don't need to specify this field in config file).  The outputed table will be saved to [`get_out_path(config, "<name>_<year>.csv")`](@ref)
* `table_name` - the name of the table to export.  I.e. `gen`, `bus`, or `branch`
* `groupby = Symbol[]` - the name(s) of the columns of the table specified by `table_name` to group by. I.e. `state`, `country`, `genfuel`, `gentype`, etc.  Leave blank to group the whole table together into a single row.  To prevent any grouping and show every row, give a `:`
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
    if groupby == ":"
        groupby = (:)
    end
    return YearlyTable(Symbol(name), Symbol(table_name), groupby, group_hours_by)
end

mod_rank(::Type{<:YearlyTable}) = 0.0

"""
    modify_results!(mod::YearlyTable, config, data) -> nothing
"""
function modify_results!(mod::YearlyTable, config, data)
    @info "Starting result processing for YearlyTable $(mod.name)"

    # Retrieve the table and group it
    table_name = mod.table_name
    table = get_table(data, table_name)
    gdf = groupby(table, mod.groupby)
    idx_sets = [getfield(sdf, :rows) for sdf in gdf]

    filter_results_formulas!(data)

    # Retrieve the hours table and group it
    hours_table = get_table(data, :hours)
    gdf_hours = groupby(hours_table, mod.group_hours_by)
    hour_idx_sets = [getfield(sdf, :rows) for sdf in gdf_hours]

    # Compute the columns of the yearly_table.
    new_cols = get_new_cols_for_yearly_table(data, table_name, gdf, idx_sets, hour_idx_sets)
    results_formulas = get_results_formulas(data, table_name)

    # Loop over each year in data
    for (yr_idx, yr) in enumerate(get_years(data))
        out_name = "$(mod.name)_$yr"
        out_file = get_out_path(config, "$out_name.csv")

        # Compose the table
        df = DataFrame()
        for (col_name, col_fn) in new_cols
            df[!, col_name] = [col_fn(group_idx, yr_idx, hr_group_idx)
                for group_idx in 1:length(idx_sets) for hr_group_idx in 1:length(hour_idx_sets)
            ]
        end

        for (_, result_name) in keys(results_formulas)
            compute_results!(df, data, table_name, result_name, idx_sets, yr_idx, hour_idx_sets)
        end

        # Add columns for hours in group_hours_by
        hours_cols = add_hours_columns!(mod, df, gdf, gdf_hours) 

        # Reorder columns based on the grouping columns
        mod.groupby == (:) || select!(df, mod.groupby, Not(mod.groupby))

        # compose the set of grouping columns by which to sort by.
        grouping_cols = Symbol[]
        mod.groupby == (:) || append!(grouping_cols, tosymvec(mod.groupby))
        append!(grouping_cols, hours_cols)

        # Sort the dataframe
        isempty(grouping_cols) || sort!(df, grouping_cols)
        
        add_result!(data, Symbol(out_name), df)
        CSV.write(out_file, df)

    end
    @info "Done with result processing for YearlyTable $(mod.name)"
end
export modify_results!


"""
    get_new_cols_for_yearly_table(data, table_name, gdf, group_idx_sets, hour_idx_sets) -> new_cols

Computes the columns to add to the YearlyTable.  Returns `new_cols`, a dictionary mapping `col_name::String` to `col_fn::Function`.
* `col_name` is either the original table's column name, or appended with `total` or `average`.
* `col_fn` is a function mapping (idxs, hr_idxs, yr_idxs) to the aggregated result.
"""
function get_new_cols_for_yearly_table(data, table_name, gdf, group_idx_sets, hour_idx_sets)
    table = get_table(data, table_name)

    # Begin composing the new_cols OrderedDict by looping through each column in the table
    new_cols = OrderedDict{Symbol, Function}()
    for name in propertynames(table)

        # Pull out the unit and type of the column
        unit = get_table_col_unit(data, table_name, name)
        type = get_table_col_type(data, table_name, name)

        # Check to see if the column is numeric
        if type <: Float64 || type <: Container || type <: AbstractArray{Float64}
        else
            # If not numeric check to see if each group has the same value for this column.
            if all(allequal(sdf[!, name]) for sdf in gdf)
                push!(new_cols,
                    name => (group_idx, yr_idx, hr_group_idx) -> gdf[group_idx][1, name]
                )
            end
        end
    end
    return new_cols
end

"""
    add_hours_columns!(mod::YearlyTable, df, gdf, gdf_hours) -> cols::Vector{Symbol}

Add hours columns
"""
function add_hours_columns!(mod::YearlyTable{<:Any, Colon}, df, gdf, gdf_hours)
    new_cols = [:hour_idx]
    df[!, :hour_idx] = repeat(collect(getfield(sdf, :rows)[1] for sdf in gdf_hours), outer=length(gdf))
    for col in propertynames(gdf_hours)
        df[!, col] = repeat(collect(sdf[1, col] for sdf in gdf_hours), outer=length(gdf))
        push!(new_cols, col)
    end
    select!(df, new_cols, Not(new_cols))
    return new_cols
end
function add_hours_columns!(mod::YearlyTable{<:Any, <:Any}, df, gdf, gdf_hours)
    df[!, mod.group_hours_by] = repeat([first(k) for k in keys(gdf_hours)], outer=length(gdf))
    select!(df, mod.group_hours_by, Not(mod.group_hours_by))
    return Symbol(mod.group_hours_by)
end
function add_hours_columns!(mod::YearlyTable{<:Any, <:AbstractVector}, df, gdf, gdf_hours)
    isempty(mod.group_hours_by) && return Symbol[]
    new_cols = Symbol.(mod.group_hours_by)
    for (i, col) in enumerate(mod.group_hours_by)
        df[!, col] = repeat([k[i] for k in keys(gdf_hours)], outer=length(gdf))
    end
    df[!, :hours] = repeat([sum(sdf.hours) for sdf in gdf_hours], outer=length(gdf))
    push!(new_cols, :hours)
    select!(df, new_cols, Not(new_cols))
    return new_cols
end
export add_hours_columns!

@inline function allequal(x)
    length(x) < 2 && return true
    e1 = x[1]
    i = 2
    @inbounds for i=2:length(x)
        x[i] == e1 || x[i] === e1 || return false
    end
    return true
end

"""
    tosymvec(x) -> v::Vector{Symbol}
"""
function tosymvec(v::Vector{Symbol})
    v
end
function tosymvec(v::Vector)
    Symbol.(v)
end
function tosymvec(v)
    [Symbol(v)]
end

