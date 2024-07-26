"""
    append_builds!(config, data, existing_table_name, build_table_name)

Adds new builds from `build_table_name` to `existing_table_name`.  
For each row of the build table, it may denote one or more buses to connect to via the `area` and `subarea` columns.  
For any column included in the existing table but not the build table that is also included in the bus table, the value from the connected bus will be used.
"""
function append_builds!(config, data, table_name, build_table_name)
    if !haskey(data, build_table_name)
        @warn "No table $build_table_name defined, not appending any builds to the $table_name table"
        return
    end
    build = get_table(data, build_table_name)
    bus = get_table(data, :bus)
    existing = get_table(data, table_name)
    years = get_years(data)

    # Filter any already-built exogenous generators
    filter!(build) do row
        if row.build_type == "exog"
            row.year_on <= config[:year_gen_data] && return false
            row.year_on > last(years) && return false
        end 
        return true
    end
    build.build_idx = 1:nrow(build)

    # Set up a table to add to the gen table
    new = make_new_from_build(config, data, build_table_name)

    # Begin filling in the other columns.
    leftjoin!(new, build, on=:build_idx, makeunique=true)

    # Add custom columns:
    new[!, "year_shutdown"]       .= "y9999" # add_to_year(year, spec_row.age_shutdown)
    new[!, "year_off"]            .= "y9999"
    new[!, "pcap_inv"]            .= 0.0
    new[!, "past_invest_cost"]    .= Ref(Container(0.0))
    new[!, "past_invest_subsidy"] .= Ref(Container(0.0))

    new_bus_idxs = new.bus_idx::Vector{Int64}
    
    # Loop through and add all the other columns from the existing table
    for col_name in names(existing)
        # If the column already exists in `new`, impute from `bus` if it is a `bus` column and there are missing values
        if hasproperty(new, col_name)
            if hasproperty(bus, col_name)
                col = new[!, col_name]
                for (i, val) in enumerate(col)
                    # Continue if the value is filled in.
                    ismissing(val) || isnothing(val) || isempty(val) || isnan(val) || continue
                    bus_idx = new_bus_idxs[i]
                    col[i] = bus[bus_idx, col_name]
                end
            end
            continue
        end

        # If the column needs to come solely from the bus table, add it here.
        if startswith(col_name, "bus_") || hasproperty(bus, col_name)
            bus_col = hasproperty(bus, col_name) ? bus[!, col_name] : bus[!, col_name[5:end]]
            new[!, col_name] = map(new_bus_idxs) do bus_idx
                bus_col[bus_idx]
            end
            continue
        end

        if hasmethod(get_default_column_value, Tuple{Val{Symbol(col_name)}})
            new[!, col_name] .= get_default_column_value(Val(Symbol(col_name)))
            continue
        end

        error("Column $col_name was in the $table_name table but not found in $build_table_name table nor bus table.")
    end

    # Add any columns to existing that are present in `new` but not in `existing`
    new_table_extra_cols = setdiff(propertynames(new), propertynames(existing))
    for extra_col in new_table_extra_cols
        if hasmethod(get_default_column_value, Tuple{Val{extra_col}})
            existing[!, extra_col] .= get_default_column_value(Val(extra_col))
        else
            @warn "No column $(extra_col) defined in the table $table_name, but it is defined in $build_table_name. Removing that column from both tables.  Consider defining a default value using get_default_column_value"
            select!(new, Not(extra_col))
        end
    end

    append!(existing, new, promote = true)
    return new
end
export append_builds!


function make_new_from_build(config, data, s)
    build = get_table(data, s)
    bus = get_table(data, :bus)
    new = DataFrame(
        :bus_idx => Int64[], 
        :build_idx => Int64[],
        :year_on => String[],
        :year_unbuilt => String[],        
    )
    years = get_years(config)
    year_gen_data = config[:year_gen_data]::String
    for (build_idx, spec_row) in enumerate(eachrow(build))
        get(spec_row, :status, true) || continue

        # Get the bus indexes for which this will be built
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
                # for endogenous new builds, a new build is created for each sim year
                for (yr_idx, year) in enumerate(years)
                    year < year_on_min && continue
                    year > year_on_max && continue
                    new_row = (;
                        bus_idx,
                        build_idx,
                        year_on = year,
                        year_unbuilt = get(years, yr_idx - 1, year_gen_data)
                    )
                    push!(new, new_row)
                end
            else
                @assert !isempty(spec_row.year_on) "Exogenous builds must have a specified year_on value" 
                # Skip this build if it is after the simulation
                year_on = spec_row.year_on
                year_on > last(years) && continue
                new_row = (;
                    bus_idx,
                    build_idx,
                    year_on,
                    year_unbuilt = add_to_year(year_on, -1)
                )
                push!(new, new_row)
            end
        end
    end
    return new
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


