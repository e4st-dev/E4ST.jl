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
"""
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
    add_price_term!(data, :avg_elec_rate, :bus, :gs_payment, +)

    # ToDo: include past subsidies, but these may be hard to track down 
    if haskey(config, :past_invest_file)
        add_price_term!(data, :avg_elec_rate, :past_invest, :cost_of_service_past_costs, +)
    end

    if haskey(config, :mods) && haskey(config[:mods], :baa_reserve_requirement)
        add_price_term!(data, :avg_elec_rate, :bus, :baa_reserve_requirement_cost, +)
        add_price_term!(data, :avg_elec_rate, :bus, :baa_reserve_requirement_merchandising_surplus_total, -)
    end

    # future work: calculate electricity rates by end-use sector
    
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

function compute_retail_price(data, price_type::Symbol, idxs...)
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

function compute_retail_price(data, price_type::Symbol, ref_price_file::String, idxs, yr_idxs, hr_idxs)
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

    ref_value, area, subarea, year = compute_calibrator_value(ref_price_file, idxs, yr_idxs, hr_idxs, retail_price)
    return retail_price, [area, subarea, year, retail_price - ref_value]
end

function compute_retail_price(data, price_type::Symbol, cal::Bool, calibrator_file::String, idxs, yr_idxs, hr_idxs)
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
   
    cal = get_calibrator_value(calibrator_file, idxs, yr_idxs, hr_idxs)
    retail_price = retail_price + cal
    return retail_price
   
end

export compute_retail_price

function compute_calibrator_value(ref_price_file, idxs, yr_idxs, hr_idxs, retail_price)
    # get corresponding price values
    ref_price_table = read_table(ref_price_file)

    if isempty(idxs)
        area = ""
        subarea = ""
    elseif length(idxs)==1 && idxs[1] isa Pair
        area = idxs[1].first
        subarea = idxs[1].second
    else 
        error("Retail price calibrator is not set up to handle multiple filters.")
    end

    @assert yr_idxs != Any[] "Retail price calibrator is not set up to handle average retail rate across years."
    year = yr_idxs

    @assert hr_idxs == Colon() "Retail price calibrator is not set up to handle hourly retail rates."

    ref_values = []
    for (i, row) in enumerate(eachrow(ref_price_table))
        if row.area == area && row.subarea ==subarea
            push!(ref_values, row[year])
        end
    end 
    
    if length(ref_values) > 1
        error("Retail price calibator is not set up to handle multiple referenc prices")
    elseif isempty(ref_values)
        push!(ref_values, retail_price)
    end
   
    return sum(ref_values), area, subarea, year
end

function get_calibrator_value(calibrator_file, idxs, yr_idxs, hr_idxs)
    # adjust retail price with calibrator values
    cal_table = read_table(calibrator_file)

    if isempty(idxs)
        area = ""
        subarea = ""
    elseif length(idxs)==1 && idxs[1] isa Pair
        area = idxs[1].first
        subarea = idxs[1].second
    else 
        error("Retail price calibrator is not set up to handle multiple filters.")
    end

    @assert yr_idxs != Any[] "Retail price calibrator is not set up to handle average retail rate across years."
    year = yr_idxs

    @assert hr_idxs == Colon() "Retail price calibrator is not set up to handle hourly retail rates."

    cal_values =[]
    for (i, row) in enumerate(eachrow(cal_table))
        if row.area == "" && row.subarea == "" && !isempty(idxs)
            push!(cal_values, row[year])
        elseif row.area == area && row.subarea ==subarea
            push!(cal_values, row[year])
        end
    end 
   
    return sum(cal_values)
end