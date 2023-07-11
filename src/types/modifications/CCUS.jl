"""
    struct CCUS <: Modification

    CCUS(;file, groupby, co2_scalar=1e5, co2_step_quantity_limit=1e9)

This is a [`Modification`](@ref) that sets up markets for carbon captured by generators.  
* `file` - a file to the table containing markets/prices for buying/selling carbon dioxide.  See the `ccus_paths` table below, or [`summarize_table(::Val{:ccus_paths})`](@ref)
* `groupby` - a `String` indicating how markets are grouped.  I.e. "state".
* `co2_scalar` - a `Float64` for how much to scale the co2 variables by.  This helps with numerical instability, given that some CO₂ steps can be very large and could bloat the RHS and bounds range of the model.  A good rule of thumb is that this should be no less than `1e4` times smaller than `co2_step_quantity_limit`.
* `co2_step_quantity_limit` - A `Float64` for the maximum quantity of CO₂ that can be stored in any step.

Creates the following tables in `data`:
* `ccus_paths` - contains all pathways possible to sell CO₂.  
    * `producing_region` - The producing region
    * `storing_region` - The storing region of the pathway
    * `ccus_type` - the type of ccus (`eor` or `saline`)
    * `step_id` - the number of the step (not very important other than for book-keeping)
    * `step_quantity` - the quantity of CO₂ that can be stored in this step
    * `price_trans` - the cost to transport 1 short ton of CO₂ from `producing_region` to `storing_region`
    * `price_store` - the cost to store 1 short ton of CO₂ in the step
* `ccus_storers` - contains all the storers
    * `storing_region` - the storing region
    * `step_id` - the number of the step for the region
    * `ccus_type` - whether the step is `eor` or `saline`.
    * `step_quantity` - the number of short tons that may be stored in the step
    * `price_store` - the price to store a short ton of CO₂.
    * `path_idxs` - A list of indices representing the transportation paths to store carbon in this step.  Indexes into `ccus_paths` table.
* `ccus_producers` - contains all the producers, grouped by `ccus_type` and `producing_region`.  This contains the following columns:
    * `producing_region` - the region the CO₂ will be sent from
    * `ccus_type` - the type of the step the CO₂ will be sent to (`eor` or `saline`)
    * `path_idxs` - A list of indices representing the transportation paths to send carbon from this step.  Indexes into `ccus_paths` table.
    * `gen_idxs` - A list of generator indices that produce CO₂ in this region.

Creates the following variables/expressions
* `co2_trans[1:nrow(ccus_paths), 1:nyear]` - the amount of CO₂ transported along this producer-producer pathway (variable)
* `co2_stor[1:nrow(ccus_storers), 1:nyear]` - the amount of CO₂ stored by each storer (expression of `co2_trans`)
* `co2_prod[1:nrow(ccus_producers), 1:nyear]` - the amount of CO₂ produced by each sending region (expression of electricity generation)
* `co2_sent[1:nrow(ccus_producers), 1:nyear]` - the amount of CO₂ sent out from each sending region (expression of `co2_trans`).  This includes CO₂ sent within the same region.
* `cost_ccus_obj[1:nyear]` - the total cost of ccus, as added to the objective function.

Creates the following constraints
* `cons_co2_stor[1:nrow(ccus_storers), 1:nyear]` - the CO₂ stored at each injection site must not exceed `step_quantity`
* `cons_co2_bal[1:nrow(ccus_producers), 1:nyear]` - the CO₂ balancing equation for each region, i.e. `co2_prod == co2_sent`.

## Accessing Results
Results are stored in 2 places; the `ccus_paths` table, and the `gen` table.

Example Result Queries
* `compute_result(data, :gen, :stored_co2_total, :ccus_type=>"eor", "y2030")`
* `compute_result(data, :gen, :cost_capt_co2, :ccus_type=>"eor", yr_idx)`
* `compute_result(data, :gen, :cost_capt_co2_store, :gentype=>"coalccs", yr_idx)`
* `compute_result(data, :gen, :cost_capt_co2_trans, :, yr_idx)`
* `compute_result(data, :ccus_paths, :storer_cost_total, :storing_region=>"narnia")
* `compute_result(data, :ccus_paths, :storer_revenue_total, :producing_region=>"narnia")`
* `compute_result(data, :ccus_paths, :storer_profit_total, :ccus_type=>"eor")`

See also:
* [`modify_raw_data!(::CCUS, config, data)`](@ref)
* [`modify_setup_data!(::CCUS, config, data)`](@ref)
* [`modify_model!(::CCUS, config, data, model)`](@ref)
* [`modify_results!(::CCUS, config, data)`](@ref)
"""
struct CCUS <: Modification
    file::String # This would point to the file containing the CCUS market
    groupby::String
    co2_scalar::Float64
    co2_step_quantity_limit::Float64
