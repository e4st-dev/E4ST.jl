
"""
    Retrofit <: Modification

Abstract supertype for retrofits.  Must implement the following interfaces:
* (required) [`can_retrofit(ret::Retrofit, gen::DataFrameRow)`](@ref)` -> ::Bool` - returns whether or not a generator row can be retrofitted.
* (required) [`retrofit!(ret::Retrofit, gen)`](@ref)` -> newgen::AbstractDict` - returns a new row to be added to the gen table.
* (optional) [`init!(ret::Retrofit, config, data)`](@ref) - initialize data with the `Retrofit` by adding any necessary columns to the gen table, etc.  Defaults to do nothing.

The following methods are defined for `Retrofit`, so you do not define any of the ordinary `Modification` methods for any subtype of `Retrofit` - only implement the above interfaces.
* [`modify_setup_data!(ret::Retrofit, config, data)`](@ref)
* [`modify_model!(ret::Retrofit, config, data, model)`](@ref)
"""
abstract type Retrofit <: Modification end
export Retrofit

"""
    can_retrofit(ret::Retrofit, row) -> ::Bool

Returns whether or not a generator row can be retrofitted.
"""
function can_retrofit end
export can_retrofit

"""
    retrofit!(ret::Retrofit, newgen) -> ::AbstractDict

This function should change `newgen` to have the properties of the retrofit.  `newgen` is a `Dict` containing all the properties of the original generator, but with the the following fields already changed:
* `year_retrofit` - set to the year to be retrofitted
* `retrofit_original_gen_idx` - set to the index of the gen table for the original generator
* `capex` - set to 0 to avoid double-paying capex for the already-built generator.  Capex added to `newgen` should only be the capital costs for the retrofit itself.  E4ST should already be accounting capex in `past_capex` for the original generator.
* `pcap0` - set to 0
* `transmission_capex` - set to 0
* `build_status` - set to `unretrofitted`
"""
function retrofit! end
export retrofit!

"""
    init!(ret::Retrofit, config, data)

initialize data with the `Retrofit` by adding any necessary columns to the gen table, etc.  Defaults to do nothing.
"""
function init!(ret::Retrofit, config, data) end

"""
    modify_setup_data!(ret::Retrofit, config, data)

* Calls [`init!(ret::Retrofit, config, data)`](@ref) to initialize the data.
* Makes a `Dict` in `data[:retrofits]` to keep track of the retrofits being produced for each retrofit.
* Loops through the rows of the `gen` table
    * Checks to see if the can be retrofitted via [`can_retrofit(ret::Retrofit, row)`](@ref)
    * Constructs the new retrofitted generator via [`retrofit!(ret::Retrofit, row)`](@ref)
    * Constructs one new one for each year in the simulation.
"""
function modify_setup_data!(ret::Retrofit, config, data)

    @info "Setting up retrofits for $ret"

    # Add year_retrofit column to the gen table
    gen = get_table(data, :gen)
    hasproperty(gen, :year_retrofit) || add_table_col!(data, :gen, :year_retrofit, fill("", nrow(gen)), Year, "Year in which the unit was retrofit, or blank if not a retrofit.")
    hasproperty(gen, :retrofit_original_gen_idx)  || add_table_col!(data, :gen, :retrofit_original_gen_idx, fill(-1, nrow(gen)), NA, "Index of the original generator of a retrofit. `-1` if not a retrofit.")

    # Initialize with the Retrofit type
    init!(ret, config, data)
    years = get_years(data)
    ngen = nrow(gen)
    nyr = get_num_years(data)

    # Loop through generators and add retrofits
    for gen_idx in 1:ngen
        row = gen[gen_idx, :]
        row.build_status == "built" || continue
        can_retrofit(ret, row) || continue

        # Add a retrofit candidate for each year
        for yr_idx in 1:nyr
            newgen = deepcopy(Dict(pairs(row)))

            # Set year_retrofit
            year = years[yr_idx]
            newgen[:year_retrofit] = year
            newgen[:retrofit_original_gen_idx] = gen_idx

            #set capex = 0 because original capex of the plant will continue to be paid based on pcap_inv of the pre retrofit generator
            # capex for the retrofit will be added in retrofit!()
            newgen[:capex] = 0
            newgen[:pcap0] = 0
            newgen[:transmission_capex] = 0
            newgen[:build_status] = "unretrofitted"

            retrofit!(ret, newgen)
            
            # Add newgen to the gen table, add it to retrofits.
            push!(gen, newgen)
        end
    end

    original_gen_cols = data[:gen_table_original_cols]::Vector{Symbol}
    (:year_retrofit in original_gen_cols) || push!(original_gen_cols, :year_retrofit)

    @info "Added $(nrow(gen) - ngen) retrofit generators to gen table"
