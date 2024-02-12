
@doc raw"""
    struct CapacityConstraint <: Modification

**Capacity Constraint** - A Modification that applies a constraint based on total capacity. 

* `name`: modification name 
* `max_values`: maximum values for a year (defaults as an empty OrderedDict if no maxs)
* `min_values`: minimum values for a year (defaults as an empty OrderedDict if no mins)
* `gen_filters`: OrderedDict of the generator filters
"""
Base.@kwdef struct CapacityConstraint <: Modification
    name::Symbol
    max_values::OrderedDict = OrderedDict()
    min_values::OrderedDict = OrderedDict()
    gen_filters::OrderedDict = OrderedDict()
end
export CapacityConstraint

mod_rank(::Type{<:CapacityConstraint}) = 1.0

"""
    E4ST.modify_model!(m::CapacityConstraint, config, data, model) -> 

Creates an upper and lower bound on capacity. See also [`CapacityConstraint`](@ref) for more details
"""
function E4ST.modify_model!(cons::CapacityConstraint, config, data, model)
    @info "$(cons.name) modifying model" 

    gen = get_table(data, :gen)
    years = Symbol.(get_years(data))
    nyr = get_num_years(data)

    # Get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(cons.gen_filters))

    v = zeros(nrow(gen))
    add_table_col!(data, :gen, cons.name, v, NA,
        "Boolean value for whether a gen is constrained by $(cons.name)")
    for gen_idx in gen_idxs
        gen[gen_idx, cons.name] = 1
    end

    # get only years from cons.values that are in the sim
    max_years = collect(keys(cons.max_values))
    min_years = collect(keys(cons.min_values))
    
    filter!(in(years), max_years)
    filter!(in(years), min_years)

    #create max and min constraints names
    max_cons_name = "cons_$(cons.name)_max"
    min_cons_name = "cons_$(cons.name)_min"

    if ~isempty(max_years)
        @info "Creating a maximum capacity constraint for $(length(gen_idxs)) generators. Constraint name is $(max_cons_name)"
        model[Symbol(max_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in max_years
            ], 
            sum(
                get_pcap_gen(data, model, gen_idx, yr_idx) * 
                get_table_val(data, :gen, cons.name, gen_idx)
                for gen_idx=gen_idxs
            ) <= cons.max_values[years[yr_idx]]
        )
    end

    if ~isempty(min_years)
        @info "Creating a minimum capacity constraint for $(length(gen_idxs)) generators. Constraint name is $(min_cons_name)"
        model[Symbol(min_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in min_years
            ], 
            sum(
                get_pcap_gen(data, model, gen_idx, yr_idx) * 
                get_table_val(data, :gen, cons.name, gen_idx)
                for gen_idx=gen_idxs
            ) >= cons.min_values[years[yr_idx]]
        )
    end
end