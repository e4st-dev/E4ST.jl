
@doc raw"""
    struct GenerationConstraint <: Modification

**Generation Constraint** - A Modification that applies a constraint based on (yearly generation) * (a column from the gen table). 

* `name`: modification name 
* `col`: gen table column, optional. Defaults to multiplying by 1
* `max_values`: maximum values for a year (defaults as an empty OrderedDict if no maxs)
* `min_values`: minimum values for a year (defaults as an empty OrderedDict if no mins)
* `gen_filters`: OrderedDict of the generator filters
"""
Base.@kwdef struct GenerationConstraint <: Modification
    name::Symbol
    col::Symbol = Symbol("")
    max_values::OrderedDict = OrderedDict()
    min_values::OrderedDict = OrderedDict()
    gen_filters::OrderedDict = OrderedDict()
    hour_filters::OrderedDict = OrderedDict()
end
export GenerationConstraint

mod_rank(::Type{<:GenerationConstraint}) = 1.0

"""
    modify_model!(cons::GenerationConstraint, config, data, model)

Creates upper and lower bound constraints on the generators.  See also [`GenerationConstraint`](@ref) for more details
"""
function E4ST.modify_model!(cons::GenerationConstraint, config, data, model)
    @info "$(cons.name) modifying model" 

    gen = get_table(data, :gen)
    years = Symbol.(get_years(data))
    nyr = get_num_years(data)

    # Get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(cons.gen_filters))

    # Get qualifying hour idxs
    hours = get_table(data, :hours)
    nhr = get_num_hours(data)
    hour_idxs = get_row_idxs(hours, parse_comparisons(cons.hour_filters))
    if length(hour_idxs) < nhr
        hour_multiplier = ByHour([i in hour_idxs ? 1.0 : 0.0 for i in 1:nhr])
    else
        hour_multiplier = ByNothing(1.0)
    end



    v = zeros(nrow(gen))
    add_table_col!(data, :gen, cons.name, v, NA,
        "Boolean value for whether a gen is constrained by $(cons.name)")
    to_container!(gen, cons.name)
    for gen_idx in gen_idxs
        gen[gen_idx, cons.name] = hour_multiplier
    end

    # get only years from cons.values that are in the sim
    max_years = collect(keys(cons.max_values))
    min_years = collect(keys(cons.min_values))
    
    filter!(in(years), max_years)
    filter!(in(years), min_years)

    #create max and min constraints names
    max_cons_name = "cons_$(cons.name)_max"
    min_cons_name = "cons_$(cons.name)_min"

    #create max and min constraints
    nhours = get_num_hours(data)

    pgen_gen = model[:pgen_gen]::Array{VariableRef, 3}
    hour_weights = get_hour_weights(data)
    
    col_empty = cons.col == Symbol("")
    if ~isempty(max_years)
        @info "Creating a maximum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(max_cons_name)"
        model[Symbol(max_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in max_years
            ], 
            sum(
                pgen_gen[gen_idx, yr_idx, hour_idx] * hour_weights[hour_idx] * 
                get_table_num(data, :gen, cons.name, gen_idx, yr_idx, hour_idx) *
                (col_empty == true ? 1.0 : get_table_num(data, :gen, cons.col, gen_idx, yr_idx, hour_idx))
                for gen_idx=gen_idxs, hour_idx=1:nhours
            ) <= cons.max_values[years[yr_idx]]
        )
    end

    if ~isempty(min_years)
        @info "Creating a minimum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(min_cons_name)"
        model[Symbol(min_cons_name)] = @constraint(model, 
            [
                yr_idx in 1:nyr;
                years[yr_idx] in min_years
            ], 
            sum(
                pgen_gen[gen_idx, yr_idx, hour_idx] * hour_weights[hour_idx] * 
                get_table_num(data, :gen, cons.name, gen_idx, yr_idx, hour_idx) *
                (col_empty == true ? 1.0 : get_table_num(data, :gen, cons.col, gen_idx, yr_idx, hour_idx))
                for gen_idx=gen_idxs, hour_idx=1:nhours
            ) >= cons.min_values[years[yr_idx]]
        )
    end
end

