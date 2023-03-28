"""
    struct CCUS <: Modification

    CCUS(;file, groupby)

This is a [`Modification`](@ref) that sets up markets for carbon captured by generators.  
* `file` - a file to the table containing markets/prices for buying/selling carbon dioxide.  See the `ccus` table below, or [`summarize_table(::Val{:ccus})`](@ref)
* `groupby` - a String indicating how markets are grouped.  I.e. "state".

Creates the following tables in `data`:
* `ccus` - contains all pathways possible to sell CO₂.  
    * `producer` - The producing region
    * `storer` - The storing region of the pathway
    * `ccus_type` - the type of ccus (`eor` or `saline`)
    * `step_num` - the number of the step (not very important other than for book-keeping)
    * `step_quantity` - the quantity of CO₂ that can be stored in this step
    * `price_trans` - the cost to transport 1 short ton of CO₂ from `producer` to `storer`
    * `price_store` - the cost to store 1 short ton of CO₂ in the step
* `ccus_storers` - contains all the storers
    * `storer` - the storing region
    * `step_num` - the number of the step for the region
    * `ccus_type` - whether the step is `eor` or `saline`.
    * `step_quantity` - the number of short tons that may be stored in the step
    * `price_store` - the price to store a short ton of CO₂.
    * `trans_idxs` - A list of indices representing the transportation paths to store carbon in this step.  Indexes into `ccus` table.
* `ccus_senders` - contains all the senders, grouped by `ccus_type` and `producer` region.  This contains the following columns:
    * `producer` - the region the CO₂ will be sent from
    * `ccus_type` - the type of the step the CO₂ will be sent to (`eor` or `saline`)
    * `trans_idxs` - A list of indices representing the transportation paths to send carbon from this step.  Indexes into `ccus` table.
    * `gen_idxs` - A list of generator indices that produce CO₂ in this region.

Creates the following variables/expressions
* `co2_trans[1:nrow(ccus), 1:nyear]` - the amount of CO₂ transported along this sender-producer pathway (variable)
* `co2_stored[1:nrow(ccus_storers), 1:nyear]` - the amount of CO₂ stored by each storer (expression of `co2_trans`)
* `co2_prod[1:nrow(ccus_senders), 1:nyear]` - the amount of CO₂ produced by each sending region (expression of electricity generation)
* `co2_sent[1:nrow(ccus_senders), 1:nyear]` - the amount of CO₂ sent out from each sending region (expression of `co2_stored`)
* `cost_ccus[1:nyear]` - the total cost of ccus, as added to the objective function.

Creates the following constraints
* `cons_co2_stor[1:nrow(ccus_storers), 1:nyear]` - the CO₂ stored at each injection site must not exceed `step_quantity`
* `cons_co2_bal[1:nrow(ccus_senders), 1:nyear]` - the CO₂ balancing equation for each region, i.e. `co2_prod == co2_sent`.
"""
struct CCUS <: Modification
    file::String # This would point to the file containing the CCUS market
    groupby::String
end
function CCUS(;file, groupby)
    CCUS(file, groupby)
end
export CCUS

"""
    summarize_table(::Val{:ccus}) -> summary
"""
function summarize_table(::Val{:ccus})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:producer, String, NA, true, "The name of the producing region (type of regions specified by groupby kwarg of CCUS mod"),
        (:storer, String, NA, true, "The name of the sequestering region (type of regions specified by groupby kwarg of CCUS mod"),
        (:step_num, Int64, NA, true, "The number of this particular market step"),
        (:ccus_type, String, NA, true, "The type of storage.  Can be \"eor\" or \"saline\""),
        (:step_quantity, Float64, ShortTonsPerYear, true, "The annual quantity of CO2 that can be stored in the step"),
        (:price_trans, Float64, DollarsPerShortTon, true, "The cost of transporting a short ton of CO2 for this producer-storer pair"),
        (:price_store, Float64, DollarsPerShortTon, true, "The cost to store a short ton of CO2 in this storage step"),
    )
    return df
end 

