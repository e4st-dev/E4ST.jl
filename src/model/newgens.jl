# Create new generators 

"""
    setup_new_gens!(config, data)

Creates new generators with zero capacity. Location is determined by build___ columns in bus table. 
"""
function setup_new_gens!(config, data)

    newgen = make_newgen_table(config, data)

    append_newgen_table!(data, newgen)

end
export setup_new_gens!


"""
    make_newgen_table(config, data) -> 
    
Create empty newgen table with a structure that mirrors the existing gen table.
"""
function make_newgen_table(config, data)
    #create table with same columns as gen
    gen = get_gen_table(data)
    newgen = similar(gen, 0) 

    # add potential generation capacity and exogenously built generators 
    make_newgens!(config, data, newgen)
    
    return newgen
end

"""
    make_newgens!(config, data, newgen) -> 

Create newgen rows for each spec in build_gen. Creates a generator of the given type at all buses in the area/subarea. 
Endogenous unbuilt gens are created for each year in years.
Exogenously specified generators are also added to newgen through the build_gen sheet.
"""
function make_newgens!(config, data, newgen)
    build_gen = get_build_gen_table(data)
    bus = get_bus_table(data)
    spec_names = filter!(!=(:bus_idx), propertynames(newgen)) #this needs to be updated if there is anything else in gen that isn't a spec
    years = get_years(data)

    for spec_row in eachrow(build_gen)
        area = spec_row.area
        subarea = spec_row.subarea
        bus_idxs = table_rows(bus, (area=>subarea))
        spec_row.year_on_min == "na" ? year_on_min = "y0" : year_on_min = spec_row.year_on_min
        spec_row.year_on_max == "na" ? year_on_max = "y9999" : year_on_max = spec_row.year_on_max

        for bus_idx in bus_idxs
            if spec_row.build_type == "endog"
                # for endogenous new builds, a new gen is created for each sim year
                for year in years
                    if year_on_min <= year <= year_on_max
                        #populate newgen_row with specs
                        newgen_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                        newgen_row[:year_on] = year
                        push!(newgen, newgen_row)
                    end
                end
            else 
                # for exogenously specified gens, only one generator is created with the specified year_on
                newgen_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)  
                push!(newgen, newgen_row)        
            end
        end
    end
    return newgen
end


"""
    append_newgen_table!(data, newgen) -> 

Appends the newgen table to the gen table. 
"""
function append_newgen_table!(data, newgen)
    append!(get_gen_table(data), newgen)
end



# This is unecessary for how the new gen code is current written but might be helpful later. 
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


