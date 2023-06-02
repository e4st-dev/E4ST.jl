"""
    struct Storage <: Modification

    Storage(;name, file, build_file="")

Storage is represented over sets of time-weighted sequential representative hours for which the following must hold true, for a given storage device:
* Net charge over the interval must equal zero.
* Total charge of the device cannot exceed its maximum charge, or go below zero.
* Initial charge over an interval can be anywhere between 0 and the maximum charge, and is the same initial charge for each time interval.

# Arguments
* `name` - the name of the [`Modification`](@ref).
* `file` - the filename of the storage table, where each row represents a storage device. See also [`summarize_table(::Val{:storage})`](@ref)
* `build_file` - the filename of the buildable storage table, where each row represents a specification for buildable storage.  See also [`summarize_table(::Val{:build_storage})`](@ref)

# Variables Introduced
* `pcap_stor[stor_idx, yr_idx]` - The discharge power capacity, in MW, of the storage device.
* `pcharge_stor[stor_idx, yr_idx, hr_idx]` - The charge power, in MW, for a given hour.
* `pdischarge_stor[stor_idx, yr_idx, hr_idx]` - The discharged power, in MW, for a given hour.
* `e0_stor[stor_idx]` - The starting charge energy (in MWh) for each interval.

# Constraints Introduced
* `cons_stor_charge_bal[stor_idx, yr_idx, int_idx]` - the charge balancing equation - net charge in each interval is 0
* `cons_stor_charge_max[stor_idx, yr_idx, int_idx, _hr_idx]` - constrain the stored energy in each hour of each interval to be less than the maximum (function of `pcap_stor` and the discharge duration column of the storage table).  Note `_hr_idx` is the index within the interval, not the normal `hr_idx`
* `cons_stor_charge_min[stor_idx, yr_idx, int_idx, _hr_idx]` - constrain the stored energy in each hour of each interval to be greater than zero.  Note `_hr_idx` is the index within the interval, not the normal `hr_idx`
* `cons_pcap_stor_noadd[stor_idx, yr_idx; years[yr_idx] >= storage.year_on[stor_idx]]` - constrain the capacity to be non-increasing after being built. (only in multi-year simulations)
* `cons_pcap_stor_prebuild[stor_idx, yr_idx; years[yr_idx] < storage.year_on[stor_idx]]` - constrain the capacity to be zero before being built. (should only happen in multi-year simulations)
* `cons_pcap_stor_exog[stor_idx, yr_idx]` - constrain the exogenous, unbuilt capacity to equal pcap0 for the first year >= its build year.

# Objective Terms
* `capex_obj_stor` - the capital expenditures to build the storage device, only non-zero in the build year.  (function of `pcap_stor` and `capex`, and `year_on`)
* `fom_stor` - the fixed operation and maintenance costs for the storage device (function of `pcap_stor` and `fom` from the storage table)
* `vom_stor` - the variable operation and maintenance costs for the storage device (function of `pdischarge_stor`, the `vom` column of the storage table, and the hour weights [`get_hour_weights`](@ref))

# Power Balancing Equation
Each storage device can either be on the "gen" side or the "load" side, as specified by the `side` column.
* "gen" side:
    * `pcharge_stor` gets subtracted from `pgen_bus`
    * `pdischarge_stor` gets added to `pgen_bus`
* "load" side:
    * `pcharge_stor` gets added to `plserv_bus`
    * `pdischarge_stor` gets subtracted from `plserv_bus`
"""
struct Storage <: Modification
    name::Symbol
    file::String
    build_file::String
end
function Storage(;name, file, build_file="")
    return Storage(name, file, build_file)
end
export Storage

mod_rank(::Type{<:Storage}) = -3.0

