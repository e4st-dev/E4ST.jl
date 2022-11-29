# DC OPF setup



"""
    setup_dcopf!(config, data, model)

Set up a DC OPF problem
"""
function setup_dcopf!(config, data, model)
    
    # define tables 
    bus = get_bus_table(data)
    years = get_years(data)
    rep_hours = get_rep_hours(data) # weight of representative time chunks (hours) 
    gen = get_gen_table(data)
    branch = get_branch_table(data)


    ## Variables

    # Voltage Angle
    @variable(model, θ[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)])

    # Power Generation
    @variable(model, pg[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)])

    # Capacity
    @variable(model, pcap[gen_idx in 1:nrow(gen)])

    # Load Served
    @variable(model, pl[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)] >= 0)



    ## Constraints

    # Constrain Power Flow
    @constraint(model, cons_pf[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            get_pg_bus(data, model, bus_idx, year_idx, hour_idx) - get_pl_bus(data, model, bus_idx, year_idx, hour_idx) == 
            get_pf_bus(data, model, bus_idx, year_idx, hour_idx))

    # Constrain Reference Bus 
    @constraint(model, cons_ref_bus[ref_bus_id in get_ref_bus_idxs(data)], 
            model[:θ][ref_bus_id] == 0)

    # Constrain Power Generation 
    @constraint(model, cons_pg_min[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)],
            pg[gen_idx, year_idx, hour_idx] >= get_pg_min(data, model, gen_idx, year_idx, hour_idx))
    @constraint(model, cons_pg_max[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)],
            pg[gen_idx, year_idx, hour_idx] <= get_pg_max(data, model, gen_idx, year_idx, hour_idx)) 

    # Constrain Load Served 
    @constraint(model, cons_pl[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            pl[bus_idx, year_idx, hour_idx] <= get_dl(data, model, bus_idx, year_idx, hour_idx))

    # Constrain Capacity
    @constraint(model, cons_pcap_min[gen_idx in 1:nrow(gen)], 
            pcap[gen_idx] >= get_pcap_min(data, model, gen_idx))
    @constraint(model, cons_pcap_max[gen_idx in 1:nrow(gen)], 
            pcap[gen_idx] <= get_pcap_max(data, model, gen_idx))

    # Constrain Transmission Lines 
    @constraint(model, cons_branch_pf_pos[branch_idx in 1:nrow(branch), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            get_pf_branch(data, model, branch_idx, year_idx, hour_idx) <= get_pf_branch_max(data, model, branch_idx, year_idx hour_idx))

    @constraint(model, cons_branch_pf_neg[branch_idx in 1:nrow(branch), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            -get_pf_branch(data, model, branch_idx, year_idx, hour_idx) <= get_pf_branch_max(data, model, branch_idx, year_idx, hour_idx))
    


    # Objective Function

    # This is written as a benefits maximization function, so costs are subtracted and benefits are added. 

    @expression(model, obj, 0)
    # TODO: build out this expression

    data[:obj_vars] = OrderedDict{Symbol, Any}()
    
    # # subtract costs from the objective 
    # add_variable_gen_var!(data, model, :vom, oper = -)
    # add_variable_gen_var!(data, model, :fuel_cost, oper = -)

    # add_fixed_gen_var!(data, model, :fom, oper = -)
    # add_fixed_gen_var!(data, model, :invest_cost, oper = -)


    # Power System Costs
    add_obj_term!(data, model, PerMWhGen(), :vom, oper = -)
    add_obj_term!(data, model, PerMWhGen(), :fuel_cost, oper = -)

    add_obj_term!(data, model, PerMWCap(), :fom, oper = -)
    add_obj_term!(data, model, PerMWCap(), :invest_cost, oper = -)

    # Consumer Benefits
    add_obj_term!(data, model, ConsumerBenefit(), :consumer_benefit, oper = +)


    # @objective() goes in the setup
    

    return model
end


################################################################################
# Helper Functions
################################################################################


# Accessor Functions
################################################################################

"""
    get_bus_table(data)

Returns the bus data table
"""
function get_bus_table(data) 
    return data[:bus]    
end

"""
    get_years(data)

Returns the array of years
"""
function get_years(data) 
    return data[:years]
end

"""
    get_rep_hours(data)

Returns the vector of representative time chunks (hours)
""" 
function get_rep_hours(data) 
    return data[:hours].hours
end

"""
    get_gen_table(data)

Returns gen data table
"""
function get_gen_table(data) 
    return data[:gen]
end

"""
    get_branch_table(data)

Returns table of the transmission lines (branches) from data. 
"""
function get_branch_table(data)
    return data[:branch]
end


"""
    get_pg_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total power generation for a bus at a time
"""
function get_pg_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, model, bus_idx)
    sum(model[:pg][bus_gens, year_idx, hour_idx])
end


"""
    get_bus_gens(data, model, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, model, bus_idx) end

"""
    get_pl_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total load served for a bus at a time
"""
function get_pl_bus(data, model, bus_idx, year_idx, hour_idx) end


"""
    get_pf_bus(data, model, bus_idx, year_idx, hour_idx)

Returns net power flow out of the bus
""" 
function get_pf_bus(data, model, bus_idx, year_idx, hour_idx) end


"""
    get_pf_branch(data, model, branch_idx, year_idx, hour_idx)

Return total power flow on a branch 
""" 
function get_pf_branch(data, model, branch_idx, year_idx, hour_idx) end


"""
    get_ref_bus_idxs(data)

Returns reference bus ids
"""
function get_ref_bus_idxs(data) 
    bus = get_bus_table(data)
    return findall(bus.ref_bus)
end


# the get pg min and max functions require capacity which is a variable in model
"""
    get_pg_min(data, model, gen_idx, year_idx, hour_idx)

Returns min power generation for a generator at a time
""" 
function get_pg_min(data, model, gen_idx, year_idx, hour_idx) 
    
end

"""
    get_pg_max(data, model, gen_idx, year_idx, hour_idx)

Returns max power generation for a generator at a time
""" 
function get_pg_max(data, model, gen_idx, year_idx, hour_idx) 

end


"""
    get_dl(data, model, bus_idx, year_idx, hour_idx)

Returns the demanded load at a bus at a time. Load served (pl) can be less than demanded when load is curtailed. 
"""
function get_dl(data, model, bus_idx, year_idx, hour_idx) 
    return get_bus_value(data, :pd, bus_idx, year_idx, hour_idx)
end


"""
    get_pcap_min(data, model, gen_idx)

Returns min capacity for a generator
"""
function get_pcap_min(data, model, gen_idx) 
    return data[:gen].pcap_min[gen_idx]
end

"""
    get_pcap_max(data, model, gen_idx)

Returns max capacity for a generator
"""
function get_pcap_max(data, model, gen_idx) 
    return data[:gen].pcap_max[gen_idx]
end


""" 
    get_pf_branch_max(data, model, branch_idx, year_idx, hour_idx)

Returns max power flow on a branch at a given time. 
"""
function get_pf_branch_max(data, model, branch_idx, year_idx, hour_idx) 
    return data[:branch].pf_max[branch_idx]
end


"""
    get_eg_gen(data, model, gen_idx)

Returns the total energy generation from a gen summed over all rep time. 
"""
function get_eg_gen(data, model, gen_idx)
    rep_hours = get_rep_hours(data)
    years = get_years(data)
    return sum(rep_hours[hour_idx] .* model[:pg][gen_idx, year_idx, hour_idx] for year_idx in 1:length(years), hour_idx in 1:length(rep_hours))
end

"""
    get_voll(data, model, bus_idx, year_idx, hour_idx)

Returns the value of lost load at given bus and time
"""
function get_voll(data, model, bus_idx, year_idx, hour_idx) end


# Model Mutation Functions
################################################################################
"""
    abstract type Term

Abstract type Term is used to add variables (terms) to the objective function or other functions. Subtypes include PerMWh and PerMW 
"""        
abstract type Term end

struct PerMWhGen <: Term end
struct PerMWCap <: Term end
struct ConsumerBenefit <: Term end

# """
#     add_variable_gen_var!(data, model, s::Symbol; oper)

# Defines expression for the variable generator cost or revenue `s` which is multiplied by annual generation. Adds or subtracts that cost/rev to the objective function based on `oper`
# """
# function add_variable_gen_var!(data, model, s::Symbol; oper)
#     gen = get_gen_table(data)

#     model[s] = @expression(model, [gen_idx in 1:nrow(gen)],
#         gen[gen_idx, s] .* get_eg_gen(data, model, gen_idx))

#     add_obj_var!(data, model, s::Symbol, oper = oper)
# end


# """
#     add_fixed_gen_var!(data, model, s::Symbol; oper)

# Defines expression for the fixed generator cost or revenue `s` which is multiplied by capacity. Adds or subtracts that cost/rev to the objective function based on `oper` 
# """
# function add_fixed_gen_var!(data, model, s::Symbol; oper)
#     gen = get_gen_table(data)

#     model[s] = @expression(model, [gen_idx in 1:nrow(gen)],
#         gen[gen_idx, s] .* model[:pcap][gen_id])

#     add_obj_var!(data, model, s::Symbol, oper = oper)
# end


  

"""
    add_obj_term!(data, model, ::Term, s::Symbol; oper)

Adds or subtracts cost/revenue `s` to the objective function of the `model` based on the operator `oper`. Adds the cost/revenue to the objective variables list in data. 
"""
function add_obj_term!(data, model, term::Term, s::Symbol; oper) end

function add_obj_term!(data, model, ::PerMWhGen, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_gen_table(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen)],
        gen[gen_idx, s] .* get_eg_gen(data, model, gen_idx))

    # add or subtract the expression from the objective function
    if oper == + 
        model[:obj] += sum(model[s])
    elseif oper == -
        model[:obj] -= sum(model[s])
    else
        Base.error("The entered operator isn't valid, oper must be + or -")
    end
    #Add s to array of variables included obj
    data[:obj_vars][s] = oper
    
end

function add_obj_term!(data, model, ::PerMWCap, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_gen_table(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen)],
        gen[gen_idx, s] .* model[:pcap][gen_idx])

    # add or subtract the expression from the objective function
    if oper == + 
        model[:obj] += sum(model[s])
    elseif oper == -
        model[:obj] -= sum(model[s])
    else
        Base.error("The entered operator isn't valid, oper must be + or -")
    end
    #Add s to array of variables included obj
    data[:obj_vars][s] = oper
    
end

function add_obj_term!(data, model, ::ConsumerBenefit, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    bus = get_bus_table(data)
    rep_hours = get_rep_hours(data)

    # Use this expression for single VOLL
    model[s] = @expression (model, [bus_idx in 1:nrow(bus)],
        sum(get_voll(data, model, bus_idx, year_idx, hour_idx) .* rep_hours[hour_idx] .* get_pl_bus(data, model, bus_idx, hour_idx) for year_idx in 1:length(years), hour_idx in 1:length(rep_hours)))

    # # Use this expression if we ever get VOLL for each bus 

    # model[s] = @expression(model, [bus_idx in 1:nrow(bus)],
    #     bus[bus_idx, s] .* sum(rep_hours[hour_idx] .* get_pl_bus(data, model, bus_idx, year_idx, hour_idx) for year_idx in 1:length(years), hour_idx in 1:length(rep_hours)))

    # add or subtract the expression from the objective function
    if oper == + 
        model[:obj] += sum(model[s])
    elseif oper == -
        model[:obj] -= sum(model[s])
    else
        Base.error("The entered operator isn't valid, oper must be + or -")
    end
    #Add s to array of variables included obj
    data[:obj_vars][s] = oper
    
end

