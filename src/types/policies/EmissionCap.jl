

@doc raw"""
    struct EmissionCap <: Policy

Emission Cap - A limit on a certain emission for a given set of generators.

* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `targets`: OrderedDict of cap targets by year
* `gen_filters`: OrderedDict of generator filters
* `gen_cons`: GenerationConstraint Modification created on instantiation of the EmissionCap (not specified in config). It sets the cap targets as the max_targets of the GenerationConstraint and passes on other fields.
"""
struct EmissionCap <: Policy
    name::Symbol
    emis_col::Symbol
    targets::OrderedDict
    gen_filters::OrderedDict
    gen_cons::GenerationConstraint

    function EmissionCap(;name, emis_col, targets, gen_filters=OrderedDict())
        empty_mins = OrderedDict{}()
        gen_cons = GenerationConstraint(Symbol(name), Symbol(emis_col), targets, empty_mins, gen_filters)
        new(Symbol(name), Symbol(emis_col), targets, gen_filters, gen_cons)
    end

end

export EmissionCap

"""
    E4ST.modify_model!(pol::EmissionCap, config, data, model)

Calls [`modify_model!(cons::GenerationConstraint, config, data, model)`](@ref)
"""
function E4ST.modify_model!(pol::EmissionCap, config, data, model)
    modify_model!(pol.gen_cons, config, data, model)
end

"""
    E4ST.modify_results!(pol::EmissionCap, config, data) -> 
"""
function E4ST.modify_results!(pol::EmissionCap, config, data)
    gen = get_table(data, :gen)
    
    # create column for per MWh price of the policy in :gen
    shadow_prc = get_shadow_price_as_ByYear(data, Symbol("cons_$(pol.name)_max")) #($/EmissionsUnit)

    prc_col = [abs.(shadow_prc) .* g[pol.name] .* g[pol.emis_col] for g in eachrow(gen)] #($/MWh Generated)

    add_table_col!(data, :gen, Symbol("$(pol.name)_prc"), prc_col, DollarsPerMWhGenerated, "Shadow price of $(pol.name) converted to DollarsPerMWhGenerated")

    # policy cost, shadow price (per MWh generated) * generation
    add_results_formula!(data, :gen, Symbol("$(pol.name)_cost"), "SumHourly($(pol.name)_prc, egen)", Dollars, "The cost of $(pol.name) based on the shadow price of the generation constraint")
end

"""
    fieldnames_for_yaml(::EmissionCap) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(T::Type{M}) where {M<:EmissionCap}
    return setdiff(fieldnames(T), (:name, :gen_cons,))
end
export fieldnames_for_yaml