@doc """
    summarize_table(::Val{:storage})

$(table2markdown(summarize_table(Val(:storage))))
"""
function summarize_table(::Val{:storage})
    df = TableSummary()
    push!(df, 
        (:bus_idx, Int64, NA, true, "The index of the `bus` table that the storage device corresponds to"),
        (:status, Bool, NA, false, "Whether or not the storage device is in service"),
        (:build_status, String15, NA, true, "Whether the storage device is `built`, '`new`, or `unbuilt`. All storage devices marked `new` when the storage file is read in will be changed to `built`.  Can also be changed to `retired_exog` or `retired_endog` after the simulation is run.  See [`update_build_status!`](@ref)"),
        (:build_type, AbstractString, NA, true, "Whether the storage device is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:build_id, AbstractString, NA, true, "Identifier of the build row.  For pre-existing storage devices not specified in the build file, this is usually left empty"),
        (:year_on, YearString, Year, true, "The first year of operation for the storage device. (For new devices this is also the year it was built)"),
        (:econ_life, Float64, NumYears, true, "The number of years in the economic lifetime of the storage device."),
        (:year_off, YearString, Year, true, "The first year that the storage unit is no longer operating in the simulation, computed from the simulation.  Leave as y9999 if an existing storage unit that has not been retired in the simulation yet."),
        (:year_shutdown, YearString, Year, true, "The forced (exogenous) shutdown year for the storage unit."),
        (:pcap_inv, Float64, MWCapacity, true, "Original invested nameplate power generation capacity for the storage device.  This is the original invested capacity of exogenously built storage devices (even if there have been retirements ), and the original invested capacity in year_on for endogenously built storage devices."),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power discharge capacity for the storage device"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power discharge capacity of the storage device (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power discharge capacity of the storage device"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of energy discharged"),
        (:fom, Float64, DollarsPerMWCapacityPerHour, true, "Hourly fixed operation and maintenance cost for a MW of discharge capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacity, true, "Hourly capital expenditures for a MW of discharge capacity"),
        (:duration_discharge, Float64, Hours, true, "Number of hours to fully discharge the storage device, from full."),
        (:duration_charge, Float64, Hours, false, "Number of hours to fully charge the empty storage device from empty. (Defaults to equal `duration_discharge`)"),
        (:storage_efficiency, Float64, MWhDischargedPerMWhCharged, true, "The round-trip efficiency of the battery."),
        (:side, String, NA, true, "The side of the power balance equation to add the charging/discharging to.  Can be \"gen\" or \"load\""),
        (:hour_groupby, String, NA, true, "The column of the `hours` table to group by.  For example `day`"),
        (:hour_duration, String, NA, true, "The column of the `hours` table specifying the duration of each representatibe hour"),
        (:hour_order, String, NA, true, "The column of the `hours` table specifying the sequence of the hours."),
    )
end

@doc """
    summarize_table(::Val{:build_storage})

$(table2markdown(summarize_table(Val(:build_storage))))
"""
function summarize_table(::Val{:build_storage})
    df = TableSummary()
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:status, Bool, NA, false, "Whether or not the storage device is in service"),
        (:build_status, String15, NA, true, "Whether the storage device is `built`, '`new`, or `unbuilt`. All storage devices marked `new` when the storage file is read in will be changed to `built`.  Can also be changed to `retired_exog` or `retired_endog` after the simulation is run.  See [`update_build_status!`](@ref)"),
        (:build_type, AbstractString, NA, true, "Whether the storage device is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:build_id, AbstractString, NA, true, "Identifier of the build row.  Each storage device made using this build spec will inherit this `build_id`"),
        (:year_on, YearString, Year, true, "The first year of operation for the storage device. (For new devices this is also the year it was built)"),
        (:econ_life, Float64, NumYears, true, "The number of years in the economic lifetime of the storage device."),
        (:age_shutdown, Float64, NumYears, true, "The age at which the storage device is no longer operating.  I.e. if `year_on` = `y2030` and `age_shutdown` = `20`, then capacity will be 0 in `y2040`."),
        (:year_on_min, YearString, Year, true, "The first year in which a storage device can be built/come online (inclusive). Storage device with no restriction and exogenously built gens will be left blank"),
        (:year_on_max, YearString, Year, true, "The last year in which a storage device can be built/come online (inclusive). Storage devices with no restriction and exogenously built gens will be left blank"),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power discharge capacity for the storage device"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power discharge capacity of the storage device (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power discharge capacity of the storage device"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of energy discharged"),
        (:fom, Float64, DollarsPerMWCapacityPerHour, true, "Hourly fixed operation and maintenance cost for a MW of discharge capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacity, true, "Hourly capital expenditures for a MW of discharge capacity"),
        (:duration_discharge, Float64, Hours, true, "Number of hours to fully discharge the storage device, from full."),
        (:duration_charge, Float64, Hours, false, "Number of hours to fully charge the empty storage device from empty. (Defaults to equal `duration_discharge`)"),
        (:storage_efficiency, Float64, MWhDischargedPerMWhCharged, true, "The round-trip efficiency of the device."),
        (:side, String, NA, true, "The side of the power balance equation to add the charging/discharging to.  Can be \"gen\" or \"load\""),
        (:hour_groupby, String, NA, true, "The column of the `hours` table to group by.  For example `day`"),
        (:hour_duration, String, NA, true, "The column of the `hours` table specifying the duration of each representatibe hour"),
        (:hour_order, String, NA, true, "The column of the `hours` table specifying the sequence of the hours."),
    )
end

function modify_raw_data!(mod::Storage, config, data)
    config[:storage_file] = mod.file
    isempty(mod.build_file) || (config[:build_storage_file] = mod.build_file)

    read_table!(config, data, :storage_file=>:storage)
    read_table!(config, data, :build_storage_file=>:build_storage, optional=true)
end

function modify_setup_data!(mod::Storage, config, data)
    storage = get_table(data, :storage)
    bus = get_table(data, :bus)
    hours = get_table(data, :hours)
    years = get_years(data)

    data[:storage_table_original_cols] = propertynames(storage)

    add_buildable_storage!(config, data)

    ### Add the following columns to the storage table:
    # num_intervals: number of time intervals for storage of this device
    # duration_charge (only if not provided)
    # intervals: each entry is a Vector{Vector{Int64}} - vector of vectors of hour indices
    # interval_hour_duration: each entry is a Dict{Int64, Float64} - lookup of hour index to duration.

    if !hasproperty(storage, :duration_charge)
        storage.duration_charge = copy(storage.duration_discharge)
    end

    ### Create capex_obj (the capex used in the optimization/objective function)
    # set to capex for unbuilt generators in the year_on
    # set to 0 for already built capacity because capacity expansion isn't considered for existing generators
    add_table_col!(data, :storage, :capex_obj, Container[ByNothing(0.0) for i in 1:nrow(storage)], DollarsPerMWBuiltCapacity, "Hourly capital expenditures that is passed into the objective function. 0 for already built capacity")

    for row in eachrow(storage)
        row.build_status == "unbuilt" || continue
        row.capex_obj = ByYear([row.capex * (year >= row.year_on && year < add_to_year(row.year_on, row.econ_life)) for year in years])
    end

    storage.num_intervals = fill(0, nrow(storage))
    storage.intervals = fill(Vector{Int64}[], nrow(storage))
    storage.interval_hour_duration = fill(Vector{Float64}(), nrow(storage))

    # Add num_intervals
    gdf_storage = groupby(storage, [:hour_groupby, :hour_duration, :hour_order])

    for k in keys(gdf_storage)
        hour_groupby, hour_duration, hour_order = k

        sdf_storage = gdf_storage[k]
        gdf_hours = groupby(hours, hour_groupby)

        sdf_storage.interval_hour_duration .= Ref(hours[!, hour_duration])
        sdf_storage.num_intervals .= length(gdf_hours)

        intervals = Vector{Int64}[]
        for hk in keys(gdf_hours)
            sdf_hours = gdf_hours[hk]
            
            # Check to see if the hour durations are weighted in proportion to the hour weights
            weight_hours = sdf_hours.hours ./ (sum(sdf_hours.hours))
            weight_durations = sdf_hours[!, hour_duration] ./ sum(sdf_hours[!, hour_duration])
            @assert all(i -> weight_hours[i] ≈ weight_durations[i], eachindex(weight_hours)) "Hour durations for hours grouped by $(hour_groupby) must be proportional to the `hours` column of the `hours` table."

            hour_idxs = getfield(sdf_hours, :rows)
            hour_idxs_sorting = sortperm(sdf_hours, hour_order)
            hour_idxs_sorted = hour_idxs[hour_idxs_sorting]
            push!(intervals, hour_idxs_sorted)
        end

        sdf_storage.intervals .= Ref(intervals)
    end

    ### Map bus characteristics to storage
    names_before = propertynames(storage)
    leftjoin!(storage, bus, on=:bus_idx)
    select!(storage, Not(:plnom))
    disallowmissing!(storage)
    names_after = propertynames(storage)

    for name in names_after
        name in names_before && continue
        add_table_col!(data, :storage, name, storage[!,name], get_table_col_unit(data, :bus, name), get_table_col_description(data, :bus, name), warn_overwrite=false)
    end
end

"""
    add_buildable_storage!(config, data)

Add buildable storage from `build_storage` table to `storage` table, if the `build_storage` table exists
"""
function add_buildable_storage!(config, data)
    haskey(data, :build_storage) || return nothing

    storage =       get_table(data, :storage)
    build_storage = get_table(data, :build_storage)
    bus =           get_table(data, :bus)

    spec_names = filter!(
        !in((:bus_idx, :year_off, :year_shutdown, :pcap_inv)),
        propertynames(storage)
    )
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
                    new_row[:year_shutdown] = add_to_year(year, spec_row.age_shutdown)
                    new_row[:year_off] = "y9999"
                    new_row[:pcap_inv] = 0.0
                    push!(storage, new_row, promote=true)
                end
            else # exogenous
                @assert !isempty(spec_row.year_on) "Exogenous storage devices must have a specified year_on value"

                # Skip this build if it is after the simulation
                spec_row.year_on > last(years) && continue

                # for exogenously specified storage, only one storage device is created with the specified year_on
                new_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                new_row[:year_shutdown] = add_to_year(spec_row.year_on, spec_row.age_shutdown)
                new_row[:year_off] = "y9999"
                new_row[:pcap_inv] = 0.0

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
    hour_weights = get_hour_weights(data)

    ### Create Variables
    # Power discharge capacity
    @variable(model, 
        pcap_stor[stor_idx in axes(storage,1), yr_idx in 1:nyr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx]
    )

    # Power discharged
    @variable(model,
        pdischarge_stor[stor_idx in axes(storage, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx]
    )

    # Power charged - upper bound depends on ratio of duration for charge/discharge durations.
    @variable(model,
        pcharge_stor[stor_idx in axes(storage, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx]  * storage.duration_charge[stor_idx] / (storage.duration_discharge[stor_idx] * storage.storage_efficiency[stor_idx])
    )

    # initial energy stored in the device
    @variable(model,
        e0_stor[stor_idx in axes(storage, 1)],
        lower_bound = 0,
        upper_bound = storage.pcap_max[stor_idx] * storage.duration_discharge[stor_idx]
    )

    ### Create Constraints
    # Constrain start and end of each device's intervals to be the same
    @constraint(model,
        cons_stor_charge_bal[stor_idx in axes(storage,1), yr_idx in 1:nyr, int_idx in 1:storage.num_intervals[stor_idx]],
        sum(
            (
                pdischarge_stor[stor_idx, yr_idx, hr_idx] - 
                pcharge_stor[stor_idx, yr_idx, hr_idx] * storage.storage_efficiency[stor_idx]
            ) * 
            storage.interval_hour_duration[stor_idx][hr_idx] 
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
                pcharge_stor[stor_idx, yr_idx, hr_idx] * storage.storage_efficiency[stor_idx]
            ) *
            storage.interval_hour_duration[stor_idx][hr_idx]
            for hr_idx in storage.intervals[stor_idx][int_idx][1:_hr_idx]
        # ) <= pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
        )  + e0_stor[stor_idx] <= pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
    )
    
    # Constrain lower limit on charge
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
                pcharge_stor[stor_idx, yr_idx, hr_idx] * storage.storage_efficiency[stor_idx]
            ) * 
            storage.interval_hour_duration[stor_idx][hr_idx] 
            for hr_idx in storage.intervals[stor_idx][int_idx][1:_hr_idx]
        # ) >= 0 # -pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
        ) + e0_stor[stor_idx] >= 0 # -pcap_stor[stor_idx, yr_idx] * storage.duration_discharge[stor_idx]
    )

    ### Add build constraints for endogenous batteries
    add_build_constraints!(data, model, :storage, :pcap_stor)
    
    ### Add charge/discharge to appropriate expressions in power balancing equation
    plserv_bus = model[:plserv_bus]
    pgen_bus = model[:pgen_bus]
    for (stor_idx, row) in enumerate(eachrow(storage))
        bus_idx = row.bus_idx
        if row.side == "load"
            for yr_idx in 1:nyr, hr_idx in 1:nhr
                add_to_expression!(plserv_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx], -1)
                add_to_expression!(plserv_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], 1)
            end
        else # row.side == "gen"
            for yr_idx in 1:nyr, hr_idx in 1:nhr
                add_to_expression!(pgen_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx])
                add_to_expression!(pgen_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], -1)
            end
        end
    end

    ### Add Costs to objective function terms: vom, fom, capex.
    @expression(model,
        vom_stor[yr_idx in 1:nyr],
        sum(
            hour_weights[hr_idx] * pdischarge_stor[stor_idx, yr_idx, hr_idx] * get_table_num(data, :storage, :vom, stor_idx, yr_idx, hr_idx)
            for stor_idx in axes(storage,1), hr_idx in 1:nhr
        )
    )

    @expression(model,
        fom_stor[yr_idx in 1:nyr],
        sum(
            pcap_stor[stor_idx, yr_idx] * get_table_num(data, :storage, :fom, stor_idx, yr_idx, :)
            for stor_idx in axes(storage,1)
        )
    )

    

    @expression(model,
        pcap_stor_inv_sim[stor_idx in axes(storage,1)],
        begin
            storage.build_status[stor_idx] == "unbuilt" || return 0.0
            year_on = storage.year_on[stor_idx]
            year_on > last(years) && return 0.0
            yr_idx_on = findfirst(>=(year_on), years)
            return pcap_stor[stor_idx, yr_idx_on]
        end
    )

    @expression(model,
        capex_obj_stor[yr_idx in 1:nyr],
        sum(
            pcap_stor_inv_sim[stor_idx] * get_table_num(data, :storage, :capex_obj, stor_idx, yr_idx, :)
            for stor_idx in axes(storage,1)
        )
    )

    add_obj_exp!(data, model, PerMWhGen(), :vom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCap(), :fom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCapInv(), :capex_obj_stor, oper = +) 
