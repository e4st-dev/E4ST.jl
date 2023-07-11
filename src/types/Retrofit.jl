
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

Retrofits `newgen`, a `Dict` containing all the properties of the original generator, but with the `year_retrofit` already updated.  Note that the `capex` should be included in the retrofitted generator WITHOUT the existing generator's capex.  I.e. capex for the retrofit should be only the capital costs for the retrofit, not including the initial capital costs for building the generator.
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

    # Initialize with the Retrofit type
    init!(ret, config, data)
    years = get_years(data)
    retrofits = get!(data, :retrofits, OrderedDict{Int64, Vector{Int64}}())::OrderedDict{Int64, Vector{Int64}}
    ngen = nrow(gen)
    nyr = get_num_years(data)

    # Loop through generators and add retrofits
    for gen_idx in 1:ngen
        row = gen[gen_idx, :]
        row.build_status == "built" || continue
        can_retrofit(ret, row) || continue

        # Add a retrofit candidate for each year
        for yr_idx in 1:nyr
            newgen = Dict(pairs(row))
            # Set year_retrofit
            year = years[yr_idx]
            newgen[:year_retrofit] = year

            #set capex = 0 because original capex of the plant will continue to be paid based on pcap_inv of the pre retrofit generator
            # capex for the retrofit will be added in retrofit!()
            newgen[:capex] = 0
            newgen[:pcap0] = 0

            retrofit!(ret, newgen)
            
            # Set capex_obj
            v = zeros(nyr)
            v[yr_idx:end] .= newgen[:capex]
            newgen[:capex_obj] = ByYear(v)

            # Add newgen to the gen table, add it to retrofits.
            push!(gen, newgen)
            current_gen_retrofit_idxs = get!(retrofits, gen_idx, Int64[])
            push!(current_gen_retrofit_idxs, nrow(gen))
        end
    end

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
    retrofits = data[:retrofits]::OrderedDict{Int64, Vector{Int64}}
    pcap_gen = model[:pcap_gen]::Array{VariableRef, 2}
    pcap_max = gen.pcap_max
    pcap_min = gen.pcap_min

    # Make constraint on the sum of the retrofit capacities
    @constraint(model, 
        cons_pcap_gen_retro_max[
            gen_idx in keys(retrofits),
            yr_idx in 1:nyr
        ],
        sum(ret_idx-> pcap_gen[ret_idx, yr_idx] * (pcap_max[gen_idx] / pcap_max[ret_idx]), retrofits[gen_idx]) + pcap_gen[gen_idx, yr_idx] <= pcap_max[gen_idx]
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
    @constraint(model, 
        cons_pcap_gen_retro_min[
            gen_idx in keys(retrofits),
            yr_idx in 1:nyr
        ],
        sum(ret_idx-> pcap_gen[ret_idx, yr_idx], retrofits[gen_idx]) + pcap_gen[gen_idx, yr_idx] >= pcap_min[gen_idx]
    )

    # Constrain their capacities to be zero before year_retrofit
    @constraint(model,
        cons_pcap_gen_preretro[
            gen_idx = axes(gen, 1),
            yr_idx = 1:nyr;
            (!isempty(gen.year_retrofit[gen_idx]) && years[yr_idx] < gen.year_retrofit[gen_idx])
        ],
        pcap_gen[gen_idx, yr_idx] == 0.0
    )

    # Remove noadd constraints before retrofit
    if haskey(model, :cons_pcap_gen_noadd)
        cons = model[:cons_pcap_gen_noadd]
        for gen_idx in 1:nrow(gen)
            row = gen[gen_idx, :]

            # Check to see if this is a retrofit generator
            isempty(row.year_retrofit) && continue
            retro_yr_idx = findfirst(>=(row.year_retrofit), years)
            retro_yr_idx === nothing && continue # Must be a previously retrofit generator, no need to remove constraints

            for yr_idx in 1:(retro_yr_idx-1)
                delete(model, cons[gen_idx, yr_idx])
            end
        end
    end

    # Add the retrofit capacity to the pcap_gen_inv_sim expression
    expr = model[:pcap_gen_inv_sim]::Vector{AffExpr}
    for gen_idx in 1:nrow(gen)
        row = gen[gen_idx, :]

        # Check to see if this is a retrofit generator
        isempty(row.year_retrofit) && continue
        retro_yr_idx = findfirst(>=(row.year_retrofit), years)
        retro_yr_idx === nothing && continue 

        # Zero out the expression
        add_to_expression!(expr[gen_idx], expr[gen_idx], -1)

        # Add the correct pcap_gen to the expression
        add_to_expression!(expr[gen_idx], pcap_gen[gen_idx, retro_yr_idx])        
    end
    
    return nothing
end

function mod_rank(::Type{R}) where {R<:Retrofit}
    -3.0
end
