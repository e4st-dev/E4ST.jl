"""
    struct LeftJoinCols <: Modification 

This left joins columns from the `right_table_file` onto the table specified by `left_table_name`. 
This can happen during `modify_raw_data!` or `modify_setup_data!` which is specified in `mod_step` where the two function names are the input options.

### fields
* `left_table_name` - the name of the table within `data` that you want to join to
* `on` - the column names you want to join on
* `right_table_file` - file path for the table you are trying to join onto the left table
* `mod_step` - which modification step you would like to do the join in, options are `modify_raw_data!` or `modify_setup_data!`
* `matchmissing` - how you would like to treat missing values in the leftjoin, options are from `leftjoin!()`: `error`, `equal`, `notequal` where `notequal` is likely the best option
"""
struct LeftJoinCols <: Modification 
    name::Symbol
    left_table_name::Symbol
    on::Vector{Symbol}
    right_table_file::AbstractString
    mod_step::AbstractString
    matchmissing::Symbol
    right_table::DataFrame

    function LeftJoinCols(;name, left_table_name, on, right_table_file, mod_step, matchmissing)
        right_table = CSV.read(right_table_file, DataFrame)
        return new(name, Symbol(left_table_name), Symbol.(on), right_table_file, mod_step, Symbol(matchmissing), right_table)
    end
end

mod_rank(::Type{LeftJoinCols}) = -1.0
fieldnames_for_yaml(::Type{LeftJoinCols}) = (:left_table_name, :on, :right_table_file, :mod_step, :matchmissing)

"""
    modify_raw_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_raw_data!(m::LeftJoinCols, config, data)
    # check that the mod_step is legitimate
    (m.mod_step != "modify_raw_data!" && m.mod_step != "modify_setup_data!") && error("The mod step you specified is not an option, please check your spelling. No columns will be added to the $(m.left_table_name) table.")

    if m.mod_step == "modify_raw_data!"
        left_table = get_table(data, m.left_table_name)

        leftjoin!(left_table, m.right_table, on = m.on, matchmissing = m.matchmissing)
    end
end

"""
    modify_setup_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_setup_data!(m::LeftJoinCols, config, data)
    if m.mod_step == "modify_setup_data!"
        left_table = get_table(data, m.left_table_name)

        leftjoin!(left_table, m.right_table, on = m.on ,matchmissing = m.matchmissing)
    end
end