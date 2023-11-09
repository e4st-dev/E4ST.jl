
"""
    ReserveRequirement <: Modification

Representation of reserve requirement, such that the sum of eligible power injection capacity in the region (including both generators and storage devices) is constrained to be greater than or equal to some percentage above the load.

Keyword arguments:
* `name` - name of the modification
* `area` - the area by which to group the buses by for the reserve requirements.
* `credit_gen` - the [`Crediting`](@ref) for the generators, defaults to [`AvailabilityFactorCrediting`](@ref)
* `credit_stor` - the [`Crediting`](@ref) for the storage facilities (see [`Storage`](@ref)), defaults to [`StandardStorageReserveCrediting`](@ref)
* `requirements_file` - a table with the subareas and the percent requirement of power capacity above the load.  See [`summarize_table(::Val{:reserve_requirements})`](@ref)
* `flow_limits_file` - (optional) a table with positive and negative flow limits from each subarea to each other subarea.  See [`summarize_table(::Val{:reserve_flow_limits})`](@ref).  If none provided, it is assumed that no flow is permitted between regions.
* `load_type` - a `String` for what type of load to base the requirement off of.  Can be either: 
    * `plnom` - (default), nominal load power.
    * `plserv` - served load power.

Model Modification:
* Variables
  * `pres_flow_<name>` - (nflow x nyr x nhr) Reserve power flow for each row of the flow limit table, bounded by forward and reverse max flows. (only present if there is `flow_limits_file` file provided)
* Expressions
  * `pres_total_subarea_<name>` - (nsubarea x nyr x nhr) Reserve power from all sources for each subarea
  * `pres_gen_subarea_<name>` - (nsubarea x nyr x nhr) Reserve power from generators for each subarea (function of capacity)
  * `pres_stor_subarea_<name>` - (nsubarea x nyr x nhr) Reserve power from storage units (only present if there is [`Storage`](@ref) in the model.)
  * `pres_req_subarea_<name>` - (nsubarea x nyr x nhr) Required reserve power (function of load), depends on `requirements_file` and `load_type`
  * `pres_flow_subarea_<name>` - (nsubarea x nyr x nhr) Reserve flow flowing out of each subarea, function of `pres_flow_<name>` variable.   (only present if there is `flow_limits_file` file provided)
* Constraints
  * `cons_pres_<name>` - (nsubarea x nyr x nhr) Constrain that `pres_total_subarea_<name> ≥ pres_req_subarea_<name>`.

Adds results:
* `(:gen, :<name>_rebate)` - the total rebate for generators, for satisfying the reserve requirement.  Generally ≥ 0.  This is added to `(:gen, :net_total_revenue_prelim)`, and subtracted from electricity `user` welfare.
* `(:storage, :<name>_rebate)` - (only added if [`Storage`](@ref) included) the total rebate for storage units, for satisfying the reserve requirement.  Generally ≥ 0.  This is added to `(:storage, :net_total_revenue_prelim)`, and subtracted from electricity `user` welfare.
"""
struct ReserveRequirement <: Modification
    name::Symbol
    area::String
    credit_gen::Crediting
    credit_stor::Crediting
    requirements_file::String
    flow_limits_file::String
    load_type::String

    function ReserveRequirement(;
            name,
            area,
            credit_gen  = AvailabilityFactorCrediting(),
            credit_stor = StandardStorageReserveCrediting(),
            requirements_file,
            flow_limits_file="",
            load_type = "plnom"
        )
        return new(Symbol(name), area, Crediting(credit_gen), Crediting(credit_stor), requirements_file, flow_limits_file, load_type)
    end
end
export ReserveRequirement


@doc """
    summarize_table(::Val{:reserve_requirements})

$(table2markdown(summarize_table(Val(:reserve_requirements))))
"""
function summarize_table(::Val{:reserve_requirements})
    df = TableSummary()
    push!(df, 
        (:subarea, Any, NA, true, "The subarea that the requirement is specified over"),
        (:y_, Float64, Ratio, true, "The percent requirement of reserve capacity over the load.  Include a column for each year in the hours table.  I.e. `:y2020`, `:y2030`, etc"),
    )
    return df
end

