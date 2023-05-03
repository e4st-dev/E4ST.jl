
@doc raw"""
    struct GenerationConstraint <: Modification

**Generation Constraint** - A Modification that applies a constraint based on (yearly generation) * (a column from the gen table). 

* `name`: modification name 
* `col`: gen table column
* `max_values`: maximum values for a year (defaults as an empty OrderedDict if no maxs)
* `min_values`: minimum values for a year (defaults as an empty OrderedDict if no mins)
* `gen_filters`: OrderedDict of the generator filters
"""
Base.@kwdef struct GenerationConstraint <: Modification
    name::Symbol
    col::Symbol
    max_values::OrderedDict = OrderedDict()
    min_values::OrderedDict = OrderedDict()
    gen_filters::OrderedDict = OrderedDict()

end
export GenerationConstraint

mod_rank(::Type{<:GenerationConstraint}) = 1.0

"""
    modify_model!(cons::GenerationConstraint, config, data, model)

Creates upper and lower bound constraints on the generators.  See also [`GenerationConstraint`](@ref) for more details
"""
function E4ST.modify_model!(cons::GenerationConstraint, config, data, model)
    gen = get_table(data, :gen)
    years = Symbol.(get_years(data))

    #get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(cons.gen_filters))

    v = zeros(Bool, nrow(gen))
    add_table_col!(data, :gen, cons.name, v, NA,
        "Boolean value for whether a gen is constrained by $(cons.name)") #This isn't necessary and might make the gen table unnecessarily large but I think it would be good documentation.
    gen[gen_idxs, cons.name] .= 1 

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

    if ~isempty(max_years)
        @info "Creating a maximum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(max_cons_name)"
        model[Symbol(max_cons_name)] = @constraint(model, [y=max_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years), hour_idx)*get_table_num(data, :gen, cons.col, gen_idx, findfirst(==(y), years), hour_idx) for gen_idx=gen_idxs, hour_idx=1:nhours) <= cons.max_values[y]) #TODO: make it so that emis can be indexed by hour 
    end

    if ~isempty(min_years)
        @info "Creating a miminum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(min_cons_name)"
        model[Symbol(min_cons_name)] = @constraint(model, [y=min_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years), hour_idx)*get_table_num(data, :gen, cons.col, gen_idx, findfirst(==(y), years), hour_idx) for gen_idx=gen_idxs, hour_idx=1:nhours) >= cons.min_values[y])  #TODO: make it so that emis can be indexed by hour 
    end

end
