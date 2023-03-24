"""
    struct CCUS <: Modification

    CCUS(;file, groupby)

This is a [`Modification`](@ref) that sets up markets for carbon captured by generators.  
* `file` - a file to the table containing markets/prices for buying/selling carbon dioxide.
* `groupby` - a String indicating how markets are grouped.  I.e. "state".
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
        (:stor_type, String, NA, true, "The type of storage.  Can be \"eor\" or \"saline\""),
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

function modify_model!(mod::CCUS, config, data, model)

    # Pull in the table
    gen = get_table(data, :gen)
    ccus = get_table(data, :ccus)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)

    ccus.trans_idx = 1:nrow(ccus)
    price_total = (ccus.price_trans .+ ccus.price_store)::Vector{Float64}

    # Gather all the sequestration steps.  There could be multiple steps per region, and multiple ccus options per step, from different producing regions
    gdf_seq = groupby(ccus, [:storer, :step_num])

    # Assert that all the members of each sequestration step have the same quantity
    @assert all(allequal(sdf.step_quantity) for sdf in gdf_seq) "Carbon sequestration steps must have the same step_quantity!"
    @assert all(allequal(sdf.price_store) for sdf in gdf_seq) "Carbon sequestration steps must have the same price_store!"
    @assert all(allequal(sdf.stor_type) for sdf in gdf_seq) "Carbon sequestration steps must have the same stor_type"

    for (i, sdf) in enumerate(gdf_seq)
        sdf[!, :stor_idx] .= i # Technically this introduces missings but should be ok
    end

    storers = combine(gdf_seq,
        :stor_type => first => :stor_type,
        :step_quantity => first => :step_quantity,
        :price_store => first => :price_store,
        :trans_idx => Ref => :trans_idxs,
    )
    nstor = nrow(storers)
    stor2trans = storers.trans_idxs::Vector{SubArray{Int64, 1, Vector{Int64}, Tuple{SubArray{Int64, 1, Vector{Int64}, Tuple{UnitRange{Int64}}, true}}, false}}

    # Make variables for amount of captured carbon going each of the carbon markets bounded by [0, maximum co2 storage]
    @variable(model, co2_trans_seq[ts_idx in 1:nrow(ccus), yr_idx in 1:nyear], lower_bound = 0, upper_bound=ccus.step_quantity[ts_idx])

    # Setup expressions for each year's total sequestration cost.
    @expression(model, 
        cost_ccus[yr_idx in 1:nyear],
        sum(co2_trans_seq[ts_idx, yr_idx] * price_total[ts_idx] for ts_idx in 1:nrow(ccus))
    )

    # Setup expressions for carbon stored for each of the carbon sequesterers as a function of the co2 transported
    @expression(model, 
        co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear],
        sum(co2_trans_seq[ts_idx, yr_idx] for ts_idx in stor2trans[stor_idx])
    )
    
    # Constrain the co2 sold to each sequestration step must be less than the step quantity
    @constraint(model, cons_co2_stor[stor_idx in 1:nstor, yr_idx in 1:nyear], co2_stor[stor_idx, yr_idx] <= storers[stor_idx, :step_quantity]::Float64)

    ## Constrain the total amount of carbon sold in markets to be the amount captured by the generator
    
    # Group the generators by region
    gdf_gen_region = groupby(gen, mod.groupby)
    regions = collect(k[1] for k in keys(gdf_gen_region))
    sort!(regions)

    # Create an expression for the total CO2 captured by generators in each region.  Sum over the capt_co2 of the region
    @expression(model, 
        co2_capt_region[region in regions, yr_idx in 1:nyear], 
        sum(
            sum(model[:egen_gen][gen_idx, yr_idx, hr_idx] * get_table_num(data, :gen, :capt_co2, gen_idx, yr_idx, hr_idx))
            for gen_idx in getfield(gdf_gen_region[(region,)], :rows), hr_idx in 1:nhour
        )
    )

    # Group ccus by the producing region and ensure that there is a producing region for every region in the generator set.
    gdf_ccus_prod = groupby(ccus, :producer)
    @assert all(haskey(gdf_ccus_prod, (region,)) for region in regions)
    
    # Create an expression for the total CO2 sold within each region
    @expression(model, co2_trans_region[region in regions, yr_idx in 1:nyear], sum(co2_trans_seq[ts_idx, yr_idx] for ts_idx in getfield(gdf_ccus_prod[(region,)], :rows)))

    # Constrain that co2 captured in a region must equal the CO2 sold in that region "CO2 balancing constraint"
    @constraint(model, cons_co2_bal_region[region in regions, yr_idx in 1:nyear], co2_capt_region[region, yr_idx] == co2_trans_region[region, yr_idx])

    return nothing
end