"""
    mutable struct Storage <: Modification

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
mutable struct Storage <: Modification
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
        (:year_unbuilt,YearString, Year, false, "The latest year the generator was known not to be built.  Defaults to year_on - 1.  Used for past capex accounting."),
        (:econ_life, Float64, NumYears, true, "The number of years in the economic lifetime of the storage device."),
        (:year_off, YearString, Year, true, "The first year that the storage unit is no longer operating in the simulation, computed from the simulation.  Leave as y9999 if an existing storage unit that has not been retired in the simulation yet."),
        (:year_shutdown, YearString, Year, true, "The forced (exogenous) shutdown year for the storage unit."),
        (:pcap_inv, Float64, MWCapacity, true, "Original invested nameplate power generation capacity for the storage device.  This is the original invested capacity of exogenously built storage devices (even if there have been retirements ), and the original invested capacity in year_on for endogenously built storage devices."),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power discharge capacity for the storage device"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power discharge capacity of the storage device (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power discharge capacity of the storage device"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of energy discharged"),
        (:fom, Float64, DollarsPerMWCapacityPerHour, true, "Hourly fixed operation and maintenance cost for a MW of discharge capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for a MW of discharge capacity"),
        (:transmission_capex, Float64, DollarsPerMWBuiltCapacityPerHour, false, "Hourly capital expenditures for the transmission supporting a MW of discharge capacity"),
        (:routine_capex, Float64, DollarsPerMWCapacityPerHour, true, "Routine capital expenditures for a MW of discharge capacity"),
        (:past_invest_cost, Float64, DollarsPerMWCapacityPerHour, false, "Investment costs per MW of initial capacity per hour, for past investments"),
        (:past_invest_subsidy, Float64, DollarsPerMWCapacityPerHour, false, "Investment subsidies from govt. per MW of initial capacity per hour, for past investments"),
        (:duration_discharge, Float64, Hours, true, "Number of hours to fully discharge the storage device, from full."),
        (:duration_charge, Float64, Hours, false, "Number of hours to fully charge the empty storage device from empty. (Defaults to equal `duration_discharge`)"),
        (:storage_efficiency, Float64, MWhDischargedPerMWhCharged, true, "The round-trip efficiency of the battery."),
        (:side, String, NA, true, "The side of the power balance equation to add the charging/discharging to.  Can be \"gen\" or \"load\""),
        (:hour_groupby, String, NA, true, "The column of the `hours` table to group by.  For example `day`"),
        (:hour_duration, String, NA, true, "The column of the `hours` table specifying the duration of each representatibe hour"),
        (:hour_order, String, NA, true, "The column of the `hours` table specifying the sequence of the hours."),
        (:reg_factor, Float64, NA, true, "The percentage of power that dispatches to a cost-of-service regulated market"),
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
        (:capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for a MW of discharge capacity"),
        (:transmission_capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for the transmission supporting a MW of discharge capacity"),
        (:routine_capex, Float64, DollarsPerMWCapacityPerHour, true, "Routing capital expenditures for a MW of discharge capacity"),
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

    # Set up year_unbuilt before setting up new gens.  Plus we will want to save the column
    hasproperty(storage, :year_unbuilt) || (storage.year_unbuilt = map(y->add_to_year(y, -1), storage.year_on))
    
    # Set up past capex cost and subsidy to be for built generators only
    # Make columns as needed
    hasproperty(storage, :past_invest_cost) || (storage.past_invest_cost = zeros(nrow(storage)))
    hasproperty(storage, :past_invest_subsidy) || (storage.past_invest_subsidy = zeros(nrow(storage)))
    z = Container(0.0)
    _to_container!(storage, :past_invest_cost)
    _to_container!(storage, :past_invest_subsidy)
    for (idx_g, g) in enumerate(eachrow(storage))
        if g.build_status == "unbuilt"
            if any(!=(0), g.past_invest_cost) || any(!=(0), g.past_invest_subsidy)
                @warn "Generator $idx_g is unbuilt yet has past capex cost/subsidy, setting to zero"
                g.past_invest_cost = z
                g.past_invest_subsidy = z
            end
        else
            past_invest_percentages = get_past_invest_percentages(g, years)
            g.past_invest_cost = g.past_invest_cost .* past_invest_percentages
            g.past_invest_subsidy = g.past_invest_subsidy .* past_invest_percentages
        end
    end

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
    # set to capex for unbuilt storage units in the year_on
    # set to 0 for already built capacity because capacity expansion isn't considered for existing storage units
    add_table_col!(data, :storage, :capex_obj, Container[ByNothing(0.0) for i in 1:nrow(storage)], DollarsPerMWBuiltCapacityPerHour, "Hourly capital expenditures that is passed into the objective function. 0 for already built capacity")
    add_table_col!(data, :storage, :transmission_capex_obj, Container[ByNothing(0.0) for i in 1:nrow(storage)], DollarsPerMWBuiltCapacityPerHour, "Hourly transmission capital expenditures that is passed into the objective function. 0 for already built capacity")

    for row in eachrow(storage)
        row.build_status == "unbuilt" || continue
        row.capex_obj = ByYear([row.capex * (year >= row.year_on && year < add_to_year(row.year_on, row.econ_life)) for year in years])
        row.transmission_capex_obj = ByYear([row.transmission_capex * (year >= row.year_on && year < add_to_year(row.year_on, row.econ_life)) for year in years])
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
    leftjoin!(storage, select(bus, Not(:reg_factor)), on=:bus_idx)
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

    # Filter any already-built exogenous storage units
    filter!(build_storage) do row
        row.build_type == "exog" && row.year_on >= config[:year_gen_data] && return false
        return true
    end

    spec_names = filter!(
        !in((:bus_idx, :reg_factor, :year_off, :year_shutdown, :pcap_inv, :year_unbuilt, :past_invest_cost, :past_invest_subsidy)),
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
                for (yr_idx, year) in enumerate(years)
                    year < year_on_min && continue
                    year > year_on_max && continue

                    # Make row to add to the storage table
                    new_row = Dict(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                    new_row[:year_on] = year
                    new_row[:year_unbuilt] = get(years, yr_idx - 1, config[:year_gen_data])
                    new_row[:year_shutdown] = "y9999" #add_to_year(year, spec_row.age_shutdown)
                    new_row[:year_off] = "y9999"
                    new_row[:pcap_inv] = 0.0
                    new_row[:past_invest_cost] = Container(0.0)
                    new_row[:past_invest_subsidy] = Container(0.0)

                    # Add reg_factor if needed
                    hasproperty(storage, :reg_factor) && (new_row[:reg_factor] = bus.reg_factor[bus_idx])

                    push!(storage, new_row, promote=true)
                end
            else # exogenous
                @assert !isempty(spec_row.year_on) "Exogenous storage devices must have a specified year_on value"

                # Skip this build if it is after the simulation
                spec_row.year_on > last(years) && continue

                # for exogenously specified storage, only one storage device is created with the specified year_on
                new_row = Dict{}(:bus_idx => bus_idx, (spec_name=>spec_row[spec_name] for spec_name in spec_names)...)
                
                new_row[:year_shutdown] = "y9999" #add_to_year(spec_row.year_on, spec_row.age_shutdown)
                new_row[:year_off] = "y9999"
                new_row[:pcap_inv] = 0.0
                new_row[:year_unbuilt] = add_to_year(new_row[:year_on], -1)
                new_row[:past_invest_cost] = Container(0.0)
                new_row[:past_invest_subsidy] = Container(0.0)

                # Add reg_factor if needed
                hasproperty(storage, :reg_factor) && (new_row[:reg_factor] = bus.reg_factor[bus_idx])

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
        routine_capex_stor[yr_idx in 1:nyr],
        sum(
            pcap_stor[stor_idx, yr_idx] * get_table_num(data, :storage, :routine_capex, stor_idx, yr_idx, :)
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
    @expression(model,
        transmission_capex_obj_stor[yr_idx in 1:nyr],
        sum(
            pcap_stor_inv_sim[stor_idx] * get_table_num(data, :storage, :transmission_capex_obj, stor_idx, yr_idx, :)
            for stor_idx in axes(storage,1)
        )
    )
    

    add_obj_exp!(data, model, PerMWhGen(), :vom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCap(), :fom_stor, oper = +)
    add_obj_exp!(data, model, PerMWCap(), :routine_capex_stor, oper = +)
    add_obj_exp!(data, model, PerMWCapInv(), :capex_obj_stor, oper = +) 
    add_obj_exp!(data, model, PerMWCapInv(), :transmission_capex_obj_stor, oper = +) 

    # Add some results so that policy mods can add to the investment subsidy
    add_results_formula!(data, :storage, :invest_subsidy, "0", Dollars, "Investment subsidies to go to the producer")
    add_results_formula!(data, :storage, :invest_subsidy_permw_perhr, "invest_subsidy / ecap_inv_total", DollarsPerMWCapacityPerHour, "Investment subsidies per MW per hour")
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
    lmp_bus = get_table_col(data, :bus, :lmp_elserv)
    bus_idxs = storage.bus_idx::Vector{Int64}
    lmp_stor = [lmp_bus[i] for i in bus_idxs]

    add_table_col!(data, :storage, :pcap, pcap_stor, MWCapacity, "Power Discharge capacity of the storage device")
    add_table_col!(data, :storage, :pcharge, pcharge_stor, MWCharged, "Rate of charging, in MW")
    add_table_col!(data, :storage, :pdischarge, pcharge_stor, MWDischarged, "Rate of discharging, in MW")
    add_table_col!(data, :storage, :echarge, echarge_stor, MWhCharged, "Energy that went into charging the storage device (includes any round-trip storage losses)")
    add_table_col!(data, :storage, :edischarge, edischarge_stor, MWhDischarged, "Energy that was discharged by the storage device")
    add_table_col!(data, :storage, :pcap_inv_sim, pcap_inv_sim, MWCapacity, "Total power discharge capacity that was invested for the storage unit during the sim.  (single value).  Still the same even after retirement")
    add_table_col!(data, :storage, :ecap_inv_sim, ecap_inv_sim, MWhCapacity, "Total yearly energy discharge capacity that was invested for the storage unit during the sim. (pcap_inv_sim * hours per year)  (single value).  Still the same even after retirement")
    add_table_col!(data, :storage, :lmp_e, lmp_stor, DollarsPerMWhDischarged, "Locational marginal price of electricity")

    # Update pcap_inv
    storage.pcap_inv = max.(storage.pcap_inv, storage.pcap_inv_sim)

    transform!(storage,
        [:pcharge, :storage_efficiency] => ByRow((p,η) -> p * (1 - η)) => :ploss
    )

    add_table_col!(data, :storage, :ploss, storage.ploss, MWServed, "Power that was lost by the battery, counted as served load equal to `pcharge * (1-η)`")
    eloss = weight_hourly(data, storage.ploss)
    add_table_col!(data, :storage, :eloss, eloss, MWhServed, "Energy that was lost by the battery, counted as served load")

    add_results_formula!(data, :storage, :pcap_total, "AverageYearly(pcap)", MWCapacity, "Total discharge power capacity (if multiple years given, calculates the average)")
    add_results_formula!(data, :storage, :echarge_total, "SumHourly(echarge)", MWhCharged, "Total energy charged")
    add_results_formula!(data, :storage, :edischarge_total, "SumHourly(edischarge)", MWhDischarged, "Total energy discharged")
    add_results_formula!(data, :storage, :eloss_total, "SumHourly(eloss)", MWhLoss, "Total energy loss")
    add_results_formula!(data, :storage, :ecap_inv_total, "SumHourlyWeighted(pcap_inv)", MWhCapacity, "Total invested energy discharge capacity over the time period given.")
    
    # Add electricity cost and revenue
    add_results_formula!(data, :storage, :electricity_revenue, "SumHourly(lmp_e, edischarge)", Dollars, "Revenue from discharging electricity to the grid")
    add_results_formula!(data, :storage, :electricity_cost, "SumHourly(lmp_e, echarge)", Dollars, "Cost of electricity to charge the storage units")
    
    # Add production costs
    add_results_formula!(data, :storage, :vom_cost, "SumHourly(vom, edischarge)", Dollars, "Total variable operation and maintenance cost for discharging energy")
    add_results_formula!(data, :storage, :vom_per_mwh, "vom_cost / edischarge_total", DollarsPerMWhDischarged, "Average variable operation and maintenance cost for discharging 1 MWh of energy")
    add_results_formula!(data, :storage, :fom_cost, "SumHourlyWeighted(fom, pcap)", Dollars, "Total fixed operation and maintenance cost paid, in dollars")
    add_results_formula!(data, :storage, :fom_per_mwh, "fom_cost / edischarge_total", DollarsPerMWhDischarged, "Average fixed operation and maintenance cost for discharging 1 MWh of energy")
    add_results_formula!(data, :storage, :routine_capex_cost, "SumHourlyWeighted(routine_capex, pcap)", Dollars, "Total routine capex cost paid, in dollars")
    add_results_formula!(data, :storage, :routine_capex_per_mwh, "fom_cost / edischarge_total", DollarsPerMWhDischarged, "Average routine capex cost for discharging 1 MWh of energy")
    add_results_formula!(data, :storage, :capex_cost, "SumYearly(capex_obj, ecap_inv_sim)", Dollars, "Total annualized capital expenditures paid, in dollars")
    add_results_formula!(data, :storage, :capex_per_mwh, "capex_cost / edischarge_total", DollarsPerMWhDischarged, "Average capital cost for discharging 1 MWh of energy")
    add_results_formula!(data, :storage, :transmission_capex_cost, "SumYearly(transmission_capex_obj, ecap_inv_sim)", Dollars, "Total annualized transmission capital expenditures paid, in dollars")
    add_results_formula!(data, :storage, :transmission_capex_per_mwh, "transmission_capex_cost / edischarge_total", DollarsPerMWhDischarged, "Average transmission capital cost for discharging 1 MWh of energy")
    add_results_formula!(data, :storage, :invest_cost, "transmission_capex_cost + capex_cost", Dollars, "Total annualized investment costs, in dollars")
    add_results_formula!(data, :storage, :invest_cost_permw_perhr, "invest_cost / ecap_inv_total", DollarsPerMWCapacityPerHour, "Average investment cost per MW of invested capacity per hour")    

    # Variable costs
    add_results_formula!(data, :storage, :variable_cost, "vom_cost", Dollars, "Total variable costs for operation, including vom.  One day if storage has fuel, this could include fuel also")
    add_results_formula!(data, :storage, :variable_cost_per_mwh, "variable_cost / edischarge_total", DollarsPerMWhDischarged, "Average variable costs for operation, including vom, for discharging 1MWh from storage.  One day if storage has fuel, this could include fuel also")
    add_results_formula!(data, :storage, :production_subsidy, "0", Dollars, "Total production subsidy for storage")
    add_results_formula!(data, :storage, :production_subsidy_per_mwh, "production_subsidy / edischarge_total", DollarsPerMWhDischarged, "Average production subsidy for discharging 1 MWh from storage")
    add_results_formula!(data, :storage, :past_invest_cost_total, "SumHourlyWeighted(past_invest_cost, pcap_inv)", Dollars, "Past investment cost for storage")
    add_results_formula!(data, :storage, :past_invest_subsidy_total, "SumHourlyWeighted(past_invest_subsidy, pcap_inv)", Dollars, "Past investment subsidy for storage")
    add_results_formula!(data, :storage, :net_variable_cost, "variable_cost - production_subsidy", Dollars, "Net variable costs for storage")
    add_results_formula!(data, :storage, :net_variable_cost_per_mwh, "net_variable_cost / edischarge_total", DollarsPerMWhDischarged, "Average net variable costs per MWh of discharged energy")

    # Fixed costs
    add_results_formula!(data, :storage, :fixed_cost, "capex_cost + fom_cost", Dollars, "Total fixed costs including capex and fom costs")
    add_results_formula!(data, :storage, :fixed_cost_permw_perhr, "fixed_cost / ecap_total", DollarsPerMWCapacityPerHour, "Fixed costs, per MW per hour")
    add_results_formula!(data, :storage, :net_fixed_cost, "fixed_cost - invest_subsidy", Dollars, "Fixed costs minus investment subsidies")
    add_results_formula!(data, :storage, :net_fixed_cost_permw_perhr, "net_fixed_cost / ecap_total", DollarsPerMWCapacityPerHour, "Average net fixed cost per MW per hour.")

    # Production costs
    add_results_formula!(data, :storage, :production_cost, "variable_cost + fixed_cost", Dollars, "Cost of production, includes fixed and variable costs but not energy cost")
    add_results_formula!(data, :storage, :production_cost_per_mwh, "production_cost / edischarge_total", DollarsPerMWhDischarged, "Average cost of production for a MWh of energy discharge, including variable and fixed costs but not energy cost")
    add_results_formula!(data, :storage, :net_production_cost, "net_variable_cost + net_fixed_cost", Dollars, "Net cost of production, includes fixed and variable costs and investment and production subsidies, but not energy cost")
    add_results_formula!(data, :storage, :net_production_cost_per_mwh, "net_production_cost / edischarge_total", DollarsPerMWhDischarged, "Average net cost of discharging 1 MWh of energy")
    
    # Policy costs
    add_results_formula!(data, :storage, :pol_cost, "-invest_subsidy - production_subsidy", Dollars, "Cost from all policy types")
    add_results_formula!(data, :storage, :pol_cost_per_mwh, "pol_cost / edischarge_total", DollarsPerMWhDischarged, "Average policy cost per MWh of discharged energy")
    add_results_formula!(data, :storage, :government_revenue, "- invest_subsidy - production_subsidy - past_invest_subsidy_total", Dollars, "Government revenue earned from storage of energy")
    add_results_formula!(data, :storage, :going_forward_cost, "production_cost + pol_cost", Dollars, "Total cost of production and policies")
    add_results_formula!(data, :storage, :total_cost_prelim, "going_forward_cost + past_invest_cost_total - past_invest_subsidy_total", Dollars, "Total cost of production, including  going_forward_cost, and past investment cost and subsidy.")
    add_results_formula!(data, :storage, :net_total_revenue_prelim, "electricity_revenue - electricity_cost - total_cost_prelim", Dollars, "Preliminary net total revenue, including electricity costs/revenue and total cost, before adjusting for cost-of-service rebates")
    add_results_formula!(data, :storage, :cost_of_service_rebate, "CostOfServiceRebate(storage)", Dollars, "This is a specially calculated result, which is the sum of net_total_revenue_prelim * reg_factor for each generator")
    add_results_formula!(data, :storage, :total_cost, "total_cost_prelim + cost_of_service_rebate", Dollars, "The total cost after adjusting for the cost of service")
    add_results_formula!(data, :storage, :net_total_revenue, "net_total_revenue_prelim - cost_of_service_rebate", Dollars, "Net total revenue after adjusting for the cost-of-service rebate")
    add_results_formula!(data, :storage, :net_going_forward_revenue, "electricity_revenue - net_variable_cost - cost_of_service_rebate", Dollars, "Net going forward revenue, including electricity revenue minus going forward cost")

    # Update Welfare
    # Producer welfare
    add_welfare_term!(data, :producer, :storage, :net_total_revenue_prelim, +)
    add_welfare_term!(data, :producer, :storage, :cost_of_service_rebate, -)

    # Consumer welfare
    add_welfare_term!(data, :consumer, :storage, :cost_of_service_rebate, +)

    # Government revenue
    add_welfare_term!(data, :govermnent, :storage, :government_revenue, +)

    # Update and save the storage table
    update_build_status!(config, data, :storage)
    save_updated_storage_table(config, data)

    if issequential(get_iterator(config))
        mod.file = get_out_path(config, "storage.csv")
    end
end
export modify_results!

"""
    save_updated_storage_table(config, data)

