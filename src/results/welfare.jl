"""
    setup_welfare!(config, data)

Sets up the welfare structure. 
Add in welfare terms for our standard welfare results and for several welfare checks.

Welfare Checks: 
* `system_cost_check` - This is the "system cost" and the delta of total system cost should equal the delta of the sum of user, producer, and government revenue.
* `electricity_payments` - This should sum to zero to check whether electricity payments equals electricity revenue paid to producers.
* `net_rev_prelim_check` - This is meant to check that producer `net_total_revenue_prelim` is being calculated correctly, particularly when there are reserve requirements. The sum of this check should equal the sum of `net_total_revenue_prelim` for gen and storage.
"""
function setup_welfare!(config, data)
    welfare = OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}()
    data[:welfare] = welfare

    # Producer welfare
    add_welfare_term!(data, :producer, :gen, :net_total_revenue_prelim, +)
    add_welfare_term!(data, :producer, :gen, :cost_of_service_rebate, -)

    # Consumer welfare
    add_welfare_term!(data, :user, :gen, :cost_of_service_rebate, +)
    add_welfare_term!(data, :user, :bus, :electricity_cost, -)
    add_welfare_term!(data, :user, :gen, :gs_rebate, -)
    add_welfare_term!(data, :user, :bus, :merchandising_surplus_total, +)
    add_welfare_term!(data, :user, :bus, :distribution_cost_total, -)
    # Make sure to have a term for policy costs that would get transferred to users, for policies like nuclear preservation, installed reserve margins, portfolio standards

    # Government welfare
    add_welfare_term!(data, :government, :gen, :net_government_revenue, +)
    # Make sure that emissions caps and prices get added to govt. revenue and production cost.

    # Unserved load welfare
    add_welfare_term!(data, :unserved_load, :bus, :unserved_load_value_total, -)

    # Create welfare check by calculating system cost, change in system cost should equal the change in net non-enviro (this welfare) benefits
    add_welfare_term!(data, :system_cost_check, :gen, :production_cost, +)
    add_welfare_term!(data, :system_cost_check, :bus, :distribution_cost_total, +)

    # Create welfare check for the electricity payments.  Should sum to zero
    add_welfare_term!(data, :electricity_payments, :bus, :electricity_cost, +)
    add_welfare_term!(data, :electricity_payments, :bus, :merchandising_surplus_total, -)
    add_welfare_term!(data, :electricity_payments, :gen, :electricity_revenue, -)

    #Create welfare check for net_total_revenue_prelim (gen)
    add_welfare_term!(data, :net_rev_prelim_check, :gen, :electricity_revenue, +)
    add_welfare_term!(data, :net_rev_prelim_check, :gen, :net_government_revenue, -)
    add_welfare_term!(data, :net_rev_prelim_check, :gen, :production_cost, -)
    add_welfare_term!(data, :net_rev_prelim_check, :gen, :gs_rebate, +)
    add_welfare_term!(data, :net_rev_prelim_check, :gen, :past_invest_cost_total, -)

end
export setup_welfare!

"""
    get_welfare(data) -> welfare::OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}
"""
function get_welfare(data)
    return data[:welfare]::OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}
end
export get_welfare
"""
    add_welfare_term!(data, welfare_type::Symbol, table_name::Symbol, result_name::Symbol, oper)
"""
function add_welfare_term!(data, welfare_type::Symbol, table_name::Symbol, result_name::Symbol, oper::Function)
    welfare = get_welfare(data)
    subwelfare = get!(welfare, welfare_type) do
        OrderedDict{Symbol, OrderedDict{Symbol, Function}}()
    end
    subsubwelfare = get!(subwelfare, table_name) do
        OrderedDict{Symbol, Function}()
    end


    get(subsubwelfare, result_name, oper) == oper || @warn "Changing welfare sign for welfare[$welfare_type][$table_name][$result_name] to $oper"
    subsubwelfare[result_name] = oper
end
export add_welfare_term!

function compute_welfare(data, welfare_type::Symbol, idxs...)
    value = 0.0
    welfare = get_welfare(data)
    table_names = welfare[welfare_type]
    for (table_name, result_names) in table_names
        for (result_name, result_sign) in result_names
            res = compute_result(data, table_name, result_name, idxs...) |> result_sign
            value += res
        end
    end
    return value
end

export compute_welfare