
"""
    FuelPrice(;file) <: Modification

FuelPrice is a [`Modification`](@ref) allowing users to specify fuel prices for different fuels by region.  If multiple steps and quantities are given, the fuel price for a given region will be computed endogenously.
* [`modify_raw_data!(mod::FuelPrice, config, data)`](@ref)
* [`modify_setup_data!(mod::FuelPrice, config, data)`](@ref)
* [`modify_model!(mod::FuelPrice, config, data, model)`](@ref)
* [`modify_results!(mod::FuelPrice, config, data)`](@ref)

To adjust price by hour or year, see [`AdjustHourly`](@ref) or [`AdjustYearly`](@ref).
"""
Base.@kwdef struct FuelPrice <: Modification
    file::String
end
export FuelPrice

@doc """
    summarize_table(::Val{:fuel_price})

$(table2markdown(summarize_table(Val(:fuel_price))))
"""
function summarize_table(::Val{:fuel_price})
    df = TableSummary()
    push!(df, 
        (:genfuel, String, NA, true, "The type of fuel that the price applies for. i.e. `ng` or `coal`"),
        (:area, String, NA, true, "The area that the price applies for i.e. `nation`.  Leave blank if grid-wide"),
        (:subarea, String, NA, true, "The subarea that the price applies for i.e. `narnia`.  Leave blank if grid-wide"),
        (:filter_, String, NA, false, "I.e. `filter1`, `filter2`, etc. Other filter conditions that the price applies for, see [`parse_comparison`](@ref) for ideas"),
        (:price, Float64, DollarsPerMMBtu, true, "The price of 1 MMBtu of fuel"),
        (:quantity, Float64, MMBtu, true, "The number of MMBtu of the fuel available at the price in each year.  Set to `Inf` for unlimited."),
    )
    return df
end

"""
    modify_raw_data!(mod::FuelPrice, config, data)

Read table from `mod.file` into `data[:fuel_price]`
"""
function modify_raw_data!(mod::FuelPrice, config, data)
    config[:fuel_price_file] = mod.file
    read_table!(config, data, :fuel_price_file=>:fuel_price)
    return nothing
end

"""
    modify_setup_data!(mod::FuelPrice, config, data)

Zero out the `fuel_price` column of the `gen` table, as it will get overwritten later by this Modification.  This is to avoid double-counting the fuel cost.
""" 
function modify_setup_data!(mod::FuelPrice, config, data)
    # Set the fuel_price table to all zero for the areas affected by `mod`.
    gen = get_table(data, :gen)
    fp = get_table(data, :fuel_price)
    if hasproperty(gen, :fuel_price)
        to_container!(gen, :fuel_price)
        v = fill(0.0, get_num_years(data))
        gdf = groupby(fp, Not([:price, :quantity]))
        for sdf in gdf
            row = sdf[1,:]
            gen_idxs = get_row_idxs(gen, parse_comparisons(row))
            for gen_idx in gen_idxs
                gen.fuel_price[gen_idx] = set_yearly(gen.fuel_price[gen_idx], v)
            end
        end
    else
        bn = ByNothing(0.0)
        gen.fuel_price = Container[bn for _ in axes(gen,1)]
    end
end

"""
    modify_model!(mod::FuelPrice, config, data, model)

* Make `data[:fuel_markets]` to keep track of each of the fuel markets
* Add variable `fuel_sold[fuel_price_idx,  yr_idx, hr_idx]`: total fuel sold at each price step for each time interval
* Add expression `fuel_used[fuel_market_idx, yr_idx, hr_idx]`: total fuel used by generators for each market region for each time interval
* Add expression `fuel_price_obj[fuel_market_idx, yr_idx, hr_idx]`: total cost of the fuel, added to the objective.
* Add constraint `cons_fuel_sold[fuel_price_idx, yr_idx]`: constrain the total `fuel_sold` in each year to be ≤ yearly quantity
* Add constraint `cons_fuel_bal[fuel_market_idx, yr_idx, hr_idx]`: constrain the amount of fuel sold in each market region to equal the amount of fuel used in each market region.
"""
function modify_model!(mod::FuelPrice, config, data, model)
    @info "Adding endogenous fuel prices to the model via FuelPrice Modification"

    table = get_table(data, :fuel_price)
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    heat_rate = get_table_col(data, :gen, :heat_rate)
    gen = get_table(data, :gen)

    # Make a DataFrame with each row being a fuel market.
    filter_cols = filter!(contains("filter"), names(table))
    gdf = groupby(table, [:genfuel, :area, :subarea, filter_cols...])
    fuel_markets = combine(gdf, _get_row_idxs)
    rename!(fuel_markets, :x1=>:fuel_price_idxs)
    fuel_markets.filters = map(parse_comparisons, eachrow(fuel_markets))
    fuel_markets.gen_idxs = map(fuel_markets.filters) do filt
        idxs = get_row_idxs(gen, filt)
        isempty(idxs) && @warn "No generators found for fuel market with filters $filt, removing from table"
        return idxs
    end

    filter!(:gen_idxs=>!isempty, fuel_markets)

    # Pull out other necessary data
    data[:fuel_markets] = fuel_markets
    egen = model[:egen_gen]

    # Create variable fuel_sold for fuel sold in each row of the fuel table
    @info "Create variable fuel_sold for each price step"
    @variable(model,
        fuel_sold[
            fuel_idx in axes(table, 1),
            yr_idx in 1:nyr,
        ],
        lower_bound=0
    )

    # Create objective expression for fuel cost
    @info "Create expression fuel_cost_obj for each price step"
    @expression(model,
        fuel_cost_obj[
            fuel_idx in axes(table, 1),
            yr_idx in 1:nyr,
        ],
        fuel_sold[fuel_idx, yr_idx] * table.price[fuel_idx][yr_idx, :]
    )

    # Add fuel_cost_obj to the objective function
    add_obj_exp!(data, model, FuelCostTerm(), :fuel_cost_obj; oper=+)

    # Create an expression fuel_used for total fuel used by generators for each genfuel-area-subarea combo over a year.
    @info "Create expression fuel_used for each price step"
    @expression(model,
        fuel_used[
            fm_idx in axes(fuel_markets,1),
            yr_idx in 1:nyr
        ],
        sum(
            (egen[gen_idx, yr_idx, hr_idx] * heat_rate[gen_idx][yr_idx, hr_idx])
            for gen_idx in fuel_markets.gen_idxs[fm_idx], hr_idx in 1:nhr
        )
    )

    # Set upper bound of fuel_sold to help the problem be more bounded, even though these will likely not be binding.
    @info "Set upper bound of fuel_sold"
    for (idx, quantity) in enumerate(table.quantity)
        for yr_idx in 1:nyr
            isfinite(quantity[yr_idx, :]) || continue
            set_upper_bound.(fuel_sold[idx, yr_idx], quantity[yr_idx, :] + 1) # plus one to prevent this from binding instead of `cons_fuel_sold`
        end
    end

    # Constrain the fuel sold for each row for each year to be less than or equal to the quantity
    @info "Add cons_fuel_sold constraint for each price step"
    @constraint(model,
        cons_fuel_sold[
            fuel_idx in axes(table,1),
            yr_idx in 1:nyr;
            isfinite(table.quantity[fuel_idx][yr_idx, :])
        ],
        fuel_sold[fuel_idx, yr_idx] <= table.quantity[fuel_idx][yr_idx, :]
    )

    # Constrain sum of fuel_sold in each genfuel-area-subarea combo to equal the fuel_used expression.
    @info "Add cons_fuel_bal for each fuel region"
    @constraint(model,
        cons_fuel_bal[
            fm_idx in axes(fuel_markets, 1),
            yr_idx in 1:nyr
        ],
        sum0(
            fuel_idx -> fuel_sold[fuel_idx, yr_idx],
            fuel_markets.fuel_price_idxs[fm_idx]
        ) == fuel_used[fm_idx, yr_idx]
    )
