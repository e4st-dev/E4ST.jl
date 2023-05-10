"""
    InterfaceLimit(;file)

Constrain power flowing between regions for each representative hour. See [`summarize_table(::Val{:interface_limit})`](@ref).
* [`modify_raw_data!(mod::InterfaceLimit, config, data)`](@ref)
* [`modify_model!(mod::InterfaceLimit, config, data, model)`](@ref)

To change the power flow min/max for each year and/or hour, see [`AdjustYearly`](@ref) and [`AdjustHourly`](@ref).
"""
Base.@kwdef struct InterfaceLimit <: Modification
    file::String
end
export InterfaceLimit

"""
comments from discussion with Dan
* hourly differing limits generally not necessary
* DC lines generally not included because usually interface limits are often used to address voltage stability concerns.  
* Canadian exports could mess up some policy results.  Might be nice to have annual flow limit to do this, because it could really help represent certain things.
"""

@doc """
    summarize_table(::Val{:interface_limit})

$(table2markdown(summarize_table(Val(:interface_limit))))
"""
function summarize_table(::Val{:interface_limit})
    df = TableSummary()
    push!(df, 
        (:name, String, NA, false, "Name of the interface limit, not used"),
        (:description, String, NA, false, "Description of the interface limit, not used."),
        (:f_filter, String, NA, true, "The filter for the bus table specifiying the region the power is flowing **f**rom.  I.e. `country=>narnia`, or `state=>[angard, stormness]`"),
        (:t_filter, String, NA, true, "The filter for the bus table specifiying the region the power is flowing **t**o."),
        (:pflow_max, Float64, MWFlow, false, "The maximum allowable power flow in the direction of `f` to `t`. If left as ±Inf, no constraint made."),
        (:pflow_min, Float64, MWFlow, false, "The minimum allowable power flow in the direction of `f` to `t`.  Can be positive or negative.  If left as ±Inf, no constraint made."),
        (:eflow_yearly_max, Float64, MWhFlow, false, "The yearly maximum allowable energy to flow in the direction of `f` to `t`. If left as ±Inf, no constraint made."),
        (:eflow_yearly_min, Float64, MWhFlow, false, "The yearly minimum allowable energy to flow in the direction of `f` to `t`.  Can be positive or negative. If left as ±Inf, no constraint made."),
        (:price, Float64, DollarsPerMWhFlow, false, "The price of net flow in the direction of `f` to `t`."),
        (:include_dc, Bool, NA, false, "Whether or not to include DC lines in this interface limit.  If not provided, assumed that DC lines are not included"),
    )
    return df
end

"""
    modify_raw_data!(mod::InterfaceLimit, config, data)

Reads the interface limit table from `mod.file` and stores it to `data[:interface_limit]`.
"""
function modify_raw_data!(mod::InterfaceLimit, config, data)
    table = read_table(data, mod.file, :interface_limit)
    data[:interface_limit] = table
end