Saves the updated storage table with any additional storage units, updated capacities, etc.
"""
function save_updated_storage_table(config, data)
    years = get_years(data)
    nyr = get_num_years(data)
    year_end = last(years)

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

    # Gather the past investment costs and subsidies
    for i in 1:nrow(storage_tmp)
        storage_tmp.build_status[i] == "new" || continue
        @info "updating the past investment cost/subsidy for $i"
        storage_tmp.past_invest_cost[i] =    maximum(yr_idx->compute_result(data, :storage, :invest_cost_permw_perhr, i, yr_idx), 1:nyr)
        storage_tmp.past_invest_subsidy[i] = maximum(yr_idx->compute_result(data, :storage, :invest_subsidy_permw_perhr, i, yr_idx), 1:nyr)
    end

    # Filter anything with capacity below the threshold
    thresh = config[:pcap_retirement_threshold]
    filter!(storage_tmp) do row
        # Keep anything above the threshold
        row.pcap0 > thresh && return true
        row.pcap_inv <= thresh && return false 

        row.build_type == "exog" && return false # We don't care to keep track of exogenous past capex

        # Below the threshold, check to see if we are still within the economic lifetime
        year_econ_life = add_to_year(row.year_on, row.econ_life)
        year_econ_life > year_end && return true

        return false
    end

    storage_tmp.pcap_max = copy(storage_tmp.pcap0)


    # Combine storage devices that are the same
    gdf = groupby(storage_tmp, Not(:pcap0))
    storage_tmp_combined = combine(gdf,
        :pcap0 => sum => :pcap0
    )
    storage_tmp_combined.pcap_max = copy(storage_tmp_combined.pcap0)

    file_out = get_out_path(config, "storage.csv")
    CSV.write(file_out, storage_tmp_combined)

    return nothing
end
export save_updated_storage_table