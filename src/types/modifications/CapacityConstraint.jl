
@doc raw"""
    struct CapacityConstraint <: Modification

**Capacity Constraint** - A Modification that applies a constraint based on total capacity. 

* `name`: modification name 
* `table`: whether to apply the constraint to items in the gen or storage table. 
* `max_values`: maximum values for a year (defaults as an empty OrderedDict if no maxs)
* `min_values`: minimum values for a year (defaults as an empty OrderedDict if no mins)
* `table_filters`: OrderedDict of the table filters
"""
Base.@kwdef struct CapacityConstraint <: Modification
    name::Symbol
    table::String = "gen"
    max_values::OrderedDict{Symbol, Any} = OrderedDict{Symbol, Any}()
    min_values::OrderedDict{Symbol, Any} = OrderedDict{Symbol, Any}()
    table_filters::OrderedDict{Symbol, Any} = OrderedDict{Symbol, Any}()
end
export CapacityConstraint

mod_rank(::Type{<:CapacityConstraint}) = 1.0

"""
    E4ST.modify_model!(m::CapacityConstraint, config, data, model) -> 

Creates an upper and lower bound on capacity. See also [`CapacityConstraint`](@ref) for more details
"""
function E4ST.modify_model!(cons::CapacityConstraint, config, data, model)
    @info "$(cons.name) modifying model" 
    table_name = Symbol(cons.table)

    table = get_table(data, table_name)
    years = Symbol.(get_years(data))
    nyr = get_num_years(data)

    # Get qualifying table idxs
    table_idxs = get_row_idxs(table, parse_comparisons(cons.table_filters))

    v = zeros(nrow(table))
    add_table_col!(data, table_name, cons.name, v, NA,
        "Boolean value for whether a gen/storage is constrained by $(cons.name)")
    for table_idx in table_idxs
        table[table_idx, cons.name] = 1
    end

    # get only years from cons.values that are in the sim
    max_years = collect(keys(cons.max_values))
    min_years = collect(keys(cons.min_values))
    
    filter!(in(years), max_years)
    filter!(in(years), min_years)

    #create max and min constraints names
    max_cons_name = "cons_$(cons.name)_max"
    min_cons_name = "cons_$(cons.name)_min"

    # pull out the capacity variable
    if table_name == :gen 
        pcap_var = model[:pcap_gen]::Matrix{VariableRef}
    elseif table_name == :storage
        pcap_var = model[:pcap_stor]::Matrix{VariableRef}
    else
        error("You must specify either the gen or storage table for the CapacityConstraint mod")
    end

    # Check to see if any infeasibilities introduced
    for (yr_idx, year) in enumerate(years)
        if haskey(cons.min_values, year) 
            min_val = cons.min_values[year]
            if haskey(cons.max_values, year)
                max_val = cons.max_values[year]
                # Check that they are not conflicting.
                @assert max_val >= min_val "CapacityConstraint $(cons.name) has max value $max_val which is less than min value $min_val for year $year"
            end
            pcap_max_sum = sum(table_idx->table.pcap_max[table_idx][yr_idx, :], table_idxs)
            @assert pcap_max_sum >= min_val "CapacityConstraint $(cons.name) has min value $min_val which is greater than the max capacity of the portion of the $(cons.name) table that it is constraining, which is $pcap_max_sum."
        end
    end

    if ~isempty(max_years)
        @info "Creating a maximum capacity constraint for $(length(table_idxs)) generators/storage. Constraint name is $(max_cons_name)"
        model[Symbol(max_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in max_years
            ], 
            sum(
                pcap_var[table_idx, yr_idx] * 
                get_table_val(data, table_name, cons.name, table_idx)
                for table_idx=table_idxs
            ) <= cons.max_values[years[yr_idx]]
        )
    end

    if ~isempty(min_years)
        @info "Creating a minimum capacity constraint for $(length(table_idxs)) generators/storage. Constraint name is $(min_cons_name)"
        model[Symbol(min_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in min_years
            ], 
            sum(
                pcap_var[table_idx, yr_idx] * 
                get_table_val(data, table_name, cons.name, table_idx)
                for table_idx=table_idxs
            ) >= cons.min_values[years[yr_idx]]
        )
    end
end