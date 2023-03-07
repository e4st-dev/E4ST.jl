

@doc raw"""
    struct EmissionCap <: Policy

Emission Cap - A limit on a certain emission for a given set of generators.

name: name of the policy (Symbol)
emis_col: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
values: OrderedDict of cap values by year
gen_filters: OrderedDict of generator filters
gen_cons: GenerationConstraint Modification created on instantiation of the EmissionCap. It sets the cap values as the max_values of the GenerationConstraint and passes on other fields.
"""
struct EmissionCap <: Policy
    name::Symbol
    emis_col::Symbol
    values::OrderedDict
    gen_filters::OrderedDict
    gen_cons::GenerationConstraint

    function EmissionCap(;name, emis_col, values, gen_filters)
        empty_mins = OrderedDict{}()
        gen_cons = GenerationConstraint(Symbol(name), Symbol(emis_col), values, empty_mins, gen_filters)
        new(Symbol(name), Symbol(emis_col), values, gen_filters, gen_cons)
    end

end

# function EmissionCap(;name, emis_col, values, gen_filters)
#     empty_mins = OrderedDict{}()
#     gen_cons = GenerationConstraint(Symbol(name), Symbol(emis_col), values, empty_mins, gen_filters)
#     EmissionCap(Symbol(name), Symbol(emis_col), values, gen_filters, gen_cons)
# end
export EmissionCap

"""
 E4ST.modify_model!(pol::EmissionCap, config, data, model)

"""
function E4ST.modify_model!(pol::EmissionCap, config, data, model)
    modify_model!(pol.gen_cons, config, data, model)

    # # get buses and then associated gens
    # gen = get_table(data, :gen)
    # bus = get_table(data, :bus)
    # years = get_table(data, :years)

    # gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    # # get only years from pol.values that are in the sim
    # pol_years = collect(keys(pol.values))
    # filter!(in(years), pol_years)

    # caps = collect(values(pol.targets))

    # #set constraint on total emissions for given gens based on emis rate and gen
    # cons_name = "cons_$(pol.name)"

    # model[Symbol(cons_name)] = @constraint(model, [y in pol_years],
    #     sum(get_table_val(data, :gen, emis_col, gen_idx)*get_egen_gen(data, model, gen_idx, findfirst(==(y), years)), gen_idxs) <= caps[y], base_name = pol.name)

end

"""
    fieldnames_for_yaml(::EmissionCap) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(::EmissionCap)
    return setdiff(fieldnames(M), (:name, :gen_cons,))
end