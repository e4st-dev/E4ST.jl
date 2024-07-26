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

mod_rank(::Type{<:DCLine}) = -3.0

"""
    modify_raw_data!(mod::DCLine, config, data)

Loads `mod.file => data[:dc_line]`
"""
function modify_raw_data!(mod::DCLine, config, data)
    config[:dc_line_file] = mod.file
    read_table!(config, data, :dc_line_file=>:dc_line)
    return nothing
end

@doc """
    summarize_table(::Val{:dc_line})

$(table2markdown(summarize_table(Val(:dc_line))))
"""
function summarize_table(::Val{:dc_line})
    df = TableSummary()
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
    pflow_bus = model[:pflow_bus]::Array{AffExpr, 3}

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
            add_to_expression!(pflow_bus[f_bus_idx, year_idx, hour_idx], pflow_dc[dc_idx, year_idx, hour_idx], 1)
            add_to_expression!(pflow_bus[t_bus_idx, year_idx, hour_idx], pflow_dc[dc_idx, year_idx, hour_idx], -1)
        end
    end
    
    return nothing
end

function modify_results!(mod::DCLine, config, data)
    # Loop through each branch and add the hourly merchandising surplus, in dollars, to the appropriate bus
    ms =         get_table_col(data, :bus, :merchandising_surplus)::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
    
    if config[:line_loss_type] == "pflow"
        lmp_elserv = get_table_col(data, :bus, :lmp_elserv)::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
    else
        lmp_elserv = get_table_col(data, :bus, :lmp_elserv_preloss)::Vector{SubArray{Float64, 2, Array{Float64, 3}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}, Base.Slice{Base.OneTo{Int64}}}, true}}
    end
    dc_line = get_table(data, :dc_line)

    # Get numbers used for indexing
    ndc = nrow(dc_line)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)

    f_bus_idxs = dc_line.f_bus_idx::Vector{Int64}
    t_bus_idxs = dc_line.t_bus_idx::Vector{Int64}
    pflow_dc = get_raw_result(data, :pflow_dc)::Array{Float64, 3}
    hour_weights = get_hour_weights(data)
    hour_weights_mat = [hour_weights[hr_idx] for yr_idx in 1:nyr, hr_idx in 1:nhr]
    for dc_idx in 1:ndc
        f_bus_idx = f_bus_idxs[dc_idx]
        t_bus_idx = t_bus_idxs[dc_idx]
        f_bus_lmp = lmp_elserv[f_bus_idx] # nyr x nhr
        t_bus_lmp = lmp_elserv[t_bus_idx] # nyr x nhr
        pflow = view(pflow_dc, dc_idx, :, :) # nyr x nhr
        ms_per_bus = ((t_bus_lmp .- f_bus_lmp) .* pflow) .* hour_weights_mat .* 0.5
        ms[f_bus_idx] .+= ms_per_bus
        ms[t_bus_idx] .+= ms_per_bus
    end

    add_table_col!(data, :dc_line, :pflow, pflow_dc, MWFlow,"Average Power flowing through line")    

end