"""
    modify_raw_data!(mod::CCUS, config, data) -> nothing

Loads `mod.file` into `data[:ccus]`.  See [`summarize_table(::Val{:ccus})`](@ref) for more info.
"""
function modify_raw_data!(mod::CCUS, config, data)
    config[:ccus_file] = mod.file
    load_table!(config, data, :ccus_file => :ccus)
    return nothing
end

"""
    modify_setup_data!(mod::CCUS, config, data) -> nothing

Does the following:
* Adds a column for carbon captured, `capt_co2`, based on `emis_co2`, and `capt_co2_percent`
* reduces `emis_co2`by `capt_co2`
* Splits up carbon capturing generators into 2
* Add a column for `ccus_type` - either "eor", "saline", or "na"
* Adds sets of indices to `data[:ccus_gen_sets]::Vector{Vector{Int64}}` 
"""
function modify_setup_data!(mod::CCUS, config, data)
    # TODO: think through how to un-group ccus matched generators, and how we would want to handle saving them and loading them in
    update_ccus_gens!(mod, config, data)


    ### Modify ccus
    ccus = get_table(data, :ccus)
    gen = get_table(data, :gen)
    add_table_col!(data, :ccus, :trans_idx, 1:nrow(ccus), NA, "The index of this path")
    add_table_col!(data, :ccus, :price_total, (ccus.price_trans .+ ccus.price_store), DollarsPerShortTon, "The cost of transporting and storing a short ton of CO₂ in this storage pathway")


    ### Make ccus_storers
    # Gather all the sequestration steps.  There could be multiple steps per region, and multiple ccus options per step, from different producing regions
    gdf_storers = groupby(ccus, [:storer, :step_num])

    # Assert that all the members of each sequestration step have the same quantity
    @assert all(allequal(sdf.step_quantity) for sdf in gdf_storers) "Carbon sequestration steps must have the same step_quantity!"
    @assert all(allequal(sdf.price_store) for sdf in gdf_storers) "Carbon sequestration steps must have the same price_store!"
    @assert all(allequal(sdf.ccus_type) for sdf in gdf_storers) "Carbon sequestration steps must have the same ccus_type"

    ccus_storers = combine(gdf_storers,
        :ccus_type => first => :ccus_type,
        :step_quantity => first => :step_quantity,
        :price_store => first => :price_store,
        :trans_idx => Ref => :trans_idxs,
    )
    ccus_storers.stor_idx = 1:nrow(ccus_storers)
    data[:ccus_storers] = ccus_storers


    ### Make ccus_senders
    # Group ccus by the producing region and ccus_type
    gdf_senders = groupby(ccus, [:producer, :ccus_type])
    gdf_gen = groupby(gen, Cols(mod.groupby, :ccus_type))

    # Add the generators together for the producer-type combos
    ccus_senders = combine(gdf_senders,
        :trans_idx => Ref => :trans_idxs,
    )

    transform!(ccus_senders,
        [:producer, :ccus_type] => 
        ByRow((key...) -> (haskey(gdf_gen, key) ? getfield(gdf_gen[key], :rows) : Int64[]))
        => :gen_idxs
    )

    data[:ccus_senders] = ccus_senders

end
export modify_setup_data!


