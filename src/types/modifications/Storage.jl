"""
    struct Storage <: Modification

    Storage(;name, file, build_file="")
"""
struct Storage <: Modification
    name::Symbol
    file::String
    build_file::String
end
function Storage(;name, file, build_file="")
    return Storage(name, file, build_file)
end

function summarize_table(::Val{:storage})
    df = TableSummary()
    push!(df, 
        (:bus_idx, Int64, NA, true, "The index of the `bus` table that the storage device corresponds to"),
        (:status, Bool, NA, false, "Whether or not the storage device is in service"),
        (:build_status, AbstractString, NA, true, "Whether the storage device is 'built', 'new', or 'unbuilt'. All storage devices marked 'new' when the gen file is read in will be changed to 'built'."),
        (:build_type, AbstractString, NA, true, "Whether the storage device is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:year_on, AbstractString, Year, true, "The first year of operation for the storage device. (For new devices this is also the year it was built)"),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power discharge capacity for the storage device"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power discharge capacity of the storage device (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power discharge capacity of the storage device"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of energy discharged"),
        (:fom, Float64, DollarsPerMWCapacity, true, "Hourly fixed operation and maintenance cost for a MW of discharge capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacity, true, "Hourly capital expenditures for a MW of discharge capacity"),
        (:duration_discharge, Float64, Hours, true, "Number of hours to fully discharge the storage device, from full."),
        (:duration_charge, Float64, Hours, false, "Number of hours to fully charge the empty storage device from empty. (Defaults to equal `duration_discharge`)"),
        (:storage_efficiency, Float64, true, MWhDischargedPerMWhCharged, "The round-trip efficiency of the battery."),
        (:side, String, true, NA, "The side of the power balance equation to add the charging/discharging to.  Can be \"gen\" or \"load\""),
        (:hour_groupby, String, NA, true, "The column of the `hours` table to group by.  For example `day`"),
        (:hour_duration, String, NA, true, "The column of the `hours` table specifying the duration of each representatibe hour"),
        (:hour_order, String, NA, true, "The column of the `hours` table specifying the sequence of the hours."),
    )
end

function modify_raw_data!(mod::Storage, config, data)
    # TODO: Pull in the storage table
    # TODO: Pull in the build_storage table
end

function modify_setup_data!(mod::Storage, config, data)
    # TODO: Add the buildable storage devices to the storage table
    # TODO: Add the following columns to the storage table:
    # num_intervals: number of time intervals for storage of this device
    # duration_charge (only if not provided)
    # intervals: each entry is a Vector{Vector{Int64}} - vector of vectors of hour indices
    # interval_hour_duration: each entry is a Dict{Int64, Float64} - lookup of hour index to duration.
    # year_on
end

function modify_model!(mod::Storage, config, data, model)
    storage = get_table(data, :storage)
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    years = get_years(data)

    ### Create Variables
    # Power discharge capacity
    @variable(model, 
        pcap_stor[stor_idx in axes(storage,1), yr_idx in 1:nyr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx]
    )

    # Power discharged
    @variable(model,
        pdischarge_stor[stor_idx in axex(storage, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx]
    )

    # Power charged - upper bound depends on ration of duration for charge/discharge durations.
    @variable(model,
        pcharge_stor[stor_idx in axes(storage, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx] * storage.duration_charge[stor_idx] / storage.duration_discharge[stor_idx]
    )

    ### Create Constraints
    # Constrain start and end of each device's intervals to be the same
    @constraint(model,
        cons_stor_charge_bal[stor_idx in axes(storage,1), yr_idx in 1:nyr, int_idx in 1:storage.num_intervals[stor_idx]],
        sum(
            (
                pdischarge_stor[stor_idx, yr_idx, hr_idx] - 
                pcharge_stor[stor_idx, yr_idx, hr_idx]
            ) * 
            storage.interval_hour_weights[stor_idx][hr_idx] 
            for hr_idx in storage.intervals[stor_idx][int_idx]
        ) == 0.0
    )

    ### Constrain net charge after each hour in each interval is bounded by maximum charge
    # Constrain upper limit on charge
    @constraint(model,
        cons_stor_charge_max[
            stor_idx in axes(storage,1),
            yr_idx in 1:nyr,
            int_idx in 1:storage.num_intervals[stor_idx],
            _hr_idx in 1:(length(storage.intervals[stor_idx][int_idx]) - 1)
        ],
        sum(
            (
                pdischarge_stor[stor_idx, yr_idx, hr_idx] -
                pcharge_stor[stor_idx, yr_idx, hr_idx]
            ) *
            storage.interval_hour_weights[stor_idx][hr_idx]
            for hr_idx in storage.intervals[stor_idx][int_idx][1:_hr_idx]
        ) <= pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
    )
    
    # Constrain upper limit on charge
    @constraint(model,
        cons_stor_charge_min[
            stor_idx in axes(storage,1),
            yr_idx in 1:nyr,
            int_idx in 1:storage.num_intervals[stor_idx],
            _hr_idx in 1:(length(storage.intervals[stor_idx][int_idx]) - 1)
        ],
        sum(
            (
                pdischarge_stor[stor_idx, yr_idx, hr_idx] - 
                pcharge_stor[stor_idx, yr_idx, hr_idx]
            ) * 
            storage.interval_hour_weights[stor_idx][hr_idx] 
            for hr_idx in storage.intervals[stor_idx][int_idx][1:_hr_idx]
        ) >= -pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
    )

    ### Add build constraints for endogenous batteries

    # Constrain Capacity to 0 before the start/build year 
    if any(>(first(years)), storage.year_on)
        @constraint(model, 
            cons_pcap_prebuild_stor[
                stor_idx in axes(storage, 1),
                yr_idx in 1:nyr;
                # Only for years before the device came online
                years[yr_idx] < storage.year_on[stor_idx]
            ],
            stor_idx[stor_idx, yr_idx] == 0
        ) 
    end

    # Constrain existing capacity to only decrease (only retire, not add capacity)
    if nyr > 1
        @constraint(model, 
            cons_pcap_noadd_stor[
                stor_idx in axes(storage,1),
                yr_idx in 1:(nyear-1);
                years[yr_idx] >= storage.year_on[stor_idx]
            ], 
            pcap_stor[stor_idx, yr_idx+1] <= pcap_stor[stor_idx, yr_idx])
    end
    
    ### Add charge/discharge to appropriate expressions in power balancing equation
    plserv_bus = model[:plserv_bus]
    pgen_bus = model[:pgen_bus]
    for (stor_idx, row) in enumerate(storage)
        bus_idx = row.bus_idx
        η = row.storage_efficiency
        if row.side == "load"
            for yr_idx in 1:nyear, hr_idx in 1:nyear
                add_to_expression!(plserv_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx], -1)
                add_to_expression!(plserv_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], 1/η)
            end
        else # row.side == "gen"
            for yr_idx in 1:nyear, hr_idx in 1:nyear
                add_to_expression!(pgen_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx])
                add_to_expression!(pgen_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], -1/η)
            end
        end
    end

    ### Add Costs to objective function terms: vom, fom, capex.
    @expression(model,
        vom_stor,
        sum(
            pdischarge_stor[stor_idx, yr_idx, hr_idx] * get_table_num(data, :storage, :vom, stor_idx, yr_idx, hr_idx)
            for stor_idx in axes(storage,1), yr_idx in 1:nyr, hr_idx in 1:nhr
        )
    )

    @expression(model,
        fom_stor,
        sum(
            pcap_stor[stor_idx, yr_idx] * get_table_num(data, :storage, :fom, stor_idx, yr_idx, :)
            for stor_idx in axes(storage,1), yr_idx in 1:nyr
        )
    )

    @expression(model,
        capex_obj_stor,
        sum(
            pcap_stor[stor_idx, yr_idx] * get_table_num(data, :storage, :capex_obj, stor_idx, yr_idx, :)
            for stor_idx in axes(storage,1), yr_idx in 1:nyr
        )
    )

    add_obj_exp!(data, model, PerMWhGen(), vom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCap(), fom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCap(), capex_obj_stor, oper = +) 
end

