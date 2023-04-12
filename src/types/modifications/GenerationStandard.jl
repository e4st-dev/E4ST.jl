@doc raw"""
    struct GenerationStandard <: Policy

A generation standard (also refered to as a portfolio standard) is a constraint on generation where a portion of generation from certain generators must meet the a portion of the load in a specified region.
This encompasses RPSs, CESs, and technology carveouts.
To assign the credit (the portion of generation that can contribute) to generators, the [Crediting](@ref) type is used.

* `name` - Name of the policy 
* `targets` - The yearly targets for the Generation Standard
* `gen_filters` - Filters on which generation qualifies to fulfill the GS. Sometimes qualifying generators may be outside of the GS load region if they supply power to it. 
* `crediting` - the crediting structure and related fields
* `load_bus_filters` - Filters on which buses fall into the GS load region. The GS will be applied to the load from these buses. 
* `gs_type` - The original type the GS (RPS, CES, etc)
"""
struct GenerationStandard <: Policy 
    name::Symbol
    targets::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict
    gs_type::DataType

end
function GenerationStandard(;name, targets, crediting::OrderedDict, gen_filters, load_bus_filters, gs_type)
    c = Crediting(crediting)
    return GenerationStandard(Symbol(name), targets, c, gen_filters, load_bus_filters, gs_type)
end
export GenerationStandard

mod_rank(::Type{GenerationStandard}) = 1.0 #not sure this matters because this isn't usually a type specified in the config or a super type of something specified in the config. 


## Modifying Functions
#######################################################################################################################
"""
    modify_setup_data!(pol::GenerationStandard, config, data)

Adds column to the gen table with the credit level of the generation standard. Adds the name and type of the policy to the gs_pol_list in data. 
"""
function modify_setup_data!(pol::GenerationStandard, config, data)
    #add policy name and type to data[:gs_pol_list]
    add_to_gs_pol_list!(pol, config, data) 

    #get gen idxs 
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    #create get table column for policy, set to zeros to start
    v = zeros(Float64, nrow(gen))
    add_table_col!(data, :gen, pol.name, v, Ratio,
        "Credit level for generation standard: $(pol.name)")

    #set credit level in the gen table
    #call get_credit on gen_idxs, dispatching on crediting type
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        gen[gen_idx, pol.name] = get_credit(pol.crediting, g)
    end

end

"""
    modify_model!(pol::GenerationStandard, config, data, model)

Creates the expression :p_gs_bus, the load that generation standards are applied to, if it hasn't been created already. 
Creates a constraint that takes the general form: `sum(gs_egen * credit) <= gs_value * sum(gs_load)`
"""
function E4ST.modify_model!(pol::GenerationStandard, config, data, model)

    # get bus and gen idxs
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    bus = get_table(data, :bus)
    bus_idxs = get_row_idxs(bus, parse_comparisons(pol.load_bus_filters))

    years = Symbol.(get_years(data))

    # create expression for qualifying load, only created if it hasn't already been defined in the model
    nyear = get_num_years(data)
    nhour = get_num_hours(data)

    # The qualifying load should follow the formula `nominal load - curtailment + DAC load + net battery load + T&D losses`
    # Most of this is covered in `plserv_bus` except possibly battery load
    if ~haskey(model, :p_gs_bus)
        model[:p_gs_bus] = @expression(model, [bus_idx in 1:nrow(bus), year_idx in 1:nyear, hour_idx in 1:nhour], 
                model[:plserv_bus][bus_idx, year_idx, hour_idx])   
    end

    # create yearly constraint that qualifying generation meeting qualifying load
    # takes the form sum(gs_egen * credit) <= gs_value * sum(gs_load)

    cons_name = "cons_$(pol.name)"
    target_years = collect(keys(pol.targets))

    @show cons_name

    @info "Creating a generation constraint for the Generation Standard $(pol.name)."
    model[Symbol(cons_name)] = @constraint(model, [y = target_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years), hour_idx)*get_table_val(data, :gen, pol.name, gen_idx) for gen_idx=gen_idxs, hour_idx=1:nhour) >= 
            pol.targets[y]*sum(model[:p_gs_bus][bus_idx, findfirst(==(y), years), hour_idx] for bus_idx=bus_idxs, hour_idx=1:nhour))

end
export modify_model!


## Helper Functions
#############################################################################################################

"""
    add_to_gs_pol_list!(pol, config, data) -> 

Adds the generation standard policy name and type as a key value pair in an ordered dict `data[:gs_pol_list]`
"""
function add_to_gs_pol_list!(pol::GenerationStandard, config, data)
    if haskey(data, :gs_pol_list) #TODO: could come up with better name
        data[:gs_pol_list][pol.name] = pol.gs_type
    else 
        #create gs_pol_list if it doesn't exist yet
        data[:gs_pol_list] = OrderedDict{}(
            pol.name => pol.gs_type
        )
    end
end

