"""
    setup_retail_price!(config, data)

Sets up the retail price structure. 
Add in welfare terms for our standard welfare results and for several welfare checks.

Welfare Checks: 
* `system_cost_check` - This is the "system cost" and the delta of total system cost should equal the delta of the sum of user, producer, and government revenue.
* `electricity_payments` - This should sum to zero to check whether electricity payments equals electricity revenue paid to producers.
* `net_rev_prelim_check` - This is meant to check that producer `net_total_revenue_prelim` is being calculated correctly, particularly when there are reserve requirements. The sum of this check should equal the sum of `net_total_revenue_prelim` for gen and storage.
"""
function setup_retail_price!(config, data)
    retail_price = OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}()
    data[:retail_price] = retail_price

   
    add_price_term!(data, :retail_price, :bus, :electricity_cost, +)
    add_price_term!(data, :retail_price, :bus, :distribution_cost_total, +)
    add_price_term!(data, :retail_price, :bus, :merchandising_surplus_total, -)
    add_price_term!(data, :retail_price, :gen, :cost_of_service_rebate, -)
    add_price_term!(data, :retail_price, :gen, :net_production_cost, +)
    add_price_term!(data, :retail_price, :storage, :net_production_cost, +)
    if haskey(config, :mods) && haskey(config[:mods], :baa_reserve_requirement)
        add_price_term!(data, :retail_price, :bus, :baa_reserve_requirement_cost, +)
        add_price_term!(data, :retail_price, :bus, :baa_reserve_requirement_merchandising_surplus_total, -)
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
    egen_total = compute_result(data, :gen, :egen_total, idxs...)
    return value/egen_total
end

export compute_retail_price