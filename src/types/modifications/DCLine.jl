"""
    struct DCLine <: Modification
        
    DCLine(;file)

This [`Modification`](@ref) takes in a file representing the dc lines to add to the model.  See [`summarize_table(::Val{:dc_line})`](@ref) for info on the table.

This creates a single variable for each dc line (at each point in time), and adds it to `pbal_bus` of the `t_bus_idx`, and subtracts it from the `f_bus_idx`.  Represents a lossless transfer of power, ignoring voltage angle requirements.

# Interfaces Implemented
* [`modify_raw_data!(mod::DCLine, config, data)`](@ref) - loads `mod.file => data[:dc_line]`
* [`modify_model!(mod::DCLine, config, data, model)`](@ref) - Add dc lines to the model from `data[:dc_lines]`, creating `pflow_dc` variables, and adding/subtracting to the corresponding `pflow_bus` variables.
"""
Base.@kwdef struct DCLine <: Modification
    file::String
end
export DCLine

"""
    modify_raw_data!(mod::DCLine, config, data)

Loads `mod.file => data[:dc_line]`
"""
function modify_raw_data!(mod::DCLine, config, data)
    config[:dc_line_file] = mod.file
    read_table!(config, data, :dc_line_file=>:dc_line)
    return nothing
end

"""
    summarize_table(::Val{:dc_line}) -> summary
"""
function summarize_table(::Val{:dc_line})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:f_bus_idx, Int64, NA, true, "The index of the `bus` table that the line originates **f**rom"),
        (:t_bus_idx, Int64, NA, true, "The index of the `bus` table that the line goes **t**o"),
        (:status, Bool, NA, false, "Whether or not the dc line is in service"),
        (:pflow_max, Float64, MWFlow, true, "Maximum power flowing through the dc line")
    )
    return df
end

"""
    modify_model!(mod::DCLine, config, data, model)

Add dc lines to the model from `data[:dc_lines]`, creating `pflow_dc` variables, and adding/subtracting to the corresponding `pflow_bus` variables.
"""
function modify_model!(mod::DCLine, config, data, model)
    dc_line = get_table(data, :dc_line)

    # Get numbers used for indexing
    ndc = nrow(dc_line)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)

    # Add the pflow_dc variable
    @variable(model,
        pflow_dc[dc_idx in 1:ndc, year_idx in 1:nyear, hour_idx in 1:nhour],
        start=0.0,
        lower_bound = -get_table_num(data, :dc_line, :pflow_max, dc_idx, year_idx, hour_idx),
        upper_bound =  get_table_num(data, :dc_line, :pflow_max, dc_idx, year_idx, hour_idx)
    )

    # Add the pflow_dc variable to the appropriate power balancing expressions
    for dc_idx in 1:ndc
        f_bus_idx = dc_line[dc_idx, :f_bus_idx]::Int64
        t_bus_idx = dc_line[dc_idx, :t_bus_idx]::Int64
        for year_idx in 1:nyear, hour_idx in 1:nhour
            add_to_expression!(model[:pflow_bus][f_bus_idx, year_idx, hour_idx], pflow_dc[dc_idx, year_idx, hour_idx], 1)
            add_to_expression!(model[:pflow_bus][t_bus_idx, year_idx, hour_idx], pflow_dc[dc_idx, year_idx, hour_idx], -1)
        end
    end
    
    return nothing
end