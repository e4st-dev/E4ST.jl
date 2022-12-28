# Create new generators 

"""
    setup_new_gens!(config, data)

Creates new generators with zero capacity. Location is determined by build___ columns in bus table. 
"""
function setup_new_gens!(config, data)

    make_newgen_table!(config, data)
    
    characterize_newgen!(config, data)

    append_newgen_table!(data) # after this, all mods should apply to the gen table, should we delete data[:newgen] so that it doesn't get confusing if gen is modified but not newgen? 

end


"""
    make_newgen_table!(config, data) -> 
    
Create newgen table with zero cap gens at buildable buses. Structure mirrors the existing gen table.
"""
function make_newgen_table!(config, data)
    #create table with same columns as gen
    gen_col_names = names(get_gen_table(data))
    newgen = DataFrame([name => [] for name in gen_col_names])
    force_table_types!(newgen, :newgen, summarize_gen_table())

    #for each bus, add rows to newgen for each type of buildable gen
    build_gentypes = get_build_gentypes(config, data)
    bus = get_bus_table(data)
    for gentype in build_gentypes
        colname = Symbol("build"*gentype)
        gentype_bus_idxs = findall(1, bus[colname])
        genfuel = get_genfuel(data,gentype)
        for bus_idx in gentype_bus_idxs
            newgen_row = make_newgen_row(data, newgen)
            newgen_row[:bus_idx] = bus_idx
            newgen_row[:gentype] = gentype
            newgen_row[:genfuel] = genfuel
            # newgen_row[:build_status] = "new"
            push!(newgen, newgen_row)
        end
    end
    data[:newgen] = newgen
end

"""
    characterize_newgen!(config, data) -> 

Assigns new generator characteristics (fuel cost, emis rate, etc) to gens in the newgen table. 
"""
function characterize_newgen!(config, data)
    newgen_char_table = get_newgen_char_table(data)
    newgen = get_newgen_table(data)
    for char_idx in 1:nrow(newgen_char_table)
        newgen_idx = get_filtered_idx(newgen_char_table, char_idx, newgen)
        update_gen_chars!(newgen_char_table, char_idx, newgen, newgen_idx)
    end
    data[:newgen] = newgen
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


#TODO: find a better place for this function to live, it's too general for here
"""
    get_filtered_idx(info_table, info_idx, data_table) -> 

Returns the idxs from data_table which meet the filtering parameters from info_table.
"""
function get_filtered_idx(info_table, info_idx, data_table)
    
end
export get_filtered_idx

"""
    update_gen_chars!(info_table, info_idx, gen_table, gen_idx) ->
    
Updates characterisitcs in gen_table for gen_idx from characteristics in info_table at info_idx. 
"""
function update_gen_chars!(info_table, info_idx, gen_table, gen_idx)
    
end