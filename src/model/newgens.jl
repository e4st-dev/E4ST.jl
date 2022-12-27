# Create new generators 

"""
    setup_new_gens!(config, data)

Creates new generators with zero capacity. Location is determined by build___ columns in bus table. 
"""
function setup_new_gens!(config, data)

    make_newgen_table!(config, data)
    
    characterize_newgen!(config, data)

    append_newgen_table!(data)
end


"""
    make_newgen_table!(config, data) -> 
    
Create newgen table with zero cap gens at buildable buses. Structure mirrors the existing gen table.
"""
function make_newgen_table!(config, data)
    #create table with same columns as gen
    gen_col_names = names(data[:gen])
    newgen = DataFrame([name => [] for name in gen_col_names])
    force_table_types!(newgen, :newgen, summarize_gen_table())

    #for each bus, add rows to newgen for each type of buildable gen
    build_gentypes = get_build_gentypes(config, data)
    bus = data[:bus]
    for gentype in build_gentypes
        colname = Symbol("build"*gentype)
        gentype_bus_idxs = findall(1, bus[colname])
        genfuel = get_genfuel(data,gentype)
        for bus_idx in gentype_bus_idxs
            newgen_row = make_newgen_row(data, newgen)
            newgen_row[:bus_idx] = bus_idx
            newgen_row[:gentype] = gentype
            newgen_row[:genfuel] = genfuel
            push!(data[:newgen], newgen_row)
        end
    end
    
end

"""
    characterize_newgen!(config, data) -> 

Assigns new generator characteristics (fuel cost, emis rate, etc) to gens in the newgen table. 
"""
function characterize_newgen!(config, data)
    
end


"""
    append_newgen_table!(data) -> 

Appends the newgen table to the gen table. 
"""
function append_newgen_table!(data)
    
end


"""
    get_build_gentypes(config, data) ->
    
Returns a list of the types of generation in build columns in the bus table. 
"""
function get_build_gentypes(config, data)
    
end

"""
    get_genfuel(data, gentype) -> 

Returns the corresponding genfuel for the given gentype. 
"""
function get_genfuel(data, gentype)
    
end

"""
    make_newgen_row(data, newgen_table) -> 

Makes a DataFrameRow for the newgen table with default values for all the columns
"""
function make_newgen_row(data, newgen_table)
    # maybe use sumamrize_gen_table() but would have to add default values in there somewhere
    # need to store default values somewhere, they don't have to be meaningful
end