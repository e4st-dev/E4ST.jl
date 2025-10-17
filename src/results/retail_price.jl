"""
    setup_retail_price!(config, data)

Sets up the retail price structure. 
Add in retail price terms to calculate retail electricity rates in \$/MWh.

The relevant price terms are:
* `electricity_cost`
* `distribution_cost_total`
* `merchandising_surplus_total`
* `cost_of_service_rebate`
* `net_production_cost`
* `baa_reserve_requirement_cost`
* `baa_reserve_requiremetn_merchandising_surplus_total`
Reference the results formulas for more detailed descriptions of each of these terms.

The results template can calculate annual rates by specified region, but is not set up for hourly rates. 


There are three specialized methods for calculating the retail rate that depend on the cal_mode argument in the RetailPrice mod. If cal_mode is set to `none`
there will be no calibration steps. If it is set to `get_cal_values`, the function will find the difference between the estimated retail rates
and the true retail rate to use as a calibrator value. If cal_mode is set to `calibrate`, the corresponding calibrator vaulue will be added to the retail price.
"""

# adjust calibrator table to be read in with right format, or change function to read in correctly

function setup_retail_price!(config, data)
    retail_price = OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}()
    data[:retail_price] = retail_price

    # price terms for average electricity rate
    add_price_term!(data, :avg_elec_rate, :bus, :electricity_cost, +)

    # per MW cost adder for distribution costs
    add_price_term!(data, :avg_elec_rate, :bus, :distribution_cost_total, +)

    # merchandising suplus is from selling electricity for higher price at one end of line than another
    add_price_term!(data, :avg_elec_rate, :bus, :merchandising_surplus_total, -)

    # if the difference between revenue and total costs is positive, customers in COS regions get a rebate
    # total cost includes production costs, net policy costs, gs_rebate, and the net of past investment costs and subsidies 
    add_price_term!(data, :avg_elec_rate, :gen, :cost_of_service_rebate, -)
    add_price_term!(data, :avg_elec_rate, :storage, :cost_of_service_rebate, -)

    # add_price_term!(data, :avg_elec_rate, :bus, :gs_payment, +)

    if haskey(config, :past_invest_file)
        add_price_term!(data, :avg_elec_rate, :past_invest, :cost_of_service_past_costs, +)
    end

    if haskey(config, :mods) && haskey(config[:mods], :baa_reserve_requirement)
        add_price_term!(data, :avg_elec_rate, :bus, :baa_reserve_requirement_cost, +)
        add_price_term!(data, :avg_elec_rate, :bus, :baa_reserve_requirement_merchandising_surplus_total, -)
    end

end
export setup_retail_price!

"""
    get_retail_price(data) -> retail_price::OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}
"""
function get_retail_price(data)
    return data[:retail_price]::OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}
end
export get_retail_price

"""
    add_price_term!(data, price_type::Symbol, table_name::Symbol, result_name::Symbol, oper)
"""
function add_price_term!(data, price_type::Symbol, table_name::Symbol, result_name::Symbol, oper::Function)
    retail_price = get_retail_price(data)
    subretail_price = get!(retail_price, price_type) do
        OrderedDict{Symbol, OrderedDict{Symbol, Function}}()
    end
    subretail_price = get!(subretail_price, table_name) do
        OrderedDict{Symbol, Function}()
    end


    get(subretail_price, result_name, oper) == oper || @warn "Changing price sign for price[$price_type][$table_name][$result_name] to $oper"
    subretail_price[result_name] = oper
end
export add_price_term!

# wrapper function that dispatches different methods based on cal_mod arg
function compute_retail_price(m, data, price_type::Symbol, idxs, yr_idxs, hr_idxs)
    compute_retail_price((Val(Symbol(m.cal_mode))), m, data, price_type, idxs, yr_idxs, hr_idxs)
end

# specialized method to calculate retail price for cal_mode none
function compute_retail_price(::Val{:none}, m, data, price_type::Symbol, idxs...)
    value = 0.0
    retail_price = get_retail_price(data)
    table_names = retail_price[price_type]
    for (table_name, result_names) in table_names
        for (result_name, result_sign) in result_names
            res = compute_result(data, table_name, result_name, idxs...) |> result_sign
            value += res
        end
    end

    # divide by total generation to get dollars per MWh
    elserv_total = compute_result(data, :bus, :elserv_total, idxs...)
    return value/elserv_total
end

