

struct AddTableCols <: Modification 
    name::Symbol
    table::Symbol
    join_cols::Vector{Symbol}
    cols_file::AbstractString
    mod_step::AbstractString
    cols_table::DataFrame

    function AddTableCols(;name, table, join_cols, cols_file, mod_step)
        cols_table = CSV.read(cols_file, DataFrame)
        return new(name, Symbol(table), Symbol.(join_cols), cols_file, mod_step, cols_table)
    end
end

"""
    modify_raw_data!(m::AddTableCols, config, data) -> 
"""
function modify_raw_data!(m::AddTableCols, config, data)
    # check that the mod_step is legitimate
    (m.mod_step != "modify_raw_data!" && m.mod_step != "modify_setup_data!") && error("The mod step you specified is not an option, please check your spelling. No columns will be added to the $(m.table) table.")

    if m.mod_step == "modify_raw_data!"
        table = get_table(data, m.table)

        leftjoin!(table, m.cols_table, on = m.join_cols)
    end
end

"""
    modify_setup_data!(m::AddTableCols, config, data) -> 
"""
function modify_setup_data!(m::AddTableCols, config, data)
    if m.mod_step == "modify_setup_data!"
        table = get_table(data, m.table)

        leftjoin!(table, m.cols_table, on = m.join_cols)
    end
end