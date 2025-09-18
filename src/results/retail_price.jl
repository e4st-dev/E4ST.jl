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
    add_price_term!(data, :avg_elec_rate, :bus, :distribution_cost_total, +)
    add_price_term!(data, :avg_elec_rate, :bus, :merchandising_surplus_total, -)
    add_price_term!(data, :avg_elec_rate, :gen, :cost_of_service_rebate, -)
    add_price_term!(data, :avg_elec_rate, :storage, :cost_of_service_rebate, -)
    add_price_term!(data, :avg_elec_rate, :gen, :net_production_cost, +)
    add_price_term!(data, :avg_elec_rate, :storage, :net_production_cost, +)
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
    egen_total = compute_result(data, :gen, :egen_total, idxs...)
    return value/egen_total
end

export compute_retail_price
