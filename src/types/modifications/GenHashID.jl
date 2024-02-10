"""
    struct GenHashID <: Modification

This adds a unique hash identifier to every new build generator. It assumes that the gen table already has the column listed as `hash_col_name`. 
The hash identifier can be used to do generator specific modifications, policies, and results processing. 
The hash is converted to a String instead of a UInt because CSVs won't save it or read it in as a UInt64. 
The hash can be converted back into a UInt64 using the command `parse(UInt64, hash_to_convert, base = 16)`
"""
Base.@kwdef struct GenHashID <: Modification
    name::Symbol
    hash_col_name::AbstractString
end

"""
    modify_raw_data!(m::GenHashID, config, data) -> 

    Create the hash column in the build_gen table so that the build_gen can get set up correctly 
"""
function modify_raw_data!(m::GenHashID, config, data)
    build_gen = get_table(data, :build_gen)
    gen = get_table(data, :gen)

    (m.hash_col_name in names(gen)) || error("The hash column name given isn't in the gen table and the simulation will error on setup.")

    build_gen[:, Symbol(m.hash_col_name)] .= ""
end

"""
    modify_setup_data!(m::GenHashID) -> 
"""
function modify_setup_data!(m::GenHashID, config, data)
    gen = get_table(data, :gen)
    for g in eachrow(gen)
        (g[Symbol(m.hash_col_name)] == "") && (g[Symbol(m.hash_col_name)] = string.(hash(g[[:bus_idx, :gentype, :build_id, :year_on]]), base = 16))
    end
end