end
function CCUS(;file, groupby, co2_scalar=1e5, co2_step_quantity_limit = 1e9)
    CCUS(file, groupby, co2_scalar, co2_step_quantity_limit)
end
export CCUS

mod_rank(::Type{<:CCUS}) = -3.0

@doc """
    summarize_table(::Val{:ccus_paths})

$(table2markdown(summarize_table(Val(:ccus_paths))))
"""
function summarize_table(::Val{:ccus_paths})
    df = TableSummary()
    push!(df, 
        (:producing_region, String, NA, true, "The name of the producing region (type of regions specified by groupby kwarg of CCUS mod"),
        (:storing_region, String, NA, true, "The name of the sequestering region (type of regions specified by groupby kwarg of CCUS mod"),
        (:step_id, Int64, NA, true, "The number of this particular market step"),
        (:ccus_type, String, NA, true, "The type of storage.  Can be \"eor\" or \"saline\""),
        (:step_quantity, Float64, ShortTonsPerYear, true, "The annual quantity of CO2 that can be stored in the step"),
        (:price_trans, Float64, DollarsPerShortTon, true, "The cost of transporting a short ton of CO2 for this producer-storing_region pair"),
        (:price_store, Float64, DollarsPerShortTon, true, "The cost to store a short ton of CO2 in this storage step"),
    )
    return df
end 

"""
    modify_raw_data!(mod::CCUS, config, data) -> nothing

Loads `mod.file` into `data[:ccus_paths]`.  See [`summarize_table(::Val{:ccus_paths})`](@ref) for more info.
"""
function modify_raw_data!(mod::CCUS, config, data)
    config[:ccus_file] = mod.file
    read_table!(config, data, :ccus_file => :ccus_paths)
    return nothing
end

