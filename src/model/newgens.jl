# Create new generators 

"""
    setup_new_gens!(config, data)

Creates new generators with zero capacity. Location is determined by build___ columns in bus table. 
"""
function setup_new_gens!(config, data)

    newgen = make_newgen_table(config, data)
    
    # TODO: pass in newgen to these functions
    characterize_newgen!(config, data, newgen)

    add_exogenous_gens!(config, data, newgen)

    append_newgen_table!(data, newgen)
    # TODO: newgen shouldn't be a part of data

end


"""
    make_newgen_table(config, data) -> 
    
Create newgen table with zero cap gens at buildable buses. Structure mirrors the existing gen table.
"""
function make_newgen_table(config, data)
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
    return newgen
end

"""
    characterize_newgen!(config, data, newgen) -> 

Assigns new generator characteristics/specs (fuel cost, emis rate, etc) to gens in the newgen table. 
"""
function characterize_newgen!(config, data, newgen)
    build_gen = get_build_gen_table(data)
    for spec_idx in 1:nrow(build_gen)
        newgen_idx = get_filtered_idx(build_gen, spec_idx, newgen)
        update_gen_spec!(build_gen, spec_idx, newgen, newgen_idx)
    end
end


"""
    append_newgen_table!(data, newgen) -> 

Appends the newgen table to the gen table. 
"""
function append_newgen_table!(data, newgen)
    append!(data[:gen], newgen)
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
function get_genfuel(data, gentype::String)
    genfuel_table = get_genfuel_table(data) #TODO: update data to load in genfuel table
    genfuel = genfuel_table.genfuel[findall(x -> x == gentype, genfuel_table[!, :gentype])]
    genfuel == String[] && error("There is no corresponding genfuel for this gentype")
    return genfuel
end

"""
    make_newgen_row(data, newgen) -> 

Makes a DataFrameRow for the newgen table with default values for all the columns
"""
function make_newgen_row(data, newgen)
    # maybe use sumamrize_gen_table() but would have to add default values in there somewhere
    # need to store default values somewhere, they don't have to be meaningful
    newgen_col_names = name(newgen)
    newgenrow = DataFrameRow([name => [] for name in newgen_col_names])
    force_table_types!(newgenrow, :newgenrow, summarize_gen_table())
    #TODO: add the default or missing values to newgenrow[1,:]

end

"""
    update_gen_specs!(info_table, info_idx, gen_table, gen_idx) ->
    
Updates characterisitcs/specs in gen_table for gen_idx from characteristics in info_table at info_idx. 
"""
function update_gen_specs!(info_table, info_idx, gen_table, gen_idx)
    
end

#TODO: find a better place for this function to live, it's too general for here
"""
    get_filtered_idx(info_table, info_idx, data_table) -> 

Returns the idxs from data_table which meet the filtering parameters from info_table.
"""
function get_filtered_idx(info_table, info_idx, data_table)
    
end
export get_filtered_idx

