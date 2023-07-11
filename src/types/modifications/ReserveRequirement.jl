
"""
    ReserveRequirement <: Modification

Representation of reserve requirement, such that the sum of eligible capacity in the region is constrained to be ≥ than the load in the region. # TODO: served or nominal load?

Keyword arguments:
* `name`: name of the modification
* `filters`: the filters for the generating, storage, and load regions
* `credit_gen = AvailabilityFactorCredit()`: the [`Crediting`](@ref) for the generators, defaults to [`AvailabilityFactorCredit`](@ref)
* `credit_stor = StandardStorageCrediting()`: the [`Crediting`](@ref) for the storage facilities (see [`Storage`](@ref)), defaults to [`AvailabilityFactorCredit`](@ref)
* `requirements`: an OrderedDict{Symbol, Float64} mapping a year symbol to a percent requirement of required reserve above the load.
* `load_type = "plserv"`: a String for what type of load to consider.  Can be "plserv" or "plnom" - served load power or nominal load power.
"""
struct ReserveRequirement <: Modification
    name::Symbol
    filters::OrderedDict{Symbol} 
    credit_gen::Crediting
    credit_stor::Crediting
    requirements::OrderedDict{Symbol, Float64}
    load_type::String

    function ReserveRequirement(;
            name,
            filters = OrderedDict{Symbol, Any}(),
            credit_gen  = AvailabilityFactorCredit(),
            credit_stor = StandardStorageReserveCrediting(),
            requirements,
            load_type = "plserv"
        )
        return new(Symbol(name), filters, Crediting(credit_gen), Crediting(credit_stor), requirements, load_type)
    end
end
export ReserveRequirement


mod_rank(::Type{<:ReserveRequirement}) = 0.0

function modify_model!(mod::ReserveRequirement, config, data, model)
    # Compute the capacity credit earned by each generator.
    #get gen idxs 
    
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(mod.filters))
    bus = get_table(data, :bus)
    bus_idxs = get_row_idxs(bus, parse_comparisons(mod.filters))
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    ngen = nrow(get_table(data, :gen))
    years = get_years(data)
    requirements = mod.requirements
    c_gen = mod.credit_gen

    @info "Applying $(mod.name) to $(length(gen_idxs)) generators by modifying setup data"

    #create get table column for policy, set to zeros to start
    credits = Container[ByNothing(0.0) for i in 1:nrow(gen)]
    add_table_col!(data, :gen, mod.name, credits, CreditsPerMWCapacity,
        "Credit level for reserve requirement $(mod.name).  This gets multiplied by the power capacity in the reserve requirement constraint.")

    for gen_idx in gen_idxs
        credits[gen_idx] = Container(get_credit(c_gen, data, gen[gen_idx, :]))
    end

    # Set up the capacity constraint
    cons_name = Symbol("cons_pcap_$(mod.name)")
    pcap_gen = model[:pcap_gen]::Matrix{VariableRef}
    plserv_bus = model[:plserv_bus]::Array{AffExpr, 3}
    expr_pcap = @expression(
        model,
        [yr_idx in 1:nyr, hr_idx in 1:nhr],
        sum(
            pcap_gen[gen_idx, yr_idx] * credits[gen_idx][yr_idx, hr_idx] 
            for gen_idx in gen_idxs
        )
    )
    
    if mod.load_type == "plnom"
        expr_pres = @expression(
            model,
            [yr_idx in 1:nyr, hr_idx in 1:nhr],
            (1 + get(requirements, Symbol(years[yr_idx]), -1.0)) * 
            sum(
                get_plnom(data, bus_idx, yr_idx, hr_idx)
                for bus_idx in bus_idxs
            )
        )
    else # mod.load_type == "plserv"
        expr_pres = @expression(
            model,
            [yr_idx in 1:nyr, hr_idx in 1:nhr],
            (1 + get(requirements, Symbol(years[yr_idx]), -1.0)) * 
            sum(
                plserv_bus[bus_idx, yr_idx, hr_idx]
                for bus_idx in bus_idxs
            )
        )
    end

    model[Symbol("pcap_qual_$(mod.name)")] = expr_pcap
    model[Symbol("pres_req_$(mod.name)")] = expr_pres

    # Add in credit for storage if applicable
    if haskey(data, :storage)
        stor = get_table(data, :storage)
        stor_idxs = get_row_idxs(stor, parse_comparisons(mod.filters))
        c_stor = mod.credit_stor

        credits_stor = Container[ByNothing(0.0) for i in 1:nrow(stor)]
        add_table_col!(data, :storage, mod.name, credits_stor, CreditsPerMWCapacity,
        "Credit level for reserve requirement $(mod.name).  This gets multiplied by the power capacity in the reserve requirement constraint.")

        for stor_idx in stor_idxs
            credits_stor[stor_idx] = Container(get_credit(c_stor, data, stor[stor_idx, :]))
        end

        pcap_stor = model[:pcap_stor]::Matrix{VariableRef}
        for yr_idx in 1:nyr, hr_idx in 1:nhr
            for stor_idx in stor_idxs
                add_to_expression!(expr_pcap[yr_idx, hr_idx], pcap_stor[stor_idx, yr_idx], credits_stor[stor_idx][yr_idx, hr_idx])
            end
        end
    end

    cons = @constraint(
        model,
        [yr_idx in 1:nyr, hr_idx in 1:nhr],
        expr_pcap[yr_idx, hr_idx] >= expr_pres[yr_idx, hr_idx]
    )
    model[cons_name] = cons
