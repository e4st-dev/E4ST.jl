
@doc raw"""
struct GenerationCons <: Modification

Generation Cap - A Modification that applies a constraint based on (yearly generation) * (a column from the gen table). 

name: modification name 
col: gen table column
max_values: maximum values for a year (specify as empty OrderedDict if no maxs)
min_values: minimum values for a year (specify as empty OrderedDict if no mins)
gen_filters: OrderedDict of the generator filters
"""
Base.@kwdef struct GenerationConstraint <: Modification
    name::Symbol
    col::Symbol
    max_values::OrderedDict
    min_values::OrderedDict
    gen_filters::OrderedDict

end
export GenerationConstraint

function E4ST.modify_model!(cons::GenerationConstraint, config, data, model)
    gen = get_table(data, :gen)
    years = Symbol.(get_years(data))

    #get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(cons.gen_filters))

    add_table_col!(data, :gen, cons.name, [in(g, gen_idxs) for g in 1:nrow(gen)], NA,
        "Boolean value for whether a gen is constrained by $(cons.name)") #This isn't necessary and might make the gen table unnecessarily large but I think it would be good documentation.

    # get only years from cons.values that are in the sim
    max_years = collect(keys(cons.max_values))
    min_years = collect(keys(cons.min_values))
    
    filter!(in(years), max_years)
    filter!(in(years), min_years)

    #create max and min constraints names, max and min suffix added only if both max and min specified
    if ~isempty(max_years) & ~isempty(min_years)
        max_cons_name = "cons_$(cons.name)_max"
        min_cons_name = "cons_$(cons.name)_min"
    else 
        max_cons_name = "cons_$(cons.name)"
        min_cons_name = "cons_$(cons.name)"
    end

    #create max and min constraints
    if ~isempty(max_years)
        @info "Creating a maximum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(max_cons_name)"
        model[Symbol(max_cons_name)] = @constraint(model, [y=max_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years))*gen[gen_idx, cons.col] for gen_idx in gen_idxs) <= cons.max_values[y])
    end

    if ~isempty(min_years)
        @info "Creating a miminum generation constraint based on $(cons.col) for $(length(gen_idxs)) generators. Constraint name is $(min_cons_name)"
        model[Symbol(min_cons_name)] = @constraint(model, [y=min_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years))*gen[gen_idx, cons.col] for gen_idx in gen_idxs) <= cons.min_values[y])
    end

end
