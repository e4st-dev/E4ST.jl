"""
    setup_welfare!(config, data)

Sets up the welfare structure.
"""
function setup_welfare!(config, data)
    welfare = OrderedDict{Symbol, OrderedDict{Symbol,OrderedDict{Symbol,Function}}}()
    data[:welfare] = welfare

    add_welfare_term!(data, :producer, :gen, :variable_cost, -)
    add_welfare_term!(data, :producer, :gen, :fixed_cost, -)
    add_welfare_term!(data, :producer, :gen, :electricity_revenue, +)

    
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