@doc """
    summarize_table(::Val{:reserve_flow_limits})

$(table2markdown(summarize_table(Val(:reserve_flow_limits))))
"""
function summarize_table(::Val{:reserve_flow_limits})
    df = TableSummary()
    push!(df, 
        (:f_subarea, Any, NA, true, "The subarea the reserve power flow originates **f**rom"),
        (:t_subarea, Any, NA, true, "The subarea the reserve power flow goes **t**o"),
        (:pflow_forward_max, Float64, MWFlow, true, "Maximum reserve power going from `f_subarea` to `t_subarea`"),
        (:pflow_reverse_max, Float64, MWFlow, true, "Maximum reserve power going from `t_subarea` to `f_subarea`")
    )
    return df
end

function modify_raw_data!(mod::ReserveRequirement, config, data)
    # Load in the reserve requirements table and the reserve flow limits table
    name = mod.name
    data[Symbol("$(name)_requirements")]    = read_table(data, mod.requirements_file, :reserve_requirements)
    if ~isempty(mod.flow_limits_file)
        flow_limits = read_table(data, mod.flow_limits_file, :reserve_flow_limits)
        data[Symbol("$(name)_flow_limits")] = flow_limits

        n_wrong = count(row->row.pflow_forward_max+row.pflow_reverse_max < 0, eachrow(flow_limits))
        if n_wrong > 0
            @warn "$n_wrong reserve power flow limits given where pflow_forward_max > -pflow_reverse_max, removing these limits to avoid model infeasibility!"
            filter!(row->row.pflow_forward_max + row.pflow_reverse_max >= 0, flow_limits)
        end
    end
    return nothing
end

mod_rank(::Type{<:ReserveRequirement}) = 0.0