# specialized method to calculate retail price for cal_mode get_cal_values
function compute_retail_price(::Val{:get_cal_values}, m, data, price_type::Symbol, idxs, yr_idxs, hr_idxs)
    value = 0.0
    retail_price = get_retail_price(data)
    table_names = retail_price[price_type]
    for (table_name, result_names) in table_names
        for (result_name, result_sign) in result_names
            res = compute_result(data, table_name, result_name, idxs, yr_idxs, hr_idxs) |> result_sign
            value += res
        end
    end
    # divide by total generation to get dollars per MWh
    elserv_total = compute_result(data, :bus, :elserv_total, idxs, yr_idxs, hr_idxs)
    retail_price =  value/elserv_total

    fsy = get_first_sim_year(data)

    ref_price_table = read_table(m.calibrator_file)
   
    if !hasproperty(ref_price_table, :year) 
        if yr_idxs != fsy
            return retail_price, []
        else 
            year = ""
            ref_value, area, subarea = get_ref_price(ref_price_table, idxs, hr_idxs, retail_price)
        end
    else
        ref_value, area, subarea, year = get_ref_price(ref_price_table, idxs, yr_idxs, hr_idxs, retail_price, first_sim_year)
    end
    
    subset = filter(row -> row.area == "" && row.subarea == "", ref_price_table)

    # warn if there is no average reference price, error if more than 1
    if nrow(subset) == 0
        @warn "No full model reference price row. Outputting calibration values without a full adjustment."
        elserv_ratio = 0
    elseif nrow(subset) > 1
        error("Multiple full model reference price rows.")
    else
        elserv_total_all = compute_result(data, :bus, :elserv_total, :, yr_idxs, hr_idxs)
        elserv_ratio = elserv_total/elserv_total_all
    end
    
    return retail_price, [area, subarea, year, ref_value, retail_price, ref_value - retail_price, elserv_total, elserv_ratio]
    
end

function compute_retail_price(::Val{:calibrate}, m, data, price_type::Symbol,  idxs, yr_idxs, hr_idxs)
    value = 0.0
    retail_price = get_retail_price(data)
    table_names = retail_price[price_type]
    for (table_name, result_names) in table_names
        for (result_name, result_sign) in result_names
            res = compute_result(data, table_name, result_name, idxs, yr_idxs, hr_idxs) |> result_sign
            value += res
        end
    end
    # divide by total generation to get dollars per MWh
    elserv_total = compute_result(data, :bus, :elserv_total, idxs, yr_idxs, hr_idxs)
    retail_price =  value/elserv_total
   
    cal = get_calibrator_value(m.calibrator_file, idxs, yr_idxs, hr_idxs)
    retail_price = retail_price + cal
    return retail_price
   
end

export compute_retail_price

# get corresponding price values
function get_ref_price(ref_price_table, idxs, yr_idxs, hr_idxs, retail_price)
    
    # checks that there is only one filter, outside of hour and year filters
    area, subarea = 
    isempty(idxs) ? ("", "") :
    length(idxs) == 1 && idxs[1] isa Pair ? (idxs[1].first, idxs[1].second) :
    throw(ErrorException("Retail price calibrator is not set up to handle multiple filters."))

    # for each result row, get the corresponding reference price
    ref_values = []
    for (i, row) in enumerate(eachrow(ref_price_table))
        if row.area == area && row.subarea == subarea && row.year == yr_idxs
            push!(ref_values, row["ref_price"])
        end
    end 
    
    # error if there are multiple corresponding ref prices, and warn if there is none
    length(ref_values) > 1 && error("Retail price calibator is not set up to handle multiple reference prices for the same region and year.")

    isempty(ref_values) && begin
        @warn "There is no reference retail price for area `$(area)` and subarea `$(subarea)`. This region will not get a calibration value."
        push!(cal_values, 0)
    end
    
    return sum(ref_values), area, subarea, yr_idxs
end

# one ref price for all years
function get_ref_price(ref_price_table, idxs, hr_idxs, retail_price)
    
    # checks that there is only one filter, outside of hour and year filters
    area, subarea = 
    isempty(idxs) ? ("", "") :
    length(idxs) == 1 && idxs[1] isa Pair ? (idxs[1].first, idxs[1].second) :
    throw(ErrorException("Retail price calibrator is not set up to handle multiple filters."))

    # for each result row, get the corresponding reference price
    ref_values = []
    for (i, row) in enumerate(eachrow(ref_price_table))
        if row.area == area && row.subarea == subarea
            push!(ref_values, row["ref_price"])
        end
    end 
    
    # error if there are multiple corresponding ref prices, and warn if there is none
    length(ref_values) > 1 && error("Retail price calibator is not set up to handle multiple reference prices for the same region and year.")

    isempty(ref_values) && begin
        @warn "There is no reference retail price for area `$(area)` and subarea `$(subarea)`. This region will not get a calibration value."
        push!(cal_values, 0)
    end

    return sum(ref_values), area, subarea
end

# get the corresponding calibrator values
function get_calibrator_value(calibrator_file, idxs, yr_idxs, hr_idxs)
    
    # read in table with cal values
    cal_table = read_table(calibrator_file)

    # checks that there is only one filter, outside of hour and year filters
    area, subarea = 
    isempty(idxs) ? ("", "") :
    length(idxs) == 1 && idxs[1] isa Pair ? (idxs[1].first, idxs[1].second) :
    throw(ErrorException("Retail price calibrator is not set up to handle multiple filters."))

    # for each result row, get the corresponding calibrator value for area, subarea, year
    cal_values =[]
    for row in eachrow(cal_table)
        if row.area == area && row.subarea == subarea && (!hasproperty(calibrator_file, :year) || row.year == yr_idxs) # if there is no year column only check that area, subarea match
            push!(cal_values, row.cal_value)
        end
    end

    # error if there are multiple corresponding calibrator values, and warn if there is none
    length(cal_values) > 1 && error("Retail price calibrator is not set up to handle multiple calibrator values for the same region.")

    isempty(cal_values) && begin
        @warn "There is no calibrator value for area `$(area)` and subarea `$(subarea)`. This region will not be calibrated."
        push!(cal_values, 0)
    end
   
    return sum(cal_values)
end