"""
    modify_model!(mod::InterfaceLimit, config, data, model)

* Gathers each of the branches (forward and reverse) for each of the rows of the `interface_limit` table.
* Creates an expression `pflow_if[if_idx, yr_idx, hr_idx]` for the power flowing, in MW, in each interface.  This includes
    * The sum of all of the `pflow_branch` terms for branches that are flowing in the direction of **f**rom to **t**o.
    * Net the sum of all of the `pflow_branch` terms for branches that are flowing in the direction of **t**o to **f**rom.
* Creates min and max constraints `cons_pflow_if_min[if_idx, yr_idx, hr_idx]` and `cons_pflow_if_max[if_idx, yr_idx, hr_idx]` for each interface limit, for each year and hour in which the limit is finite, and there are qualifying `pflow_branch` variables in the interface.
* Creates min and max constraints `cons_eflow_if_min[if_idx, yr_idx]` and `cons_eflow_if_max[if_idx, yr_idx]` for each interface limit, for each year in which the limit is finite, and there are qualifying `pflow_branch` variables in the interface.
* Creates expression `interface_flow_cost_obj[if_idx, yr_idx, hr_idx]` for the cost of interface flow, and adds it to the objective.
"""
function modify_model!(mod::InterfaceLimit, config, data, model)
    table = get_table(data, :interface_limit)
    bus = get_table(data, :bus)
    branch = get_table(data, :branch)
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    hour_weights = get_hour_weights(data)
    pflow_branch = model[:pflow_branch]
    
    # Retrieve forward and reverse branch indices for each interface limit
    table.forward_branch_idxs = fill(Int64[], nrow(table))
    table.reverse_branch_idxs = fill(Int64[], nrow(table))
    for row in eachrow(table)
        f_filter = parse_comparison(row.f_filter)
        t_filter = parse_comparison(row.t_filter)
        f_bus_idxs = Set(get_row_idxs(bus, f_filter))
        t_bus_idxs = Set(get_row_idxs(bus, t_filter))
        row.forward_branch_idxs = get_row_idxs(branch, :f_bus_idx => in(f_bus_idxs), :t_bus_idx => in(t_bus_idxs))
        row.reverse_branch_idxs = get_row_idxs(branch, :t_bus_idx => in(f_bus_idxs), :f_bus_idx => in(t_bus_idxs))
    end

    @expression(model,
        pflow_if[if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        sum0(branch_idx -> pflow_branch[branch_idx, yr_idx, hr_idx], table.forward_branch_idxs[if_idx]) - 
        sum0(branch_idx -> pflow_branch[branch_idx, yr_idx, hr_idx], table.reverse_branch_idxs[if_idx])
    )
    
    # Add DC line flow to expression where relevant.
    if hasproperty(table, :include_dc) && any(table.include_dc) && has_table(data, :dc_line) && haskey(model, :pflow_dc)
        dc_line = get_table(data, :dc_line)
        table.forward_dc_idxs = fill(Int64[], nrow(table))
        table.reverse_dc_idxs = fill(Int64[], nrow(table))
        for row in eachrow(table)
            f_filter = parse_comparison(row.f_filter)
            t_filter = parse_comparison(row.t_filter)
            f_bus_idxs = Set(get_row_idxs(bus, f_filter))
            t_bus_idxs = Set(get_row_idxs(bus, t_filter))
            row.forward_dc_idxs = get_row_idxs(dc_line, :f_bus_idx => in(f_bus_idxs), :t_bus_idx => in(t_bus_idxs))
            row.reverse_dc_idxs = get_row_idxs(dc_line, :t_bus_idx => in(f_bus_idxs), :f_bus_idx => in(t_bus_idxs))
        end

        pflow_dc = model[:pflow_dc]

        for (if_idx, row) in enumerate(eachrow(table))
            row.include_dc || continue
            for dc_idx in row.forward_dc_idxs
                for yr_idx in 1:nyr, hr_idx in 1:nhr
                    add_to_expression!(pflow_if[if_idx, yr_idx, hr_idx], pflow_dc[dc_idx, yr_idx, hr_idx])
                end
            end
            for dc_idx in row.reverse_dc_idxs
                for yr_idx in 1:nyr, hr_idx in 1:nhr
                    add_to_expression!(pflow_if[if_idx, yr_idx, hr_idx], pflow_dc[dc_idx, yr_idx, hr_idx], -1)
                end
            end
        end
    end

    # Add interface constraints
    
    if hasproperty(table, :pflow_max)
        @constraint(model,
            cons_pflow_if_max[
                if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr;
                (pflow_if[if_idx, yr_idx, hr_idx] != 0.0 && isfinite(table.pflow_max[if_idx][yr_idx, hr_idx])) # Skip any Inf values
            ],
            pflow_if[if_idx, yr_idx, hr_idx] <= 
            table.pflow_max[if_idx][yr_idx, hr_idx]
        )
    end

    if hasproperty(table, :pflow_min)
        @constraint(model,
            cons_pflow_if_min[
                if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr;
                (pflow_if[if_idx, yr_idx, hr_idx] != 0.0 && isfinite(table.pflow_min[if_idx][yr_idx, hr_idx])) # Skip any Inf values
            ],
            pflow_if[if_idx, yr_idx, hr_idx] >= 
            table.pflow_min[if_idx][yr_idx, hr_idx]
        )
    end

    if hasproperty(table, :eflow_yearly_max)
        @constraint(model,
            cons_eflow_if_max[
                if_idx in axes(table, 1), yr_idx in 1:nyr;
                (any(!=(0), view(pflow_if, if_idx, yr_idx, :)) && isfinite(table.eflow_yearly_max[if_idx][yr_idx, :]))
            ],
            sum(hour_weights[hr_idx] * pflow_if[if_idx, yr_idx, hr_idx] for hr_idx in 1:nhr) <= 
            table.eflow_yearly_max[if_idx][yr_idx, :]
        )
    end

    if hasproperty(table, :eflow_yearly_min)
        @constraint(model,
            cons_eflow_if_min[
                if_idx in axes(table, 1), yr_idx in 1:nyr;
                (any(!=(0), view(pflow_if, if_idx, yr_idx, :)) && isfinite(table.eflow_yearly_min[if_idx][yr_idx, :]))
            ],
            sum(hour_weights[hr_idx] * pflow_if[if_idx, yr_idx, hr_idx] for hr_idx in 1:nhr) >= 
            table.eflow_yearly_min[if_idx][yr_idx, :]
        )
    end

    # Add to objective function
    if hasproperty(table, :price)
        @expression(model, 
            interface_flow_cost_obj[if_idx in axes(table,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            pflow_if[if_idx, yr_idx, hr_idx] * hour_weights[hr_idx] * table.price[if_idx][yr_idx, hr_idx]
        )
        add_obj_exp!(data, model, PerMWhFlow(), :interface_flow_cost_obj, oper=+)
    end
end

struct PerMWhFlow <: Term end

function sum0(f, itr)
    isempty(itr) && return 0.0
    return sum(f, itr)
end