end

"""
    modify_results!(mod::Storage, config, data)

Modify battery results.  Add columns to the `storage` table for:
* `pcap` - discharge capacity of the storage device, in MW.
* `pcharge` - the charging rate, in MW
* `pdischarge` - the discharging rate, in MW
* `echarge` - the energy charged in each representative hour (including losses)
* `edischarge` - Energy that was discharged by the storage device
* `ploss` - Power that was lost by the battery, counted as served load equal to `pcharge * (1-η)`
* `eloss` - Energy that was lost by the battery, counted as served load
* `pcap_inv_sim` - power discharge capacity invested in the sim
* `ecap_inv_sim` - 8760 * pcap_inv_sim

Also saves the updated storage table via [`save_updated_storage_table`](@ref).
"""
function modify_results!(mod::Storage, config, data)
    storage = get_table(data, :storage)
    pcap_stor = get_raw_result(data, :pcap_stor)::Matrix{Float64}
    pcharge_stor = get_raw_result(data, :pcharge_stor)::Array{Float64, 3}
    pdischarge_stor = get_raw_result(data, :pdischarge_stor)::Array{Float64, 3}
    hours_per_year = sum(get_hour_weights(data))

    pcap_inv_sim = get_raw_result(data, :pcap_stor_inv_sim)::Vector{Float64}
    ecap_inv_sim = pcap_inv_sim .* hours_per_year

    echarge_stor = weight_hourly(data, pcharge_stor)
    edischarge_stor = weight_hourly(data, pdischarge_stor)

    add_table_col!(data, :storage, :pcap, pcap_stor, MWCapacity, "Power Discharge capacity of the storage device")
    add_table_col!(data, :storage, :pcharge, pcharge_stor, MWCharged, "Rate of charging, in MW")
    add_table_col!(data, :storage, :pdischarge, pcharge_stor, MWDischarged, "Rate of discharging, in MW")
    add_table_col!(data, :storage, :echarge, echarge_stor, MWhCharged, "Energy that went into charging the storage device (includes any round-trip storage losses)")
    add_table_col!(data, :storage, :edischarge, edischarge_stor, MWhDischarged, "Energy that was discharged by the storage device")
    add_table_col!(data, :storage, :pcap_inv_sim, pcap_inv_sim, MWCapacity, "Total power discharge capacity that was invested for the generator during the sim.  (single value).  Still the same even after retirement")
    add_table_col!(data, :storage, :ecap_inv_sim, ecap_inv_sim, MWhCapacity, "Total yearly energy discharge capacity that was invested for the generator during the sim. (pcap_inv_sim * hours per year)  (single value).  Still the same even after retirement")


    add_results_formula!(data, :storage, :pcap_total, "AverageYearly(pcap)", MWCapacity, "Total discharge power capacity (if multiple years given, calculates the average)")
    add_results_formula!(data, :storage, :echarge_total, "SumHourly(echarge)", MWhCharged, "Total energy charged")
    add_results_formula!(data, :storage, :edischarge_total, "SumHourly(edischarge)", MWhDischarged, "Total energy discharged")

    transform!(storage,
        [:pcharge, :storage_efficiency] => ByRow((p,η) -> p * (1 - η)) => :ploss
    )

    add_table_col!(data, :storage, :ploss, storage.ploss, MWServed, "Power that was lost by the battery, counted as served load equal to `pcharge * (1-η)`")
    eloss = weight_hourly(data, storage.ploss)
    add_table_col!(data, :storage, :eloss, eloss, MWhServed, "Energy that was lost by the battery, counted as served load")

    add_results_formula!(data, :storage, :eloss_total, "SumHourly(eloss)", MWhLoss, "Total energy loss")

    update_build_status!(config, data, :storage)

    save_updated_storage_table(config, data)
