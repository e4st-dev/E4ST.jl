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


"""
    add_build_constraints!(data, model, table_name, pcap_name)

Adds constraints to the model for:
* `cons_<pcap_name>_prebuild` - Constrain Capacity to 0 before the start/build year 
* `cons_<pcap_name>_noadd` - Constrain existing capacity to only decrease (only retire, not add capacity)
* `cons_<pcap_name>_exog` - Constrain unbuilt exogenous generators to be built to pcap0 in the first year after year_on

"""
function add_build_constraints!(data, model, table_name::Symbol, pcap_name::Symbol)
    @info "Adding build constraints for table $table_name"

    table = get_table(data, table_name)
    years = get_years(data)
    nyr = get_num_years(data)

    pcap = model[pcap_name]
    years = get_years(data)

    # Constrain Capacity to 0 before the start/build year 
    if any(>(first(years)), table.year_on)
        name = Symbol("cons_$(pcap_name)_prebuild")
        model[name] = @constraint(model, 
            [
                row_idx in axes(table, 1),
                yr_idx in 1:nyr;
                # Only for years before the device came online
                years[yr_idx] < table.year_on[row_idx]
            ],
            pcap[row_idx, yr_idx] == 0
        ) 
    end

    # Constrain existing capacity to only decrease (only retire, not add capacity)
    if nyr > 1
        name = Symbol("cons_$(pcap_name)_noadd")
        model[name] = @constraint(model, 
            [
                row_idx in axes(table,1),
                yr_idx in 1:(nyr-1);
                years[yr_idx] >= table.year_on[row_idx]
            ], 
            pcap[row_idx, yr_idx+1] <= pcap[row_idx, yr_idx])
    end

    # Constrain unbuilt exogenous generators to be built to pcap0 in the first year after year_on
    if any(row->(row.build_type==("exog") && row.build_status == "unbuilt" && last(years) >= row.year_on), eachrow(table))
        name = Symbol("cons_$(pcap_name)_exog")
        model[name] = @constraint(model,
            [
                row_idx in axes(table,1),
                yr_idx in 1:nyr;
                # Only for exogenous generators, and only for the build year.
                (
                    table.build_type[row_idx] == "exog" && 
                    table.build_status[row_idx] == "unbuilt" &&
                    yr_idx == findfirst(year -> table.year_on[row_idx] >= year, years)
                )
            ],
            pcap[row_idx, yr_idx] == table.pcap0[row_idx]
        )
    end

    # Enforce retirement
    for (i, row) in enumerate(eachrow(table))
        year_off = row.year_off
        isempty(year_off) && continue
        year_off > last(years) && continue
        yr_off_idx = findfirst(>=(year_off), years)
        for yr_idx in yr_off_idx:nyr
            fix(pcap[i, yr_idx], 0.0, force=true)
        end
    end
end
export add_build_constraints!