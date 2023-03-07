
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

function E4ST.modify_model!(cons::GenerationConstraint, config, data, model)
    gen = get_table(data, :gen)
    years = get_table(data, :years)

    #get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(cons.gen_filters))

    # get only years from cons.values that are in the sim
    max_years = collect(keys(cons.max_values))
    min_years = collect(keys(cons.min_values))
    
    filter!(in(years), max_years)
    filter!(in(years), min_years)

    #create max and min constraints
    max_cons_name = "cons_$(cons.name)_max"
    min_cons_name = "cons_$(cons.name)_min"

    if ~isempty(max_years)
        model[Symbol(max_cons_name)] = @constraint(model, [y=max_years], 
        sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years))*gen[gen_idx, cons.col] for gen_idx in gen_idxs) <= max_values[y]
    )

    if ~isempty(min_years)
        model[Symbol(min_cons_name)] = @constraint(model, [y=min_years], 
        sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years))*gen[gen_idx, cons.col] for gen_idx in gen_idxs) <= min_values[y]
    )

end