end
export modify_results!

"""
    save_updated_storage_table(config, data)

Saves the updated storage table with any additional storage units, updated capacities, etc.
"""
function save_updated_storage_table(config, data)
    storage = get_table(data, :storage)
    original_cols = data[:storage_table_original_cols]

    # Grab only the original columns, and return to their original values for any that may have been modified.
    storage_tmp = storage[:, original_cols]
    for col_name in original_cols
        col = storage_tmp[!, col_name]
        if eltype(col) <: Container
            storage_tmp[!, col_name] = get_original.(storage_tmp[!, col_name])
        end
    end

    # Update pcap0 to be the last value of pcap
    storage_tmp.pcap0 = last.(storage.pcap)

    storage_tmp.pcap_inv = map(eachrow(storage)) do row
        row.build_status == "new" || return row.pcap_inv
        return row.pcap_inv_sim
    end

    # Filter anything with capacity below the threshold
    thresh = config[:pcap_retirement_threshold]
    filter!(:pcap0 => >(thresh), storage_tmp)
    storage_tmp.pcap_max = copy(storage_tmp.pcap0)


    # Combine storage devices that are the same
    gdf = groupby(storage_tmp, Not(:pcap0))
    storage_tmp_combined = combine(gdf,
        :pcap0 => sum => :pcap0
    )
    storage_tmp_combined.pcap_max = copy(storage_tmp_combined.pcap0)

    CSV.write(get_out_path(config, "storage.csv"), storage_tmp_combined)
    return nothing
end
export save_updated_storage_table