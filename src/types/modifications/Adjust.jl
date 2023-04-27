struct Operation end
function Operation(s::AbstractString)
    s == "add" && return s
    s == "scale" && return s
    s == "set" && return s
    error("Operation \"$s\" invalid, please choose from add, scale, and set")
end
    

@doc """
    summarize_table(::Val{:adjust_hourly})

$(table2markdown(summarize_table(Val(:adjust_hourly))))
"""
function summarize_table(::Val{:adjust_hourly})
    df = TableSummary()
    push!(df, 
        (:table_name, AbstractString, NA, true, "The name of the table to adjust.  Leave blank if this adjustment is intended for a variable in `data`"),
        (:variable_name, AbstractString, NA, true, "The name of the variable/column to adjust"),
        (:operation, Operation, NA, true, "The operation to perform.  Could be add, scale, or set."),
        (:filter_, String, NA, true, "There can be multiple filter conditions - `filter1`, `filter2`, etc.  It denotes a comparison used for selecting the table rows to apply the adjustment to.  See `parse_comparison` for examples"),
        (:year, String, Year, true, "The year to adjust, expressed as a year string prepended with a \"y\".  I.e. \"y2022\".  Leave blank to adjust all years"),
        (:status, Bool, NA, false, "Whether or not to use this adjustment"),
        (:h_, Float64, Ratio, true, "Value to adjust by for each hour.  Include a column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end

@doc """
    summarize_table(::Val{:adjust_yearly})

$(table2markdown(summarize_table(Val(:adjust_yearly))))
"""
function summarize_table(::Val{:adjust_yearly})
    df = TableSummary()
    push!(df, 
        (:table_name, AbstractString, NA, true, "The name of the table to adjust.  Leave blank if this adjustment is intended for a variable in `data`"),
        (:variable_name, AbstractString, NA, true, "The name of the variable/column to adjust"),
        (:operation, Operation, NA, true, "The operation to perform.  Could be add, scale, or set."),
        (:filter_, String, NA, true, "There can be multiple filter conditions - `filter1`, `filter2`, etc.  It denotes a comparison used for selecting the table rows to apply the adjustment to.  See `parse_comparison` for examples"),
        (:status, Bool, NA, false, "Whether or not to use this adjustment"),
        (:y_, Float64, Ratio, true, "Value to adjust by for each year.  Include a column for each year in the hours table.  I.e. `:y2020`, `:y2030`, etc"),
    )
    return df
end

@doc """
    summarize_table(::Val{:adjust_by_age})

$(table2markdown(summarize_table(Val(:adjust_by_age))))
"""
function summarize_table(::Val{:adjust_by_age})
    df = TableSummary()
    push!(df, 
        (:table_name, AbstractString, NA, true, "The name of the table to adjust.  Leave blank if this adjustment is intended for a variable in `data`"),
        (:variable_name, AbstractString, NA, true, "The name of the variable/column to adjust"),
        (:operation, Operation, NA, true, "The operation to perform.  Could be add, scale, or set."),
        (:filter_, String, NA, true, "There can be multiple filter conditions - `filter1`, `filter2`, etc.  It denotes a comparison used for selecting the table rows to apply the adjustment to.  See `parse_comparison` for examples"),
        (:status, Bool, NA, false, "Whether or not to use this adjustment"),
        (:age_type, String, NA, true, "The type of age specified, can be `exact`, `after`, or `trigger`.  If `exact`, then adjustment is applied only when the age in question is between `[age, age+1)`.  If `trigger`, then adjustment is applied for the first simulation year for which the age has been exceeded.  If `after`, then adjustment is applied on [age, Inf)"),
        (:age, Float64, NumYears, true, "The age at which to apply this adjustment.  Applies depending on `age_type`"),
        (:value, Float64, NA, true, "Value to adjust by."),
    )
    return df
end



"""
    Adjust{T} <: Modification

This [`Modification`](@ref) creates a way to adjust table values or data parameters.  See the following subtypes:
* [`AdjustHourly`](@ref)
* [`AdjustYearly`](@ref)
* [`AdjustByAge`](@ref)
"""
Base.@kwdef struct Adjust{T} <: Modification
    name::Symbol
    file::String
end
"""
    AdjustHourly(;file, name)

Adjusts tables and parameters by hour.  Stores the table stored in `file` into `data[name]`.

$(table2markdown(summarize_table(Val(:adjust_hourly))))
"""
const AdjustHourly = Adjust{:adjust_hourly}

"""
    AdjustYearly(;file, name)

Adjusts tables and parameters by year.  Stores the table stored in `file` into `data[name]`.

$(table2markdown(summarize_table(Val(:adjust_yearly))))
"""
const AdjustYearly = Adjust{:adjust_yearly}

"""
    AdjustByAge(;file, name)

Adjusts tables and parameters by year.  Stores the table stored in `file` into `data[name]`.

$(table2markdown(summarize_table(Val(:adjust_by_age))))
"""
const AdjustByAge = Adjust{:adjust_by_age}
export Adjust, AdjustHourly, AdjustYearly, AdjustByAge



function modify_raw_data!(mod::Adjust{T}, config, data) where T
    file = mod.file
    name = mod.name
    table = read_table(data, file, T)
    data[name] = table
    return nothing
end

function modify_setup_data!(mod::Adjust{T}, config, data) where T
    table = get_table(data, mod.name)
    for row in eachrow(table)
        adjust!(mod, config, data, row)
    end
end

function adjust!(mod::Adjust{:adjust_yearly}, config, data, row)
    adjust_yearly!(config, data, row)
end

function adjust!(mod::Adjust{:adjust_hourly}, config, data, row)
    adjust_hourly!(config, data, row)
end

function adjust!(mod::Adjust{:adjust_by_age}, config, data, row)
    adjust_by_age!(config, data, row)
end

"""
    adjust_hourly!(config, data, row)

Apply an hourly adjustment given `row` from the `adjust_hourly` table.
"""
function adjust_hourly!(config, data, row)
    table_name = row.table_name::AbstractString
    variable_name = row.variable_name::AbstractString
    oper = row.operation::AbstractString

    # Get the year to perform the adjustment on
    all_years = get_years(data)
    nyr = get_num_years(data)
    if isempty(row.year)
        yr_idx = (:)
    elseif row.year ∈ all_years
        yr_idx = findfirst(==(row.year), all_years)
    else
        return
    end

    if isempty(table_name)
        key = Symbol(variable_name)
        vals = [row["h$h"] for h in 1:get_num_hours(data)]
        c = get(data, key, ByNothing(0.0))
        data[key] = operate_hourly(oper, c, vals, yr_idx, nyr)
        return
    end

    # Get the filtered table with which to perform the adjustment
    pairs = parse_comparisons(row)
    table = get_table(data, table_name, pairs)
    isempty(table) && return
    hasproperty(table, variable_name) || error("Table $table_name has no column $variable_name to adjust in `adjust_hourly!`")


    # Perform the adjustment on each row of the table
    vals = [row["h$h"] for h in 1:get_num_hours(data)]

    # Make sure the appropriate column is a Vector{Container}
    _to_container!(table, variable_name)
    for r in eachrow(table)
        r[variable_name] = operate_hourly(oper, r[variable_name], vals, yr_idx, nyr)
    end
    return
end

"""
    adjust_yearly!(config, data, row)

Apply an hourly adjustment given `row` from the `adjust_hourly` table.
"""
function adjust_yearly!(config, data, row)
    # TODO: make warning if you are trying to modify the same column of the same table hourly and yearly.
    table_name = row.table_name::AbstractString
    variable_name = row.variable_name::AbstractString
    oper = row.operation::AbstractString
    if isempty(table_name)
        key = Symbol(variable_name)
        vals = [row[y] for y in get_years(data)]
        c = get(data, key, ByNothing(0.0))
        data[key] = operate_yearly(oper, c, vals)
        return
    end

    # Get the filtered table with which to perform the adjustment
    pairs = parse_comparisons(row)
    table = get_table(data, table_name, pairs)
    isempty(table) && return
    hasproperty(table, variable_name) || error("Table $table_name has no column $variable_name to adjust in `adjust_hourly!`")

    # Perform the adjustment on each row of the table
    vals = [row[y] for y in get_years(data)]

    # Make sure the appropriate column is a Vector{Container}
    _to_container!(table, variable_name) 

    for r in eachrow(table)
        r[variable_name] = operate_yearly(oper, r[variable_name], vals)
    end
    return
end

"""
    adjust_by_age!(config, data, row)

Apply an adjustment based on given `row` from the `adjust_by_age` table.
"""
function adjust_by_age!(config, data, row)
    table_name = row.table_name::AbstractString
    variable_name = row.variable_name::AbstractString
    oper = row.operation::AbstractString
    nyr = get_num_years(data)

    if isempty(table_name)
        @warn "adjust_by_age table requires non-empty table_name to adjust by age"
        return
    end

    # Get the filtered table with which to perform the adjustment
    pairs = parse_comparisons(row)
    table = get_table(data, table_name, pairs)
    isempty(table) && return
    hasproperty(table, variable_name) || error("Table $table_name has no column $variable_name to adjust in `adjust_hourly!`")

    # Perform the adjustment on each row of the table
    val = row.value
    age = row.age
    age_type = row.age_type

    # Make sure the appropriate column is a Vector{Container}
    _to_container!(table, variable_name)

    last_sim_year = get(config, :year_previous_sim, config[:year_gen_data])

    for r in eachrow(table)
        ages_container = r.age::ByYear
        ages = ages_container.v

        if age_type == "trigger"
            # If the ages of the row are before the triggering age, don't apply adjustment
            last(ages) < age && continue

            # Check to see if the trigger has already been triggered
            age_at_last_sim_year = diff_years(last_sim_year, r.year_on)
            age_at_last_sim_year > age && continue

            yr_idx = findfirst(>=(age), ages)
            @assert yr_idx !== nothing "unable to find an age to trigger adjustment, there should be a trigger year...  Something is wrong with this code/logic"
        elseif age_type == "exact"
            yr_idx = findfirst(a->(age <= a < age+1), ages)
            yr_idx === nothing && return
        elseif age_type == "after"
            yr_idx = findall(a->(age <= a), ages)
        else
            error("`age_type` must be `trigger`, `after` or `exact` in adjust_by_age table")
        end

        for _yr_idx in yr_idx
            r[variable_name] = operate_yearly(oper, r[variable_name], val, _yr_idx, nyr)
        end
    end
    return
end