"""
    modify_setup_data!(mod::CCUS, config, data) -> nothing

Does the following:
* Adds a column for carbon captured, `capt_co2`, based on `emis_co2`, and `capt_co2_percent`
* reduces `emis_co2` by `capt_co2`
* Splits up carbon capturing generators into 2 separate generators - one for "saline" and one for "eor", and adjusts the eor emissions by `config[eor_leakage_rate]`
* Add a column for `ccus_type` - either "eor", "saline", or "na"
* Adds sets of indices to `data[:ccus_gen_sets]::Vector{Vector{Int64}}`
"""
function modify_setup_data!(mod::CCUS, config, data)
    @info "Adding CCUS to the model"

    gen = get_table(data, :gen)
    @assert hasproperty(gen, :capt_co2_percent) "gen table must have column for `capt_co2_percent` for CCUS"
    @assert hasproperty(gen, :emis_co2) "gen table must have column for `emis_co2` for CCUS"

    if all(==(0.0), gen.capt_co2_percent)
        @warn "No carbon capturing generators, yet CCUS Modification provided.  Skipping. (all gen.capt_co2_percent equal to zero)"
        return
    end

    update_ccus_gens!(mod, config, data)

    ### Modify ccus
    ccus_paths = get_table(data, :ccus_paths)
    ccus_paths.step_quantity .= min.(mod.co2_step_quantity_limit, ccus_paths.step_quantity)
    gen = get_table(data, :gen)
    add_table_col!(data, :ccus_paths, :path_idx, 1:nrow(ccus_paths), NA, "The index of this path")
    add_table_col!(data, :ccus_paths, :price_total, (ccus_paths.price_trans .+ ccus_paths.price_store), DollarsPerShortTonCO2Captured, "The cost of transporting and storing a short ton of CO₂ in this storage pathway")


    ### Make ccus_storers
    # Gather all the sequestration steps.  There could be multiple steps per region, and multiple ccus options per step, from different producing regions
    gdf_storers = groupby(ccus_paths, [:storing_region, :step_id])

    # Assert that all the members of each sequestration step have the same quantity
    @assert all(allequal(sdf.step_quantity) for sdf in gdf_storers) "Carbon sequestration steps must have the same step_quantity"
    @assert all(allequal(sdf.price_store) for sdf in gdf_storers) "Carbon sequestration steps must have the same price_store"
    @assert all(allequal(sdf.ccus_type) for sdf in gdf_storers) "Carbon sequestration steps must have the same ccus_type"

    ccus_storers = combine(gdf_storers,
        :ccus_type => first => :ccus_type,
        :step_quantity => first => :step_quantity,
        :price_store => first => :price_store,
        :path_idx => Ref => :path_idxs,
    )
    ccus_storers.stor_idx = 1:nrow(ccus_storers)

    # Augment ccus_paths with the stor_idx.
    ccus_paths.stor_idx .= 0
    for (stor_idx, row) in enumerate(eachrow(ccus_storers))
        path_idxs = row.path_idxs
        ccus_paths.stor_idx[path_idxs] .= stor_idx
    end

    data[:ccus_storers] = ccus_storers


    ### Make ccus_producers
    # Group ccus_paths by the producing region and ccus_type
    gdf_producers = groupby(ccus_paths, [:producing_region, :ccus_type])
    gdf_gen = groupby(gen, Cols(mod.groupby, :ccus_type))

    # Add the generators together for the producer-type combos
    ccus_producers = combine(gdf_producers,
        :path_idx => Ref => :path_idxs,
    )

    transform!(ccus_producers,
        [:producing_region, :ccus_type] => 
        ByRow((key...) -> (haskey(gdf_gen, key) ? getfield(gdf_gen[key], :rows) : Int64[]))
        => :gen_idxs
    )

    data[:ccus_producers] = ccus_producers

end
export modify_setup_data!


