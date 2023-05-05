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
        (:max, Float64, MWFlow, true, "The maximum allowable power flow in the direction of `f` to `t`"),
        (:min, Float64, MWFlow, true, "The minimum allowable power flow in the direction of `f` to `t`.  Can be positive or negative."),
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
* Creates an expression `pflow_if` for the power flowing, in MW, in each interface.  This includes
    * The sum of all of the `pflow_branch` terms for branches that are flowing in the direction of **f**rom to **t**o.
    * Net the sum of all of the `pflow_branch` terms for branches that are flowing in the direction of **t**o to **f**rom.
* Creates min and max constraints `cons_pflow_if_min` and `cons_pflow_if_max` for each interface limit, for each year and hour in which the limit is finite, and there are qualifying `pflow_branch`variables in the interface.
"""
function modify_model!(mod::InterfaceLimit, config, data, model)
    table = get_table(data, :interface_limit)
    bus = get_table(data, :bus)
    branch = get_table(data, :branch)
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    
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

    # Modify the model
    cons_min_name = Symbol("cons_pflow_if_min")
    cons_max_name = Symbol("cons_pflow_if_max")
    pflow_if_name = Symbol("pflow_if")
    pflow_branch = model[:pflow_branch]

    pflow_if = @expression(model,
        [if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        sum0(branch_idx -> pflow_branch[branch_idx, yr_idx, hr_idx], table.forward_branch_idxs[if_idx]) - 
        sum0(branch_idx -> pflow_branch[branch_idx, yr_idx, hr_idx], table.reverse_branch_idxs[if_idx])
    )
    model[pflow_if_name] = pflow_if
    
    # TODO: Add dc line power flow here if needed

    model[cons_max_name] = @constraint(model,
        [
            if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr;
            (pflow_if[if_idx, yr_idx, hr_idx] != 0.0 && isfinite(table.max[if_idx][yr_idx, hr_idx])) # Skip any Inf values
        ],
        pflow_if[if_idx, yr_idx, hr_idx] <= 
        table.max[if_idx][yr_idx, hr_idx]
    )

    model[cons_min_name] = @constraint(model,
        [
            if_idx in axes(table, 1), yr_idx in 1:nyr, hr_idx in 1:nhr;
            (pflow_if[if_idx, yr_idx, hr_idx] != 0.0 && isfinite(table.min[if_idx][yr_idx, hr_idx])) # Skip any Inf values
        ],
        pflow_if[if_idx, yr_idx, hr_idx] >= 
        table.min[if_idx][yr_idx, hr_idx]
    )
end

function sum0(f, itr)
    isempty(itr) && return 0.0
    return sum(f, itr)
end