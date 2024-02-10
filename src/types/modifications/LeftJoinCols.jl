"""
    struct LeftJoinCols <: Modification 

This left joins columns from the `right_table_file` onto the table specified by `left_table_name`. 
This can happen during `modify_raw_data!` or `modify_setup_data!` which is specified in `mod_step` where the two function names are the input options.
"""
struct LeftJoinCols <: Modification 
    name::Symbol
    left_table_name::Symbol
    on::Vector{Symbol}
    right_table_file::AbstractString
    mod_step::AbstractString
    right_table::DataFrame

    function LeftJoinCols(;name, left_table_name, on, right_table_file, mod_step)
        right_table = CSV.read(right_table_file, DataFrame)
        return new(name, Symbol(left_table_name), Symbol.(on), right_table_file, mod_step, right_table)
    end
end

mod_rank(::Type{LeftJoinCols}) = -1.0
fieldnames_for_yaml(::Type{LeftJoinCols}) = (:left_table_name, :on, :right_table_file, :mod_step)

"""
    modify_raw_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_raw_data!(m::LeftJoinCols, config, data)
    # check that the mod_step is legitimate
    (m.mod_step != "modify_raw_data!" && m.mod_step != "modify_setup_data!") && error("The mod step you specified is not an option, please check your spelling. No columns will be added to the $(m.left_table_name) table.")

    if m.mod_step == "modify_raw_data!"
        left_table = get_table(data, m.left_table_name)

        leftjoin!(left_table, m.right_table, on = m.on)
    end
end

"""
    modify_setup_data!(m::LeftJoinCols, config, data) -> 
"""
function modify_setup_data!(m::LeftJoinCols, config, data)
    if m.mod_step == "modify_setup_data!"
        left_table = get_table(data, m.left_table_name)

        leftjoin!(left_table, m.right_table, on = m.on)
    end
end