end

"""
    modify_model!(ret::Retrofit, config, data, model)

Modifies the model for retrofits.  Only happens once, for all retrofits.
* Constrains the sum of the capacities of the original generators and the retrofits is less than the original max and greater than the original min by adding constraints `cons_pcap_gen_retro_min` and `cons_pcap_gen_retro_max`
* Removes the `cons_pcap_gen_noadd` constraints for prior to and on the retrofit year.
* Fix the capacity of the new retrofit generators to 0 before the retrofit year.
"""
function modify_model!(ret::Retrofit, config, data, model)
    # Only add constraints if it hasn't been done yet.  This will add constraints for all the Retrofit types
    haskey(model, :cons_pcap_gen_retro_max) && return

    # Fetch necessary data
    nyr = get_num_years(data)
    gen = get_table(data, :gen)
    years = get_years(data)
    pcap_gen = model[:pcap_gen]::Array{VariableRef, 2}
    pcap_max = gen.pcap_max
    pcap_min = gen.pcap_min

    # Make a Dict of retrofits to be generated, mapping original generator to retrofit(s)
    retrofits = get!(data, :retrofits, OrderedDict{Int64, Vector{Int64}}())::OrderedDict{Int64, Vector{Int64}}
    original_idxs = gen.retrofit_original_gen_idx::Vector{Int64}
    for (gen_idx, original_idx) in enumerate(original_idxs)
        if original_idx > 0
            current_gen_retrofit_idxs = get!(retrofits, original_idx, Int64[])
            push!(current_gen_retrofit_idxs, gen_idx)
        end
    end

    # Make constraint on the sum of the retrofit capacities
    # retrofit capacity is scaled by the ratio of original pcap_max over retrofit pcap_max so that penalty losses are included in max constraint
    # e.g. if pcap_max for a gen is 500 MW, its retrofit pcap_max might only be 450 MW because of penalties - need to scale up so that penalty is considered in constraint
    # @constraint(model, 
    #     cons_pcap_gen_retro_max[
    #         gen_idx in keys(retrofits),
    #         yr_idx in 1:nyr
    #     ],
    #     sum(ret_idx-> pcap_gen[ret_idx, yr_idx] * (pcap_max[gen_idx, yr_idx] / pcap_max[ret_idx, yr_idx]), retrofits[gen_idx]) + pcap_gen[gen_idx, yr_idx] <= pcap_max[gen_idx, yr_idx]
    # ) 
    @constraint(model,
    cons_pcap_gen_retro_max[
        gen_idx in keys(retrofits),
        yr_idx in 1:nyr
    ],
    sum(
        ret_idx -> pcap_gen[ret_idx, yr_idx] *
                   (pcap_max[ret_idx, yr_idx] == 0.0 ? 0.0 : pcap_max[gen_idx, yr_idx] / pcap_max[ret_idx, yr_idx]), # catches divisions by zero when pcap_max is zero
        retrofits[gen_idx]
    ) + pcap_gen[gen_idx, yr_idx] <= pcap_max[gen_idx, yr_idx]
)

    # Lower bound the capacities with zero
    for gen_idx in keys(retrofits)
        ret_idxs = retrofits[gen_idx]
        for yr_idx in 1:nyr
            ~is_fixed(pcap_gen[gen_idx, yr_idx]) && set_lower_bound(pcap_gen[gen_idx, yr_idx], 0.0)
            for ret_idx in ret_idxs
                ~is_fixed(pcap_gen[ret_idx, yr_idx]) && set_lower_bound(pcap_gen[ret_idx, yr_idx], 0.0) 
            end
        end
    end

    # Constrain the capacities to add up to the desired min capacity
    # scaling up for the penalty loss is not necessary for a min constraint
    # pcap_min does not change across years, so is only indexed by gen_idx
    @constraint(model, 
        cons_pcap_gen_retro_min[
            gen_idx in keys(retrofits),
            yr_idx in 1:nyr
        ],
        sum(ret_idx-> pcap_gen[ret_idx, yr_idx], retrofits[gen_idx]) + pcap_gen[gen_idx, yr_idx] >= pcap_min[gen_idx]
    )

    # Constrain their capacities to be zero before year_retrofit
    for gen_idx = axes(gen,1), yr_idx = 1:nyr
        (!isempty(gen.year_retrofit[gen_idx]) && years[yr_idx] < gen.year_retrofit[gen_idx]) || continue
        fix(pcap_gen[gen_idx, yr_idx], 0.0, force=true)
    end
        
    return nothing
end

function mod_rank(::Type{R}) where {R<:Retrofit}
    -3.0
end