"""
    update_ccus_gens!(mod::CCUS, config, data) -> 

Updates the carbon capturing generators
"""
function update_ccus_gens!(mod::CCUS, config, data)
    gen = get_table(data, :gen)
    @assert hasproperty(gen, :capt_co2_percent) "gen table must have column for `capt_co2_percent` for CCUS"
    @assert hasproperty(gen, :emis_co2) "gen table must have column for `capt_co2_percent` for CCUS"

    capt_co2 = gen.emis_co2 .* gen.capt_co2_percent # This may make an OriginalContainer with the original value for emis_co2 preserved, but that should be ok since this column isn't kept in save_updated_gen_table.
    add_table_col!(data, :gen, :capt_co2, capt_co2, ShortTonsPerMWhGenerated, "The rate of capture of CO2 (calculated from emis_co2 and capt_co2_percent)")


    # Turn emis_co2 into a vector of Containers for book-keeping.
    gen.emis_co2 = Container[Container(e) for e in gen.emis_co2]
    gen.emis_co2 .-= gen.capt_co2

    # Add column for ccus_type
    ccus_type = fill("na", nrow(gen))
    add_table_col!(data, :gen, :ccus_type, ccus_type, NA, "The type way the captured carbon will be utilized.  Either `saline` or `eor`.")
    ccus_types = unique(data[:ccus].ccus_type)

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
    elseif ccus_types==1
        # If all one type, then assign to that type
        ccus_idxs = get_row_idxs(gen, :capt_co2=> >(0))
        gen[ccus_idxs, :ccus_type] = first(ccus_types)
    end

    # Update emission rate for EOR
    gen_eor = get_subtable(gen, :ccus_type=>"eor")
    eor_leakage_rate = get(config, :eor_leakage_rate, 0.5)
    gen_eor.emis_co2 .+=  eor_leakage_rate * gen_eor.capt_co2

    # TODO: add eor_leakage_rate to config 
end
export update_ccus_gens!

function modify_model!(mod::CCUS, config, data, model)

    # Pull in the tables
    gen = get_table(data, :gen)
    ccus = get_table(data, :ccus)
    ccus_storers = get_table(data, :ccus_storers)
    ccus_senders = get_table(data, :ccus_senders)
    ccus_gen_sets = data[:ccus_gen_sets]::Vector{Vector{Int64}}
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nstor = nrow(ccus_storers)
    nsend = nrow(ccus_senders)

    # Add capacity matching constraints for the sets of ccus generators
    match_capacity!(data, model, ccus_gen_sets, :ccus)



    # Make variables for amount of captured carbon going each of the carbon markets bounded by [0, maximum co2 storage]
    @variable(model, co2_trans[ts_idx in 1:nrow(ccus), yr_idx in 1:nyear], lower_bound = 0, upper_bound=ccus.step_quantity[ts_idx])

    # Setup expressions for each year's total sequestration cost.
    @expression(model, 
        cost_ccus[yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] * ccus.price_total[ts_idx] for ts_idx in 1:nrow(ccus))
    )

    # Setup expressions for carbon stored for each of the carbon sequesterers as a function of the co2 transported
    @expression(model, 
        co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] for ts_idx in ccus_storers.trans_idxs[stor_idx])
    )
    
    # Constrain the co2 sold to each sequestration step must be less than the step quantity
    @constraint(model, 
        cons_co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear], 
        co2_stor[stor_idx, yr_idx] <= ccus_storers.step_quantity[stor_idx]::Float64
    )

    # Create expression for total CO2 for each sending region of each type
    @expression(model, 
        co2_sent[send_idx in 1:nsend, yr_idx in 1:nyear],
        sum(co2_trans[ts_idx, yr_idx] for ts_idx in ccus_senders.trans_idxs[send_idx])
    )

    # Create expression for total CO2 for each sending region of each type
    @expression(model, 
        co2_prod[send_idx in 1:nsend, yr_idx in 1:nyear],
        sum(
            model[:egen_gen][gen_idx, yr_idx, hr_idx] * get_table_num(data, :gen, :capt_co2, gen_idx, yr_idx, hr_idx)
            for gen_idx in ccus_senders.gen_idxs[send_idx], hr_idx in 1:nhour
        )
    )

    # Constrain that co2 captured in a region must equal the CO2 sold in that region. "CO2 balancing constraint"
    @constraint(model, 
        cons_co2_bal[send_idx in 1:nsend, yr_idx in 1:nyear], 
        co2_prod[send_idx, yr_idx] == co2_sent[send_idx, yr_idx])

    add_to_expression!(model[:obj], sum(cost_ccus))

    data[:ccus_storers] = ccus_storers
    data[:ccus_senders] = ccus_senders

    return nothing
end

"""
    modify_results!(mod::CCUS, config, data) 


"""
function modify_results!(mod::CCUS, config, data)
end
export modify_results!