"""
    struct Storage <: Modification

    Storage(;name, file, build_file="")

Storage is represented over sets of time-weighted sequential representative hours for which the following must hold true, for a given storage device:
* Net charge over the interval must equal zero.
* Total charge of the device cannot exceed its maximum charge, or go below zero.
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

function summarize_table(::Val{:build_storage})
    df = TableSummary()
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:status, Bool, NA, false, "Whether or not the storage device is in service"),
        (:build_status, AbstractString, NA, true, "Whether the storage device is 'built', 'new', or 'unbuilt'. All storage devices marked 'new' when the gen file is read in will be changed to 'built'."),
        (:build_type, AbstractString, NA, true, "Whether the storage device is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:year_on, AbstractString, Year, true, "The first year of operation for the storage device. (For new devices this is also the year it was built)"),
        (:year_on_min, AbstractString, NA, true, "The first year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
        (:year_on_max, AbstractString, NA, true, "The last year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
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
    config[:storage_file] = mod.file
    config[:build_storage_file] = mod.build_file

    load_table!(config, data, :storage_file=>:storage)
    load_table!(config, data, :build_storage_file=>:build_storage)
end

function modify_setup_data!(mod::Storage, config, data)
    storage = get_table(data, :storage)
    hours = get_table(data, :hours)

    add_buildable_storage!(config, data)

    ### Add the following columns to the storage table:
    # num_intervals: number of time intervals for storage of this device
    # duration_charge (only if not provided)
    # intervals: each entry is a Vector{Vector{Int64}} - vector of vectors of hour indices
    # interval_hour_duration: each entry is a Dict{Int64, Float64} - lookup of hour index to duration.

    if !hasproperty(storage, :duration_charge)
        storage.duration_charge = copy(storage.duration_discharge)
    end

    storage.num_intervals = fill(0, nrow(storage))
    storage.intervals = fill(Vector{Int64}[], nrow(storage))
    storage.interval_hour_duration = fill(Vector{Float64}(), nrow(storage))

    # Add num_intervals
    gdf_storage = groupby(storage, [:hour_groupby, :hour_duration, :hour_order])

    for k in keys(gdf_storage)
        hour_groupby, hour_duration, hour_order = k
        sdf_storage = gdf[k]
        gdf_hours = groupby(hours, hour_groupby)
        sdf_storage.interval_hour_duration .= hours[!, hour_duration]
        sdf_storage.num_intervals .= length(gdf_hours)

        intervals = Vector{Int64}[]
        for hk in keys(gdf_hours)
            sdf_hours = gdf_hours[hk]
            hour_idxs = getfield(sdf_hours, :rows)
            hour_idxs_sorting = sortperm(df, hour_order)
            hour_idxs_sorted = hour_idxs[hour_idxs_sorting]
            push!(sdf_storage.intervals, hour_idxs_sorted)
        end

        sdf_storage.intervals .= intervals
    end
end

"""
    add_buildable_storage!(config, data)

Add buildable storage from `build_storage` table to `storage` table.
"""
function add_buildable_storage!(config, data)
    storage =       get_table(data, :storage)
    build_storage = get_table(data, :build_storage)
    bus =           get_table(data, :bus)

    spec_names = filter!(!=(:bus_idx), propertynames(newgen))
    years = get_years(data)

    for spec_row in eachrow(build_storage)
        area = spec_row.area
        subarea = spec_row.subarea
        bus_idxs = get_row_idxs(bus, (area=>subarea))

        #set default min and max for year_on if blank
        year_on_min = (spec_row.year_on_min == "" ? "y0" : spec_row.year_on_min)
        year_on_max = (spec_row.year_on_max == "" ? "y9999" : spec_row.year_on_max)

        for bus_idx in bus_idxs
            if spec_row.build_type == "endog"
                # For endogenous new builds a new storage device is created for each year
                for year in years
                    year < year_on_min && continue
                    year > year_on_max && continue
                    
                    # Make row to add to the storage table
                    new_row = Dict(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                    new_row[:year_on] = year
                    push!(storage, new_row, promote=true)
                end
            else # exogenous
                @assert !isempty(spec_row.year_on) "Exogenous storage devices must have a specified year_on value"

                # Skip this build if it is after the simulation
                spec_row.year_on > last(years) && continue

                # for exogenously specified gens, only one generator is created with the specified year_on
                new_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                push!(storage, new_row, promote=true)
            end
        end
    end
end
export add_buildable_storage!

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
        ) >= 0 # -pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
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
    pserv_bus = model[:pserv_bus]
    pgen_bus = model[:pgen_bus]
    for (stor_idx, row) in enumerate(storage)
        bus_idx = row.bus_idx
        η = row.storage_efficiency
        if row.side == "load"
            for yr_idx in 1:nyear, hr_idx in 1:nyear
                add_to_expression!(pserv_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx], -1)
                add_to_expression!(pserv_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], 1/η)
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

"""
    modify_results!(mod::Storage, config, data)

Modify battery results
"""
function modify_results!(mod::Storage, config, data)
    storage = get_table(data, :storage)
end
export modify_results!