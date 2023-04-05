"""
    match_capacity!(data, model, sets::Vector{Vector{Int64}}, name::Symbol)

Constrains `sets` of generator indices so that their `pcap_gen` values sum to the max and min specified in the first member of the set.  The names of the constraints are:
* `Symbol("cons_pcap_max_\$name")`
* `Symbol("cons_pcap_min_\$name")`
"""
function match_capacity!(data, model, sets::Vector{Vector{Int64}}, name::Symbol)
    nset = length(sets)
    nhour = get_num_hours(data)
    nyear = get_num_years(data)
    gen = get_table(data, :gen)

    # Set up the names of the constraints
    name_max = Symbol("cons_pcap_max_$name")
    name_min = Symbol("cons_pcap_min_$name")

    # Constrain the max capacity to add up to the desired max capacity
    model[name_max] = @constraint(model,
        [set_idx=1:nset, yr_idx = 1:nyear],
        sum(model[:pcap_gen][gen_idx, yr_idx] for gen_idx in sets[set_idx]) <= get_pcap_max(data, first(sets[set_idx]), yr_idx)
    )
    
    # Lower bound the capacities with zero
    pcap_gen = model[:pcap_gen]
    for set in sets
        for gen_idx in set
            for yr_idx in 1:nyear
                set_lower_bound(pcap_gen[gen_idx, yr_idx], 0.0)
            end
        end
    end

    # Constrain the minimum capacities to add up to the desired min capacity
    model[name_min] = @constraint(model,
        [set_idx=1:nset, yr_idx = 1:nyear],
        sum(model[:pcap_gen][gen_idx, yr_idx] for gen_idx in sets[set_idx]) >= get_pcap_min(data, first(sets[set_idx]), yr_idx)
    )

    return nothing
end
export match_capacity!