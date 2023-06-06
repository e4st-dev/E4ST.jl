"""
    setup_welfare!(config, data)

Sets up the welfare structure.
"""
function setup_welfare!(config, data)
    welfare = OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}()
    data[:welfare] = welfare

    # Producer welfare
    add_welfare_term!(data, :producer, :gen, :net_total_revenue_prelim, +)
    add_welfare_term!(data, :producer, :gen, :cost_of_service_rebate, -)

    # Consumer welfare
    add_welfare_term!(data, :consumer, :gen, :cost_of_service_rebate, +)
    add_welfare_term!(data, :consumer, :bus, :electricity_cost, -)
    # Make sure to have a term for policy costs that would get transferred to consumers, for policies like nuclear preservation, installed reserve margins, portfolio standards

    # TODO: Add transfer for CO2 paid

    # Consumer welfare

    # Government welfare

    
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