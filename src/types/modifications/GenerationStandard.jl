@doc raw"""
    struct GenerationStandard{T} <: Policy

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
struct GenerationStandard{T} <: Policy 
    name::Symbol
    targets::OrderedDict
    crediting::Crediting
    gen_filters::OrderedDict
    load_bus_filters::OrderedDict

end


function GenerationStandard(;name, targets, crediting::OrderedDict, gen_filters, load_bus_filters)
    c = Crediting(crediting)
    return GenerationStandard(Symbol(name), targets, c, gen_filters, load_bus_filters)
end
export GenerationStandard

mod_rank(::Type{<:GenerationStandard}) = 1.0 #not sure this matters because this isn't usually a type specified in the config or a super type of something specified in the config. 


## Modifying Functions
#######################################################################################################################
"""
    modify_setup_data!(pol::GenerationStandard, config, data)

Adds column to the gen table with the credit level of the generation standard. Adds the name and type of the policy to the gs_pol_list in data. 
"""
function modify_setup_data!(pol::GenerationStandard, config, data)

    #get gen idxs 
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    #create get table column for policy, set to zeros to start
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], Ratio,
        "Credit level for generation standard: $(pol.name)")

    #set credit level in the gen table
    #call get_credit on gen_idxs, dispatching on crediting type
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        gen[gen_idx, pol.name] = Container(get_credit(pol.crediting, data, g))
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
    add_pl_gs_bus!(config, data, model)

    # create yearly constraint that qualifying generation meeting qualifying load
    # takes the form sum(gs_egen * credit) <= gs_value * sum(gs_load)

    cons_name = "cons_$(pol.name)"
    target_years = collect(keys(pol.targets))
    hour_weights = get_hour_weights(data)

    @info "Creating a generation constraint for the Generation Standard $(pol.name)."
    model[Symbol(cons_name)] = @constraint(model, 
        [
            yr_idx in 1:nyear;
            haskey(pol.targets, years[yr_idx])
        ],
        sum(
            get_egen_gen(data, model, gen_idx, yr_idx, hr_idx) * 
            get_table_num(data, :gen, pol.name, gen_idx, yr_idx, hr_idx)
            for gen_idx=gen_idxs, hr_idx=1:nhour
        ) >= (
            pol.targets[years[yr_idx]] * 
            sum(model[:pl_gs_bus][bus_idx, yr_idx, hr_idx]*hour_weights[hr_idx]
            for bus_idx=bus_idxs, hr_idx=1:nhour)
        )
    )
end
export modify_model!

"""
    modify_results!(mod::GenerationStandard, config, data)

Modifies the results by adding the following columns to the bus table:
* `pl_gs` - GS-qualifying load power, in MW
* `el_gs` - GS-qualifying load energy, in MWh.
"""
function modify_results!(mod::GenerationStandard, config, data)
    bus = get_table(data, :bus)

    # TODO: do any other results processing here

    # Add pl_gs and el_gs to the bus
    hasproperty(bus, :pl_gs) && return
    pl_gs_bus = get_raw_result(data, :pl_gs_bus)
    el_gs_bus = weight_hourly(data, pl_gs_bus)

    add_table_col!(data, :bus, :pl_gs, pl_gs_bus, MWServed, "Served Load Power that qualifies for generation standards")
    add_table_col!(data, :bus, :el_gs, el_gs_bus, MWhServed, "Served Load Energy that qualifies for generation standards")
    return
end
export modify_results!


## Helper Functions
#############################################################################################################

"""
    add_pl_gs_bus!(config, data, model)

Add the `pl_gs_bus` expression to the model which is load power that qualifies for generation standards.  This includes:
* Nominal load net any curtailed load `plnom_bus - plcurt_bus`
* Battery loss (i.e. difference between charge and discharge)
* Line losses
"""
function add_pl_gs_bus!(config, data, model)
    haskey(model, :pl_gs_bus) && return

    # Pull out necessary tables
    bus = get_table(data, :bus)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)


    plcurt_bus = model[:plcurt_bus]
    hour_weights = get_hour_weights(data)

    @expression(model, 
        pl_gs_bus[bus_idx in 1:nrow(bus), yr_idx in 1:nyear, hr_idx in 1:nhour], 
        get_plnom(data, bus_idx, yr_idx, hr_idx) - plcurt_bus[bus_idx, yr_idx, hr_idx]
        # Add DAC here
    )

    # Add line losses
    line_loss_type = config[:line_loss_type]
    line_loss_rate = config[:line_loss_rate]
    if line_loss_type == "plserv"
        loss_scalar = 1/(1-line_loss_rate) - 1
        for bus_idx in axes(bus, 1), yr_idx in 1:nyear, hr_idx in 1:nhour
            add_to_expression!(pl_gs_bus[bus_idx, yr_idx, hr_idx], pl_gs_bus[bus_idx, yr_idx, hr_idx], loss_scalar)
        end
    elseif line_loss_type == "pflow"
        for bus_idx in axes(bus, 1), yr_idx in 1:nyear, hr_idx in 1:nhour
            add_to_expression!(pl_gs_bus[bus_idx, yr_idx, hr_idx], pflow_out_bus[bus_idx, yr_idx, hr_idx], line_loss_rate)
        end
    else
        error("config[:line_loss_type] must be `plserv` or `pflow`, but $line_loss_type was given")

    end

    # Add storage to the expression.  Note this must come after line losses so that the generation-side storage doesn't get penalized for line losses.
    if haskey(data, :storage)
        pdischarge_stor = model[:pdischarge_stor]
        pcharge_stor = model[:pcharge_stor]
        hour_weights = get_hour_weights(data)
        storage = get_table(data, :storage)
        for (stor_idx, row) in enumerate(eachrow(storage))
            bus_idx = row.bus_idx

            # Only add line losses here if we're acconting for losses on plserv and with load-side storage devices
            line_loss_scalar = ((line_loss_type == "plserv" && row.side == "load") ? 1.0/(1.0-line_loss_rate) : 1.0)
            for yr_idx in 1:nyear, hr_idx in 1:nhour
                add_to_expression!(pl_gs_bus[bus_idx, yr_idx, hr_idx], pdischarge_stor[stor_idx, yr_idx, hr_idx], -line_loss_scalar)
                add_to_expression!(pl_gs_bus[bus_idx, yr_idx, hr_idx], pcharge_stor[stor_idx, yr_idx, hr_idx], line_loss_scalar)
            end
        end
    end

    return
end
export add_pl_gs_bus!


