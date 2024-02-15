"""
    struct LeftJoinCols <: Modification 

This left joins columns from the `right_table_file` onto the table specified by `left_table_name`. 
This can happen during `modify_raw_data!` or `modify_setup_data!` which is specified in `mod_step` where the two function names are the input options.

### fields
* `left_table_name` - the name of the table within `data` that you want to join to
* `on` - the column names you want to join on
* `right_table_file` - file path for the table you are trying to join onto the left table
* `mod_step` - which modification step you would like to do the join in, options are `modify_raw_data!`, `modify_setup_data!` or `extract_results`
* `matchmissing` - how you would like to treat missing values in the leftjoin, options are from `leftjoin!()`: `error`, `equal`, `notequal` where `notequal` is likely the best option.  This is passed straight into `DataFrames.leftjoin!`
* `replace_missing::OrderedDict` - an OrderedDict mapping col_name => val for each column for which you would like to replace missing values.  For the columns specified, 
"""
struct LeftJoinCols <: Modification 
    name::Symbol
    left_table_name::Symbol
    on::Vector{Symbol}
    right_table_file::AbstractString
    mod_step::AbstractString
    matchmissing::Symbol
    replace_missing::OrderedDict{Symbol, Any}
    right_table::DataFrame

    function LeftJoinCols(;name, left_table_name, on, right_table_file, mod_step, matchmissing, replace_missing=OrderedDict{Symbol, Any}())
        right_table = CSV.read(right_table_file, DataFrame)

        # check that the mod_step is legitimate
        (mod_step != "modify_raw_data!" && mod_step != "modify_setup_data!" && mod_step != "extract_results") && error("The mod step you specified is not an option, please check your spelling. No columns will be added to the $(m.left_table_name) table.")

        return new(name, Symbol(left_table_name), Symbol.(on), right_table_file, mod_step, Symbol(matchmissing), replace_missing, right_table)
    end
end

mod_rank(::Type{LeftJoinCols}) = -1.0
fieldnames_for_yaml(::Type{LeftJoinCols}) = (:left_table_name, :on, :right_table_file, :mod_step, :matchmissing, :replace_missing)

"""
    modify_raw_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_raw_data!(m::LeftJoinCols, config, data)
    if m.mod_step == "modify_raw_data!"
        left_join_cols!(m, config, data)
    end
end

"""
    modify_setup_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_setup_data!(m::LeftJoinCols, config, data)
    if m.mod_step == "modify_setup_data!"
        left_join_cols!(m, config, data)
    end
end

"""
    extract_results(m::LeftJoinCols, config, data) -> 
"""
function extract_results(m::LeftJoinCols, config, data)
    if m.mod_step == "extract_results"
        left_join_cols!(m, config, data)
    end
end

function left_join_cols!(m, config, data)
    left_table = get_table(data, m.left_table_name)

    #check if left table already has the columns that will be joined
    right_names = Symbol.(names(m.right_table))
    left_names = Symbol.(names(left_table))
    joined_cols = right_names[right_names .∉ Ref(m.on)] #columns that will be joined to the left table

    existing_cols = joined_cols[joined_cols .∈ Ref(left_names)] #columns that would be joined but exist already in the left table
    @info "The following columns already exist in the $(m.left_table_name) table and will not be joined by $(m.name)."
    on_new = [m.on ; existing_cols]

    leftjoin!(left_table, m.right_table, on = on_new, matchmissing = m.matchmissing)

    # Clean missing from columns
    for col_name in propertynames(left_table)
        if !any(ismissing, left_table[!, col_name])
            disallowmissing!(left_table, col_name)
        else
            if haskey(m.replace_missing, col_name)
                missing_val = m.replace_missing[col_name]
                replace!(left_table[!, col_name], missing=>missing_val)
                disallowmissing!(left_table, col_name)
            end
        end
    end
end