"""
    update_ccus_gens!(mod::CCUS, config, data) -> nothing

Updates the carbon capturing generators by splitting into EOR and Saline-storing generators.  
"""
function update_ccus_gens!(mod::CCUS, config, data)
    gen = get_table(data, :gen)

    capt_co2 = map(row->row.emis_co2 .* row.capt_co2_percent, eachrow(gen)) # This may make an OriginalContainer with the original value for emis_co2 preserved, but that should be ok since this column isn't kept in save_updated_gen_table.
    add_table_col!(data, :gen, :capt_co2, capt_co2, ShortTonsPerMWhGenerated, "The rate of capture of CO2 (calculated from emis_co2 and capt_co2_percent)")


    # Turn emis_co2 into a vector of Containers for book-keeping.
    emis_co2 = Container[Container(e) for e in gen.emis_co2]
    capt_co2 = gen.capt_co2
    for idx in eachindex(emis_co2)
        all(==(0), capt_co2[idx]) && continue
        emis_co2[idx] = emis_co2[idx] .- capt_co2[idx]
    end
    gen.emis_co2 = emis_co2

    # Add column for ccus_type
    ccus_type = fill("na", nrow(gen))
    add_table_col!(data, :gen, :ccus_type, ccus_type, NA, "The type of reservoir that the captured carbon will be stored.  Either `saline` or `eor`.")
    ccus_types = unique(data[:ccus_paths].ccus_type)

    # Create sets of generators to match.
    ccus_gen_sets = Vector{Int64}[]
    data[:ccus_gen_sets] = ccus_gen_sets

    # Add new rows to the gen table for each capturing generator
    if length(ccus_types) > 2
        error("More than 2 ccus types specified, currently only eor and saline supported, given:\n$ccus_types")
    elseif length(ccus_types) == 2
        @assert "saline" in ccus_types
        @assert "eor" in ccus_types

        new_idx = nrow(gen) + 1
        for (gen_idx, row) in enumerate(eachrow(gen))
            # Continue if no CO2 captured
            row.capt_co2 == 0 && continue

            # Start making the gen set
            gen_set = [gen_idx]
            push!(ccus_gen_sets, gen_set)

            # Set up the ccus_type for the original
            row.ccus_type = "saline"

            # Make a new row for each other ccus_type
            newrow = Dict(pairs(row))
            newrow[:ccus_type] = "eor"
            push!(gen, newrow)
            push!(gen_set, new_idx)
            new_idx += 1
        end
    elseif length(ccus_types) == 1
        # If all one type, then assign to that type
        ccus_idxs = get_row_idxs(gen, :capt_co2=> >(0))
        gen[ccus_idxs, :ccus_type] = first(ccus_types)
    end

    # Update emission rate for EOR
    gen_eor = get_subtable(gen, :ccus_type=>"eor")
    eor_leakage_rate = get(config, :eor_leakage_rate, 0.5)
    for row in eachrow(gen_eor)
        row.emis_co2 .+=  eor_leakage_rate * row.capt_co2
    end
end
export update_ccus_gens!

function modify_model!(mod::CCUS, config, data, model)
    @info "Adding CCUS representation to the model"

    # Pull in the tables
    gen = get_table(data, :gen)

    if all(==(0.0), gen.capt_co2_percent)
        @warn "No carbon capturing generators, yet CCUS Modification provided.  Skipping. (all gen.capt_co2_percent equal to zero)"
        return
    end

    co2_scalar = mod.co2_scalar
    ccus_paths = get_table(data, :ccus_paths)
    ccus_storers = get_table(data, :ccus_storers)
    ccus_producers = get_table(data, :ccus_producers)
    ccus_gen_sets = data[:ccus_gen_sets]::Vector{Vector{Int64}}
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nstor = nrow(ccus_storers)
    nsend = nrow(ccus_producers)

    # Add capacity matching constraints for the sets of ccus_paths generators
    match_capacity!(data, model, :gen, :pcap_gen, :ccus, ccus_gen_sets)

    # Make variables for amount of captured carbon going to each transport step bounded by [0, maximum co2 storage + 1].  This is in units of million metric tons
    @variable(model, 
        co2_trans[ts_idx in 1:nrow(ccus_paths), yr_idx in 1:nyear], 
        lower_bound = 0,
        upper_bound=ccus_paths.step_quantity[ts_idx]/co2_scalar + 1 # NOTE: +1 here to prevent the upper bound from being binding - that would take the shadow price away from the cons_co2_stor constraint.
    ) 

    # Setup expressions for each year's total sequestration cost.
    @expression(model, 
        cost_ccus_obj[yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] * co2_scalar * ccus_paths.price_total[ts_idx] for ts_idx in 1:nrow(ccus_paths))
    )

    # Setup expressions for carbon stored for each of the carbon sequesterers as a function of the co2 transported
    @expression(model, 
        co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] for ts_idx in ccus_storers.path_idxs[stor_idx])
    )
    
    # Constrain the co2 sold to each sequestration step must be less than the step quantity
    @constraint(model, 
        cons_co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear], 
        co2_stor[stor_idx, yr_idx] <= (ccus_storers.step_quantity[stor_idx] / co2_scalar)::Float64
    )

    # Create expression for total CO2 for each sending region of each type
    @expression(model, 
        co2_sent[send_idx in 1:nsend, yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] for ts_idx in ccus_producers.path_idxs[send_idx])
    )

    # Create expression for total CO2 for each sending region of each type
    @expression(model, 
        co2_prod[send_idx in 1:nsend, yr_idx in 1:nyear],
        sum(
            model[:egen_gen][gen_idx, yr_idx, hr_idx] * get_table_num(data, :gen, :capt_co2, gen_idx, yr_idx, hr_idx)
            for gen_idx in ccus_producers.gen_idxs[send_idx], hr_idx in 1:nhour
        )
    )

    # Constrain that co2 captured in a region must equal the CO2 sold in that region. "CO2 balancing constraint"
    # LHS is divided by sqrt of co2_scalar, rhs is multiplied, so that they meet in the middle of coefficient range.
    @constraint(model, 
        cons_co2_bal[send_idx in 1:nsend, yr_idx in 1:nyear], 
        co2_prod[send_idx, yr_idx] / sqrt(co2_scalar) == co2_sent[send_idx, yr_idx] * sqrt(co2_scalar)
    ) 

    add_obj_exp!(data, model, CCUSTerm(), :cost_ccus_obj; oper=+)

    return nothing
