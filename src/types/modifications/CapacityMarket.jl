Base.@kwdef struct CapacityMarket <: Modification
    name::Symbol
    filters::OrderedDict{Symbol}
    credit::Crediting = UnitCredit()
    requirements::OrderedDict{Symbol, Float64}
end

function modify_model!(mod::CapacityMarket, config, data, model)
    # Compute the capacity credit earned by each generator.
    #get gen idxs 
    gen = get_table(data, :gen, parse_comparisons(pol.gen_filters))
    nyr = get_num_years(data)
    ngen = nrow(get_table(data, :gen))
    years = get_years(data)
    requirements = mod.requirements
    c = pol.credit

    @info "Applying $(mod.name) to $(nrow(gen)) generators by modifying setup data"

    #create get table column for policy, set to zeros to start
    add_table_col!(data, :gen, mod.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], CreditsPerMWCapacity,
        "Credit level for capacity market: $(mod.name)")
    
    credits = get_table_col(data, :gen, mod.name)

    for g in eachrow(gen)
        g[mod.name] = Container(get_credit(c, data, g))
    end

    # Set up the capacity constraint
    cons_name = Symbol("cons_pcap_$(mod.name)")
    pcap_gen = model[:pcap_gen]
    model[cons_name] = @constraint(
        model,
        [yr_idx in 1:nyr],
        sum(pcap_gen[gen_idx, yr_idx] * credits[gen_idx][yr_idx] for gen_idx in 1:ngen) >= get(requirements, Symbol(years[yr_idx]), 0.0)
    )
end

function process_results!(mod::CapacityMarket, config, data)
    gen = get_table(data, :gen)
    credit_per_mw = gen[!, mod.name]

    # Pull out the shadow price of the constraint
    sp = get_raw_result(data, Symbol("cons_pcap_$(mod.name)"))::Vector{Float64}
    price_per_credit = ByYear(sp)

    # Make a gen table column for it
    price_per_mw_per_hr = map(c->c .* price_per_credit, credit_per_mw)
    rebate_col_name = Symbol("$(mod.name)_rebate_per_mw")
    add_table_col!(data, :gen, rebate_col_name, price_per_mw_per_hr, DollarsPerMWCapacityPerHour, "This is the rebate recieved by EGU's for each MW for each hour from the $(mod.name) capacity market.")

    # Make a results formula
    rebate_result_name = Symbol("$(mod.name)_rebate")
    add_results_formula!(data, :gen, rebate_result_name, "SumHourlyWeighted(pcap, $rebate_col_name)", Dollars, "This is the total rebate recieved by EGU's from the $(mod.name) capacity market.")

    # Add it to net_total_revenue_prelim
    add_to_results_formula!(data, :gen, :net_total_revenue_prelim, "+ $rebate_result_name")

    # Subtract it from user surplus
    add_welfare_term!(data, :user, :gen, rebate_result_name, -)

end