end

"""
    modify_results!(mod::FuelPrice, config, data)

* Calculate the clearing price for each market region for each fuel type.
    * Equal to the shadow price of `cons_fuel_sold` for the cheapest fuel price step in the region plus the cheapest fuel price
    * Add it to `fuel_markets.clearing_price` column
    * Update `gen.fuel_price` column to use the clearing price (multiplied by the `heat_rate` column)
"""
function modify_results!(mod::FuelPrice, config, data)
    cons_fuel_sold = get_raw_result(data, :cons_fuel_sold)
    fuel_used = get_raw_result(data, :fuel_used)
    fuel_price = get_table(data, :fuel_price)
    fuel_markets = get_table(data, :fuel_markets)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    gen = get_table(data, :gen)

    cp = Container[ByNothing(0.0) for _ in axes(fuel_markets, 1)]

    add_table_col!(data, :fuel_markets, :clearing_price, cp, DollarsPerMMBtuSold, "Annual clearing price, in Dollars per MMBtu of energy.")
    
    add_table_col!(data, :fuel_markets, :fuel_sold, fuel_used, MMBtu, "Quantity of fuel sold into this market, in MMBtu")

    add_results_formula!(data, :fuel_markets, :fuel_cost, "SumYearly(fuel_sold,clearing_price)", Dollars, "Total cost of fuel sold in the market(s) (using the clearing price)")
    add_results_formula!(data, :fuel_markets, :fuel_sold_total, "SumYearly(fuel_sold)", MMBtu, "Total amount of fuel sold in the market(s)")
    add_results_formula!(data, :fuel_markets, :fuel_clearing_price_per_mmbtu, "fuel_cost/fuel_sold_total", DollarsPerMMBtuSold, "Average price of fuel paid to these market(s).  Computed using the clearing price")

    # Compute the clearing price for each genfuel-area-subarea combo
    # The clearing price would be the shadow price + the price of the cheapest fuel option in each region.
    for row in eachrow(fuel_markets)
        # Find the index of the cheapest fuel price for each year in the market region
        fp_idxs = [argmin(pf_idx->mean(fuel_price.price[pf_idx][yr_idx, :]), row.fuel_price_idxs) for yr_idx in 1:nyr]

        for gen_idx in row.gen_idxs
            @assert all(==(0), gen.fuel_price[gen_idx]) "Found non-zero fuel_price in gen table with FuelPrice Modification.  That could mean double-counting of fuel cost in the objective function!"
        end
    

        
        # Find the shadow price of the fuel sold constraint.  I.e. the change in objective value, in dollars per MMBtu, by relaxing the `cons_fuel_sold` constraint.  
        # I.e. if we allowed one more unit of the cheaper fuel, this value is the difference between the clearing price and the price of the cheapest fuel.
        shad_price = ByYear([
            (haskey(cons_fuel_sold, (fp_idxs[yr_idx], yr_idx)) ? cons_fuel_sold[fp_idxs[yr_idx], yr_idx] : 0.0)
            for yr_idx in 1:nyr
        ])
        
        row.clearing_price = fuel_price.price[fp_idxs] .- shad_price
        for gen_idx in row.gen_idxs
            gen.fuel_price[gen_idx] = row.clearing_price
        end
    end
end

struct FuelCostTerm <: Term end

_get_row_idxs(sdf) = Ref(getfield(sdf, :rows))