function modify_model!(mod::ReserveRequirement, config, data, model)
    # Compute the capacity credit earned by each generator.    
    gen = get_table(data, :gen)
    bus = get_table(data, :bus)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    ngen = nrow(gen)
    nbus = nrow(bus)
    years = get_years(data)
    c_gen = mod.credit_gen
    
    area = mod.area
    requirements = get_table(data, "$(mod.name)_requirements")

    # Convert to make sure they are the same type.
    requirements.subarea = convert(typeof(bus[!, area]), requirements.subarea)

    subareas = requirements.subarea
    subarea2idx = Dict(subareas[i]=>i for i in axes(subareas,1))


    gdf_gen = groupby(gen, area)
    gdf_bus = groupby(bus, area)

    gen_idx_sets = map(subarea -> haskey(gdf_gen, (subarea,)) ? getfield(gdf_gen[(subarea,)], :rows) : Int64[], subareas)
    bus_idx_sets = map(subarea -> haskey(gdf_bus, (subarea,)) ? getfield(gdf_bus[(subarea,)], :rows) : Int64[], subareas)

    requirements.gen_idx_sets = gen_idx_sets
    requirements.bus_idx_sets = bus_idx_sets




    # Create column for credit level, set to zeros to start
    credits = Container[ByNothing(0.0) for i in axes(gen,1)]
    add_table_col!(data, :gen, mod.name, credits, CreditsPerMWCapacity,
        "Credit level for reserve requirement $(mod.name).  This gets multiplied by the power capacity in the reserve requirement constraint.")

    for gen_idx in axes(gen, 1)
        credits[gen_idx] = Container(get_credit(c_gen, data, gen[gen_idx, :]))
    end

    # Pull out some of the variables/expressions
    pcap_gen = model[:pcap_gen]::Matrix{VariableRef}
    plserv_bus = model[:plserv_bus]::Array{AffExpr, 3}

    # Create expression for total reserve power by subarea
    pres_subarea = @expression(
        model,
        [sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        AffExpr(0.0)
    )

    # Create expression for reserve power from generators by subarea
    pres_gen_subarea = @expression(
        model,
        [sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        AffExpr(0.0)
    )

    for sa_idx in axes(subareas,1)
        gen_idxs = gen_idx_sets[sa_idx]
        for gen_idx in gen_idxs, yr_idx in 1:nyr, hr_idx in 1:nhr
            add_to_expression!(pres_gen_subarea[sa_idx, yr_idx, hr_idx], pcap_gen[gen_idx, yr_idx], credits[gen_idx][yr_idx, hr_idx])
        end
    end

    # Add the power reserves from generators to the total expression.
    for sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr
        add_to_expression!(pres_subarea[sa_idx, yr_idx, hr_idx], pres_gen_subarea[sa_idx, yr_idx, hr_idx])
    end


    # Get requirement by bus and year
    bus_yr_idx_2_req = fill(-1.0, (nbus, nyr))
    years_sym = Symbol.(years)
    for req_idx in axes(requirements,1)
        for bus_idx in requirements.bus_idx_sets[req_idx]
            for (yr_idx, year) in enumerate(years_sym)
                plmax = maximum(get_plnom(data, bus_idx, yr_idx, hr_idx) for hr_idx in 1:nhr)
                bus_yr_idx_2_req[bus_idx, yr_idx] = plmax * get(requirements[req_idx,:], year, -0.0)
            end
        end
    end

    # Make a nbusxnyear matrix containing the annual peak load for the year
    bus_yr_idx_2_plmax = [maximum(get_plnom(data, bus_idx, yr_idx, hr_idx) for hr_idx in 1:nhr) for bus_idx in axes(bus,1), yr_idx in 1:nyr]

    # Set up the expression for the reserve requirement contribution from each bus.  This is used for welfare accounting
    if mod.load_type == "plnom"
        pres_req = @expression(
            model,
            [bus_idx in axes(bus, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            bus_yr_idx_2_req[bus_idx, yr_idx] == 0.0 ? 0.0 : get_plnom(data, bus_idx, yr_idx, hr_idx) + bus_yr_idx_2_req[bus_idx, yr_idx]
        )

        
    else # mod.load_type == "plserv"
        pres_req = @expression(
            model,
            [bus_idx in axes(bus, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            bus_yr_idx_2_req[bus_idx, yr_idx] == 0.0 ? 0.0 : plserv_bus[bus_idx, yr_idx, hr_idx] + bus_yr_idx_2_req[bus_idx, yr_idx]
        )
    end

    # Set up expression for the reserve requirement for each subarea by aggregating the buses
    pres_req_subarea = @expression(
        model,
        [sa_idx in axes(subareas, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        sum(
            pres_req[bus_idx, yr_idx, hr_idx]
            for bus_idx in bus_idx_sets[sa_idx]
        )
    )

    # Store things into the model
    model[Symbol("pres_gen_subarea_$(mod.name)")] = pres_gen_subarea
    model[Symbol("pres_total_subarea_$(mod.name)")] = pres_subarea
    model[Symbol("pres_req_subarea_$(mod.name)")] = pres_req_subarea
    model[Symbol("pres_req_bus_$(mod.name)")] = pres_req

    # Add in credit for storage if applicable
    if haskey(data, :storage)
        stor = get_table(data, :storage)
        gdf_stor = groupby(stor, area)
        stor_idx_sets = map(subarea -> haskey(gdf_stor, (subarea,)) ? getfield(gdf_stor[(subarea,)], :rows) : Int64[], subareas)
        requirements.stor_idx_sets = stor_idx_sets
        c_stor = mod.credit_stor

        credits_stor = Container[ByNothing(0.0) for i in 1:nrow(stor)]
        add_table_col!(data, :storage, mod.name, credits_stor, CreditsPerMWCapacity,
        "Credit level for reserve requirement $(mod.name).  This gets multiplied by the power capacity in the reserve requirement constraint.")

        for stor_idx in axes(stor, 1)
            credits_stor[stor_idx] = Container(get_credit(c_stor, data, stor[stor_idx, :]))
        end

        # Make an expression for storag reserves
        pres_stor_subarea = @expression(
            model,
            [sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            AffExpr(0.0)
        )

        pcap_stor = model[:pcap_stor]::Matrix{VariableRef}
        for sa_idx in axes(subareas, 1), yr_idx in 1:nyr, hr_idx in 1:nhr
            stor_idxs = stor_idx_sets[sa_idx]
            for stor_idx in stor_idxs
                add_to_expression!(pres_stor_subarea[sa_idx, yr_idx, hr_idx], pcap_stor[stor_idx, yr_idx], credits_stor[stor_idx][yr_idx, hr_idx])
            end
        end

        for sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr
            add_to_expression!(pres_subarea[sa_idx, yr_idx, hr_idx], pres_stor_subarea[sa_idx, yr_idx, hr_idx])
        end

        model[Symbol("pres_stor_subarea_$(mod.name)")] = pres_stor_subarea
    end

    # Add variables for reserve capacity flow
    if ~isempty(mod.flow_limits_file)
        flow_limits = get_table(data, "$(mod.name)_flow_limits")
        pflow_forward_max = flow_limits.pflow_forward_max::Vector{Float64}
        pflow_reverse_max = flow_limits.pflow_reverse_max::Vector{Float64}

        # Make a variable for each flow for each limit
        pres_flow = @variable(
            model,
            [flow_idx in axes(flow_limits,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            lower_bound = -pflow_reverse_max[flow_idx],
            upper_bound =  pflow_forward_max[flow_idx],
        )

        # Make an expression for power flowing out of each subarea
        pres_flow_subarea = @expression(
            model,
            [sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr],
            AffExpr(0.0)
        )

        flow_limits.t_subarea_idx = map(sa->subarea2idx[sa], flow_limits.t_subarea)
        flow_limits.f_subarea_idx = map(sa->subarea2idx[sa], flow_limits.f_subarea)
        
        for flow_idx in axes(flow_limits, 1)
            t_subarea_idx = flow_limits.t_subarea_idx[flow_idx]::Int64
            f_subarea_idx = flow_limits.f_subarea_idx[flow_idx]::Int64
            
            for yr_idx in 1:nyr, hr_idx in 1:nhr
                add_to_expression!(pres_flow_subarea[f_subarea_idx, yr_idx, hr_idx], pres_flow[flow_idx, yr_idx, hr_idx])
                add_to_expression!(pres_flow_subarea[t_subarea_idx, yr_idx, hr_idx], pres_flow[flow_idx, yr_idx, hr_idx], -1)
            end
        end

        for sa_idx in axes(subareas,1), yr_idx in 1:nyr, hr_idx in 1:nhr
            add_to_expression!(pres_subarea[sa_idx, yr_idx, hr_idx], pres_flow_subarea[sa_idx, yr_idx, hr_idx], -1)
        end

        # Store the newly created variables into the model
        model[Symbol("pres_flow_subarea_$(mod.name)")] = pres_flow_subarea
        model[Symbol("pres_flow_$(mod.name)")] = pres_flow
    end

    # Make the reserve requirment constraint
    model[Symbol("cons_pres_$(mod.name)")] = @constraint(
        model,
        [sa_idx in axes(subareas, 1), yr_idx in 1:nyr, hr_idx in 1:nhr],
        pres_subarea[sa_idx, yr_idx, hr_idx] >= pres_req_subarea[sa_idx, yr_idx, hr_idx]
    )
end

function modify_results!(mod::ReserveRequirement, config, data)
    gen = get_table(data, :gen)
    bus = get_table(data, :bus)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    credit_per_mw_gen = gen[!, mod.name]::Vector{Container}
    rebate_col_name = Symbol("$(mod.name)_rebate_per_mw")
    rebate_result_name = Symbol("$(mod.name)_rebate")
    rebate_price_result_name = Symbol("$(mod.name)_rebate_per_mw_price")
    cost_col_name = Symbol("$(mod.name)_cost_per_mw")
    cost_result_name = Symbol("$(mod.name)_cost")
    pres_name = Symbol("$(mod.name)_pres")
    pres_req_name = Symbol("$(mod.name)_pres_req")
    
    requirements = get_table(data, "$(mod.name)_requirements")

    gen_idx_sets = requirements.gen_idx_sets::Vector{Vector{Int64}}
    bus_idx_sets = requirements.bus_idx_sets::Vector{Vector{Int64}}
    
    # Pull out the shadow price of the constraint
    sp = get_raw_result(data, Symbol("cons_pres_$(mod.name)"))::Array{Float64, 3} # nsubarea x nyr x nhr
    # `sp` is currently a misleading shadow price - it is for the capacity in each hour, but it is not for the hourly capacity.  Must divide by # of hours spent at each hour to get an accurate "price"
    hourly_price_per_credit = unweight_hourly(data, sp, -)::Array{Float64,3}

    # Pull out the reserve power requirement contribution of each bus
    pres_req_bus = get_raw_result(data, Symbol("pres_req_bus_$(mod.name)"))::Array{Float64, 3} # nbus x nyr x nhr
    add_table_col!(data, :bus, pres_req_name, pres_req_bus, MWReserve, "The required reserve power in from $(mod.name), in MW.")

    # Make a gen table column the price for bus and gen tables
    price_per_mw_per_hr_gen = Container[ByNothing(0.0) for _ in axes(gen,1)]
    price_per_mw_per_hr_bus = Container[ByNothing(0.0) for _ in axes(bus,1)]
    for req_idx in axes(requirements, 1)
        cur_hourly_price_per_credit = ByYearAndHour(view(hourly_price_per_credit, req_idx, :, :))
        gen_idxs = gen_idx_sets[req_idx]
        for gen_idx in gen_idxs
            price_per_mw_per_hr_gen[gen_idx] = credit_per_mw_gen[gen_idx] .* cur_hourly_price_per_credit
        end

        bus_idxs = bus_idx_sets[req_idx]
        for bus_idx in bus_idxs
            price_per_mw_per_hr_bus[bus_idx] = cur_hourly_price_per_credit
        end
    end

    pres_gen = map(1:nrow(gen)) do gen_idx
        ByYear(gen.pcap[gen_idx]) .* gen[gen_idx, mod.name]
    end

    add_table_col!(data, :gen, pres_name, pres_gen, MWCapacity, "The power reserve capacity used to fill $(mod.name)")
    add_table_col!(data, :gen, rebate_col_name, price_per_mw_per_hr_gen, DollarsPerMWCapacityPerHour, "This is the rebate recieved by EGU's for each MW of capacity for each hour from the $(mod.name) reserve requirement.")
    add_table_col!(data, :bus, cost_col_name, price_per_mw_per_hr_bus, DollarsPerMWCapacityPerHour, "This is the rebate payed by users to EGU's for each MW of demand for each hour from the $(mod.name) reserve requirement.")

    # Make results formulas for bus table
    add_results_formula!(data, :bus, cost_result_name, "SumHourlyWeighted($pres_req_name, $cost_col_name)", Dollars, "This is the total rebate paid by users to EGU's from the $(mod.name) reserve requirement, not including merchandising surplus.")

    # Make results formulas for the gen table
    add_results_formula!(data, :gen, rebate_result_name, "SumHourlyWeighted(pcap, $rebate_col_name)", Dollars, "This is the total rebate recieved by EGU's from the $(mod.name) reserve requirement.")
    add_results_formula!(data, :gen, "pcap_qual_$(mod.name)", "AverageHourlyWeighted(pcap, $(mod.name))", MWCapacity, "Hourly-weighted average capacity that qualifies for the $(mod.name)")
    add_results_formula!(data, :gen, rebate_price_result_name, "$(rebate_result_name)/pcap_qual_$(mod.name)",DollarsPerMWCapacity, "The per MW of qualifying capacity price of the rebate receive by EGU's from the $(mod.name) reserve requirement.")
    
    # Add it to net_total_revenue_prelim
    add_to_results_formula!(data, :gen, :net_total_revenue_prelim, "+ $rebate_result_name")

    # Subtract the cost from user surplus
    add_welfare_term!(data, :user, :bus, cost_result_name, -)

    # Do the same for storage
    if haskey(data, :storage)
        stor = get_table(data, :storage)

        stor_idx_sets = requirements.stor_idx_sets::Vector{Vector{Int64}}

        credit_per_mw_stor = stor[!, mod.name]::Vector{Container}

        # Make a storage table column for it
        price_per_mw_per_hr_stor = Container[ByNothing(0.0) for _ in axes(stor,1)]
        for req_idx in axes(requirements, 1)
            cur_hourly_price_per_credit = ByYearAndHour(view(hourly_price_per_credit, req_idx, :, :))
            stor_idxs = stor_idx_sets[req_idx]
            for stor_idx in stor_idxs
                price_per_mw_per_hr_stor[stor_idx] = credit_per_mw_stor[stor_idx] .* cur_hourly_price_per_credit
            end
        end

        pres_stor = map(1:nrow(stor)) do stor_idx
            ByYear(stor.pcap[stor_idx]) .* stor[stor_idx, mod.name]
        end

        add_table_col!(data, :storage, pres_name, pres_stor, MWCapacity, "The power reserve capacity used to fill $(mod.name)")
        add_table_col!(data, :storage, rebate_col_name, price_per_mw_per_hr_stor, DollarsPerMWCapacityPerHour, "This is the rebate recieved by storage facilities for each MW for each hour from the $(mod.name) reserve requirement.")

        # Make a results formula
        add_results_formula!(data, :storage, rebate_result_name, "SumHourlyWeighted(pcap, $rebate_col_name)", Dollars, "This is the total rebate recieved by storage facilities from the $(mod.name) reserve requirement.")
        add_results_formula!(data, :storage, "pcap_qual_$(mod.name)", "AverageHourlyWeighted(pcap, $(mod.name))", MWCapacity, "Hourly-weighted average capacity that qualifies for the $(mod.name)")
        add_results_formula!(data, :storage, rebate_price_result_name, "$(rebate_result_name)/pcap_qual_$(mod.name)",DollarsPerMWCapacity, "The per MW price of the rebate receive by EGU's from the $(mod.name) reserve requirement.")

        # Add it to net_total_revenue_prelim
        add_to_results_formula!(data, :storage, :net_total_revenue_prelim, "+ $rebate_result_name")
    end

    # Add merchandising surplus if applicable
    if ~isempty(mod.flow_limits_file)
        flow_limits = get_table(data, "$(mod.name)_flow_limits")
        pres_flow = get_raw_result(data, Symbol("pres_flow_$(mod.name)"))::Array{Float64, 3}

        ms_bus = zeros(nrow(bus), nyr, nhr)

        hour_weights = get_hour_weights(data)
        hour_weights_mat = [hour_weights[hr_idx] for yr_idx in 1:nyr, hr_idx in 1:nhr]
    
        for flow_idx in axes(flow_limits, 1)
            flow = view(pres_flow, flow_idx, :, :)
            t_subarea_idx = flow_limits.t_subarea_idx[flow_idx]::Int64
            f_subarea_idx = flow_limits.f_subarea_idx[flow_idx]::Int64
            t_price_per_credit = view(hourly_price_per_credit, t_subarea_idx, :, :)
            f_price_per_credit = view(hourly_price_per_credit, f_subarea_idx, :, :)

            # Compute merchandising suplus to give to the f subarea and the t subarea
            # Downstream customers probably paid most of the cost for the transmission capacity to be built, so it is more likely that they would get the revenues from the transmission.
            f_ms = max.(0.0, (f_price_per_credit .- t_price_per_credit) .* flow .* hour_weights_mat)
            t_ms = max.(0.0, (t_price_per_credit .- f_price_per_credit) .* flow .* hour_weights_mat)

            # Find which buses to distribute to and the percentages of the surplus to distribute to each subarea
            f_bus_idxs = requirements.bus_idx_sets[f_subarea_idx]
            t_bus_idxs = requirements.bus_idx_sets[t_subarea_idx]
            f_bus_pres_req_total = replace_zeros!(sum(view(pres_req_bus, bus_idx, :, :) for bus_idx in f_bus_idxs), 1e-9)
            t_bus_pres_req_total = replace_zeros!(sum(view(pres_req_bus, bus_idx, :, :) for bus_idx in t_bus_idxs), 1e-9)

            # Distribute the total merchandising surplus across all the buses in the subarea
            for bus_idx in f_bus_idxs
                ms_bus[bus_idx, :, :] .+= (f_ms .* view(pres_req_bus, bus_idx, :, :) ./ f_bus_pres_req_total)
            end

            for bus_idx in t_bus_idxs
                ms_bus[bus_idx, :, :] .+= (t_ms .* view(pres_req_bus, bus_idx, :, :) ./ t_bus_pres_req_total)
            end
        end

        # Add the merchandising surplus to the bus table, results formula, and welfare.
        add_table_col!(data, :bus, Symbol("$(mod.name)_merchandising_surplus"), ms_bus, Dollars, "Merchandising surplus earned from differences in power reserve prices across reserve regions, for $(mod.name)")
        add_results_formula!(data, :bus, Symbol("$(mod.name)_merchandising_surplus_total"), "SumHourly($(mod.name)_merchandising_surplus)", Dollars, "Total merchandising surplus payed to users in the area.")
        add_welfare_term!(data, :user, :bus, Symbol("$(mod.name)_merchandising_surplus_total"), +)
    end    
end