end

function modify_results!(mod::ReserveRequirement, config, data)
    gen = get_table(data, :gen)
    credit_per_mw = gen[!, mod.name]::Vector{Container}
    rebate_col_name = Symbol("$(mod.name)_rebate_per_mw")
    rebate_result_name = Symbol("$(mod.name)_rebate")


    # Pull out the shadow price of the constraint
    sp = get_raw_result(data, Symbol("cons_pcap_$(mod.name)"))::Matrix{Float64} # nyr x nhr

    # `sp` is currently a misleading shadow price - it is for the capacity in each hour, but it is not for the hourly capacity.  Must divide by # of hours spent at each hour to get an accurate "price"
    hourly_price_per_credit = ByYearAndHour(unweight_hourly(data, sp, -))

    # Make a gen table column for it
    price_per_mw_per_hr = map(c->c .* hourly_price_per_credit, credit_per_mw)
    add_table_col!(data, :gen, rebate_col_name, price_per_mw_per_hr, DollarsPerMWCapacityPerHour, "This is the rebate recieved by EGU's for each MW for each hour from the $(mod.name) reserve requirement.")

    # Make a results formula
    add_results_formula!(data, :gen, rebate_result_name, "SumHourlyWeighted(pcap, $rebate_col_name)", Dollars, "This is the total rebate recieved by EGU's from the $(mod.name) reserve requirement.")

    # Add it to net_total_revenue_prelim
    add_to_results_formula!(data, :gen, :net_total_revenue_prelim, "+ $rebate_result_name")

    # Subtract it from user surplus
    add_welfare_term!(data, :user, :gen, rebate_result_name, -)

    # Do the same for storage
    if haskey(data, :storage)
        stor = get_table(data, :storage)
        credit_per_mw_stor = stor[!, mod.name]::Vector{Container}

        # Make a storage table column for it
        price_per_mw_per_hr_stor = map(c->c .* hourly_price_per_credit, credit_per_mw_stor)
        add_table_col!(data, :storage, rebate_col_name, price_per_mw_per_hr_stor, DollarsPerMWCapacityPerHour, "This is the rebate recieved by storage facilities for each MW for each hour from the $(mod.name) reserve requirement.")

        # Make a results formula
        add_results_formula!(data, :storage, rebate_result_name, "SumHourlyWeighted(pcap, $rebate_col_name)", Dollars, "This is the total rebate recieved by storage facilities from the $(mod.name) reserve requirement.")

        # Add it to net_total_revenue_prelim
        add_to_results_formula!(data, :storage, :net_total_revenue_prelim, "+ $rebate_result_name")

        # Subtract it from user surplus
        add_welfare_term!(data, :user, :storage, rebate_result_name, -)
    end
end