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
    gen = get_table(data, :gen)
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
    build_gen = get_table(data, :build_gen)
    bus = get_table(data, :bus)
    gen = get_table(data, :gen)
    years = get_years(data)

    newgen_cols = Symbol.(names(newgen))

    # Filter any already-built exogenous generators
    filter!(build_gen) do row
        if row.build_type == "exog"
            row.year_on <= config[:year_gen_data] && return false
            row.year_on > last(years) && return false
        end
        
        return true
    end

    #get the names of specifications that will be pulled from the build_gen table
    spec_names = filter!(
        !in((:bus_idx, :gen_latitude, :gen_longitude, :gen_state, :gen_county, :reg_factor, :year_off, :year_shutdown, :pcap_inv, :year_unbuilt, :past_invest_cost, :past_invest_subsidy)), 
        propertynames(newgen)
    ) #this needs to be updated if there is anything else in gen that isn't a spec

    for n in spec_names
        hasproperty(build_gen, n) || error("Gen table has column $n, but not found in build_gen table. If this is a mod specific column, consider adding it to build_gen using modify_raw_data!()")
    end

    for spec_row in eachrow(build_gen)
        # continue if status is false
        get(spec_row, :status, true) || continue

        area = spec_row.area
        subarea = spec_row.subarea
        if isempty(area)
            bus_idxs = 1:nrow(bus)
        else
            bus_idxs = get_row_idxs(bus, (area=>subarea))
        end
        
        #set default min and max for year_on if blank
        year_on_min = (spec_row.year_on_min == "" ? "y0" : spec_row.year_on_min)
        year_on_max = (spec_row.year_on_max == "" ? "y9999" : spec_row.year_on_max)

        for bus_idx in bus_idxs
            if spec_row.build_type == "endog"
                # for endogenous new builds, a new gen is created for each sim year
                for (yr_idx, year) in enumerate(years)
                    year < year_on_min && continue
                    year > year_on_max && continue
                    #populate newgen_row with specs
                    newgen_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)

                    #set year_on and off
                    newgen_row[:year_on] = year
                    newgen_row[:year_unbuilt] = get(years, yr_idx - 1, config[:year_gen_data])
                    newgen_row[:year_shutdown] = "y9999" # add_to_year(year, spec_row.age_shutdown)
                    newgen_row[:year_off] = "y9999"
                    newgen_row[:pcap_inv] = 0.0
                    newgen_row[:past_invest_cost] = Container(0.0)
                    newgen_row[:past_invest_subsidy] = Container(0.0)

                    #add gen location
                    hasproperty(newgen, :gen_latitude) && (newgen_row[:gen_latitude] = bus.bus_latitude[bus_idx])
                    hasproperty(newgen, :gen_longitude) && (newgen_row[:gen_longitude] = bus.bus_longitude[bus_idx])
                    hasproperty(newgen, :gen_state) && (newgen_row[:gen_state] = bus.state[bus_idx])
                    hasproperty(newgen, :gen_county) && (newgen_row[:gen_county] = bus.county[bus_idx])
                    hasproperty(newgen, :reg_factor) && (newgen_row[:reg_factor] = bus.reg_factor[bus_idx])

                    push!(newgen, newgen_row, promote=true)
                end
            else
                @assert !isempty(spec_row.year_on) "Exogenous generators must have a specified year_on value" 

                # Skip this build if it is after the simulation
                spec_row.year_on > last(years) && continue
                
                # for exogenously specified gens, only one generator is created with the specified year_on
                newgen_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                hasproperty(newgen, :gen_latitude) && (newgen_row[:gen_latitude] = bus.bus_latitude[bus_idx])
                hasproperty(newgen, :gen_longitude) && (newgen_row[:gen_longitude] = bus.bus_longitude[bus_idx])
                hasproperty(newgen, :reg_factor) && (newgen_row[:reg_factor] = bus.reg_factor[bus_idx])

                newgen_row[:year_shutdown] = "y9999" #add_to_year(spec_row.year_on, spec_row.age_shutdown)
                newgen_row[:year_off] = "y9999"
                newgen_row[:pcap_inv] = 0.0
                newgen_row[:year_unbuilt] = add_to_year(newgen_row[:year_on], -1)
                newgen_row[:past_invest_cost] = Container(0.0)
                newgen_row[:past_invest_subsidy] = Container(0.0)

                # set gen_state and gen_county if specified, otherwise set to bus location
                hasproperty(newgen, :gen_state) &&  (hasproperty(spec_row, :gen_state) ? (newgen_row[:gen_state] = spec_row[:gen_state]) : (newgen_row[:gen_state] = bus.state[bus_idx]))
                hasproperty(newgen, :gen_county) && (hasproperty(spec_row, :gen_county) ? (newgen_row[:gen_county] = spec_row[:gen_county]) : (newgen_row[:gen_county] = bus.county[bus_idx]))

                #check that all necessary columns are present in newgen_row
                newgen_row_cols = keys(newgen_row)
                issetequal(newgen_cols, newgen_row_cols) || @warn("The newgen_row does not contain the following columns that are in the newgen table: $(setdiff(newgen_cols, newgen_row_cols))")
                #@show setdiff(newgen_cols, newgen_row_cols)

                push!(newgen, newgen_row, promote=true)
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
    append!(get_table(data, :gen), newgen, promote = true)
end



# This is unecessary for how the new gen code is current written but might be helpful later. 
"""
    get_genfuel(data, gentype) -> 

Returns the corresponding genfuel for the given gentype. 
"""
function get_genfuel(data, gentype::String)
    genfuel_table = get_table(data, :genfuel_table)
    genfuel = genfuel_table.genfuel[findall(x -> x == gentype, genfuel_table[!, :gentype])]
    genfuel == String[] && error("There is no corresponding genfuel for this gentype")
    return genfuel
end