end

struct CCUSTerm <: Term end

"""
    modify_results!(mod::CCUS, config, data) 


"""
function modify_results!(mod::CCUS, config, data)
    co2_scalar = mod.co2_scalar
    gen = get_table(data, :gen)

    if all(==(0.0), gen.capt_co2_percent)
        @warn "No carbon capturing generators, yet CCUS Modification provided.  Skipping. (all gen.capt_co2_percent equal to zero)"
        return
    end

    raw_results = get_raw_results(data)
    raw_results[:co2_sent] .*= co2_scalar
    raw_results[:co2_stor] .*= co2_scalar
    raw_results[:co2_trans] .*= co2_scalar
    raw_results[:cons_co2_stor] ./= co2_scalar
    raw_results[:cons_co2_bal] ./= sqrt(co2_scalar)

    ccus_storers = get_table(data, :ccus_storers)
    ccus_producers = get_table(data, :ccus_producers)
    ccus_paths = get_table(data, :ccus_paths)
    co2_sent = get_raw_result(data, :co2_sent)::Matrix{Float64}
    co2_stor = get_raw_result(data, :co2_stor)::Matrix{Float64}
    co2_trans = get_raw_result(data, :co2_trans)::Matrix{Float64}
    cons_co2_stor = get_raw_result(data, :cons_co2_stor)::Matrix{Float64}
    nyear = get_num_years(data)

    add_table_col!(data, :ccus_paths, :stored_co2, [view(co2_trans, i, :) for i in 1:nrow(ccus_paths)], ShortTons, "CO₂ stored via this storage path, in short tons.")
    add_results_formula!(data, :ccus_paths, :stored_co2_total, "SumYearly(stored_co2)", ShortTons, "CO2 stored for the year, in short tons.")
    ccus_paths.price_total_clearing = fill(zeros(nyear), nrow(ccus_paths))

    all(<=(0), cons_co2_stor) || @warn "Shadow prices on CO2 stored should be <= 0! Max value found was $(maximum(cons_co2_stor))"

    # Compute clearing prices for each sending region
    ccus_producers.co2_sent = [view(co2_sent, i, :) for i in 1:nrow(ccus_producers)]
    gdf_producers = groupby(ccus_producers, [:producing_region, :ccus_type])
    df_producers = combine(gdf_producers,
        :path_idxs => ((v)->Ref(vcat(v...))) => :f_path_idxs,
        :gen_idxs =>   ((v)->Ref(vcat(v...))) => :gen_idxs,
        :co2_sent => (co2_sent->Ref(sum(co2_sent))) => :co2_sent,
        :path_idxs => ((v)->Ref([ccus_paths.stor_idx[path_idx] for path_idx in v])) => :stor_idxs
    )

    df_producers.price_capt_co2 = fill(zeros(nyear), nrow(df_producers))
    df_producers.price_capt_co2_trans = fill(zeros(nyear), nrow(df_producers))
    df_producers.price_capt_co2_store = fill(zeros(nyear), nrow(df_producers))
    
    # Add prices to gen table
    add_table_col!(data, :gen, :price_capt_co2, fill(zeros(nyear), nrow(gen)), DollarsPerShortTonCO2Captured, "Region-wide clearing price for the generator to pay for the transport and storage of a short ton of captured CO2")
    add_table_col!(data, :gen, :price_capt_co2_store, fill(zeros(nyear), nrow(gen)), DollarsPerShortTonCO2Captured, "Region-wide average price for the generator to pay for the storage of a short ton of captured CO2")
    add_table_col!(data, :gen, :price_capt_co2_trans, fill(zeros(nyear), nrow(gen)), DollarsPerShortTonCO2Captured, "Region-wide average price for the generator to pay for the transport of a short ton of captured CO2")
    
    # Add results formulas
    add_results_formula!(data, :gen, :cost_capt_co2, "SumHourly(egen,capt_co2,price_capt_co2)", Dollars, "Total cost paid by generators to transport and store a short ton of captured CO2, computed with the clearing price")
    add_results_formula!(data, :gen, :price_capt_co2_per_short_ton, "cost_capt_co2 / capt_co2_total", DollarsPerShortTonCO2Captured, "Average price paid by generators to transport and store a short ton of captured CO2, computed with the clearing price")

    add_results_formula!(data, :gen, :cost_capt_co2_transport, "SumHourly(egen,capt_co2,price_capt_co2_store)", Dollars, "Total cost paid by generators to transport a short ton of captured CO2, computed with the clearing price")
    add_results_formula!(data, :gen, :price_capt_co2_transport_per_short_ton, "cost_capt_co2_transport / capt_co2_total", DollarsPerShortTonCO2Captured, "Average price paid by generators to transport a short ton of captured CO2, computed with the clearing price")

    add_results_formula!(data, :gen, :cost_capt_co2_store, "SumHourly(egen,capt_co2,price_capt_co2_store)", Dollars, "Total cost paid by generators to store a short ton of captured CO2, computed with the clearing price")
    add_results_formula!(data, :gen, :price_capt_co2_store_per_short_ton, "cost_capt_co2_store / capt_co2_total", DollarsPerShortTonCO2Captured, "Average price paid by generators to store a short ton of captured CO2, computed with the clearing price")
    
    
    for row in eachrow(df_producers)
        path_idxs = row.f_path_idxs
        co2_sent = row.co2_sent
        gen_idxs = row.gen_idxs

        # Find the price and index of the cheapest step from this sending region 
        cheapest_price_total, _tmp_idx = findmin(path_idx->ccus_paths.price_total[path_idx], path_idxs)
        cheapest_path_idx = path_idxs[_tmp_idx]

        # Compute the shadow price for this cheapest step to find the clearing price.
        cheapest_stor_idx = ccus_paths.stor_idx[cheapest_path_idx]
        stor_shadow_price = view(cons_co2_stor,cheapest_stor_idx,:) # This should be <= 0 because the shadow price is the incremental cost of increasing the size of the cheapest step.  If the cheapest step is increased, that would result in a savings by the difference in cost of the cheapest step and the current price.
        price_total = cheapest_price_total .- stor_shadow_price

        # Compute the total cost of transport in this sending region, and divide by co2 sent to get average price of transport for this producer
        cost_trans = [sum(co2_trans[path_idx, yr_idx] * ccus_paths.price_trans[path_idx] for path_idx in path_idxs) for yr_idx in 1:nyear]
        price_trans = cost_trans ./ co2_sent

        # Update price_trans to be cheapest transport price for the situations when no co2 was sent.
        for (yr_idx, co2) in enumerate(co2_sent)
            co2 > 0 && continue
            price_trans[yr_idx] = ccus_paths.price_trans[cheapest_path_idx]
        end

        price_stor = price_total - price_trans

        row.price_capt_co2 = price_total
        row.price_capt_co2_trans = price_trans
        row.price_capt_co2_store  = price_stor

        # Add the prices to each of the generators
        for gen_idx in gen_idxs
            gen.price_capt_co2[gen_idx] = price_total
            gen.price_capt_co2_trans[gen_idx] = price_trans
            gen.price_capt_co2_store[gen_idx] = price_stor
        end

        # Add the total clearing price to each of the transport steps
        for path_idx in path_idxs
            ccus_paths.price_total_clearing[path_idx] = price_total
        end
    end

    # Calculate total cost, profit & revenue
    storer_cost = ccus_paths.price_store .* ccus_paths.stored_co2
    storer_revenue = [(ccus_paths.price_total_clearing[i] .- ccus_paths.price_trans[i]) .* ccus_paths.stored_co2[i] for i in 1:nrow(ccus_paths)]
    storer_profit = storer_revenue .- storer_cost

    add_table_col!(data, :ccus_paths, :storer_cost, storer_cost, Dollars, "Total storage cost of CCUS via this pathway, from the perspective of the sequesterer")
    add_table_col!(data, :ccus_paths, :storer_revenue, storer_revenue, Dollars, "Total revenue earned from storage for CCUS via this pathway.  This is the amount paid by the EGU's to the sequesterer, equal to the clearing price minus the transport cost.")
    add_table_col!(data, :ccus_paths, :storer_profit, storer_profit, Dollars, "Total profit earned by storing carbon via this pathway, equal to the revenue minus the cost.")
    add_results_formula!(data, :ccus_paths, :storer_cost_total, "SumYearly(storer_cost)", Dollars, "Total storage cost of CCUS via this pathway, from the perspective of the sequesterer, earned in a year")
    add_results_formula!(data, :ccus_paths, :storer_revenue_total, "SumYearly(storer_revenue)", Dollars, "Total revenue earned from storage for CCUS via this pathway.  This is the amount paid by the EGU's to the sequesterer, equal to the clearing price minus the transport cost, earned in a year.")
    add_results_formula!(data, :ccus_paths, :storer_profit_total, "SumYearly(storer_profit)", Dollars, "Total profit earned by storing carbon via this pathway, equal to the revenue minus the cost, earned in a year")

    add_results_formula!(data, :ccus_paths, :storer_cost_per_short_ton, "storer_cost_total/stored_co2_total", Dollars, "Average storage cost of CCUS per short ton via this pathway, from the perspective of the sequesterer")
    add_results_formula!(data, :ccus_paths, :storer_revenue_per_short_ton, "storer_revenue_total/stored_co2_total", Dollars, "Total revenue earned from storage for CCUS per short ton via this pathway.  This is the amount paid by the EGU's to the sequesterer, equal to the clearing price minus the transport cost.")
    add_results_formula!(data, :ccus_paths, :storer_profit_per_short_ton, "storer_profit_total/stored_co2_total", Dollars, "Total profit earned from storing a short ton of CO2 via this pathway, equal to the revenue minus the cost.")

    # Adjust welfare
    add_to_results_formula!(data, :gen, :variable_cost, "cost_capt_co2") # this gets added to producer welfare
    add_welfare_term!(data, :sequesterer, :ccus_paths, :storer_profit_total, +)    

    # Throw error message if there are profits ≥ 0.
    all(v->all(>=(0), v), ccus_paths.storer_profit) || @warn "All CCUS profits should be ≥ 0, but found $(minimum(minimum, ccus_paths.storer_profit))"
end
export modify_results!