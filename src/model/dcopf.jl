# DC OPF setup



"""
    setup_dcopf!(config, data, model)

Set up a DC OPF problem
"""
function setup_dcopf!(config, data, model)
    
    # define tables 
    bus = get_bus_table(data)
    rep_time = get_rep_time(data) # weight of representative time chunks (hours) 
    gen = get_gen_table(data)
    branch = get_branch_table(data)


    ## Variables

    # Voltage Angle
    @variable(model, θ[bus_id in 1:nrow(bus), time_id in 1:length(rep_time)])

    # Power Generation
    @variable(model, pg[gen_id in 1:nrow(gen), time_id in 1:length(rep_time)])

    # Capacity
    @variable(model, pcap[gen_id in 1:nrow(gen)])

    # Load Served
    @variable(model, pl[bus_id in 1:nrow(bus), time_id in 1:length(rep_time)] >= 0)



    ## Constraints

    # Constrain Power Flow
    @constraint(model, cons_pf[bus_id in 1:nrow(bus), time_id in 1:length(rep_time)], 
            get_pg_bus(data, model, bus_id, time_id) - get_pl_bus(data, model, bus_id, time_id) == 
            get_pf_bus(data, model, bus_id, time_id))

    # Constrain Reference Bus 
    @constraint(model, cons_ref_bus[ref_bus_id in get_ref_bus_ids(data)], 
            model[:θ][ref_bus_id] == 0)

    # Constrain Power Generation 
    @constraint(model, cons_pg_min[gen_id in 1:nrow(gen), time_id in 1:length(rep_time)],
            pg[gen_id, time_id] >= get_pg_min(data, model, gen_id, time_id))
    @constraint(model, cons_pg_max[gen_id in 1:nrow(gen), time_id in 1:length(rep_time)],
            pg[gen_id, time_id] <= get_pg_max(data, model, gen_id, time_id)) 

    # Constrain Load Served 
    @constraint(model, cons_pl[bus_id in 1:nrow(bus), time_id in 1:length(rep_time)], 
            pl[bus_id, time_id] <= get_dl(data, model, bus_id, time_id))

    # Constrain Capacity
    @constraint(model, cons_pcap_min[gen_id in 1:nrow(gen)], 
            pcap[gen_id] >= get_pcap_min(data, model, gen_id))
    @constraint(model, cons_pcap_max[gen_id in 1:nrow(gen)], 
            pcap[gen_id] <= get_pcap_max(data, model, gen_id))

    # Constrain Transmission Lines 
    @constraint(model, cons_branch_pf_pos[branch_id in 1:nrow(branch), time_id in 1:length(rep_time)], 
            get_pf_branch(data, model, branch_id, time_id) <= get_pf_branch_max(data, model, branch_id, time_id))

    @constraint(model, cons_branch_pf_neg[branch_id in 1:nrow(branch), time_id in 1:length(rep_time)], 
            -get_pf_branch(data, model, branch_id, time_id) <= get_pf_branch_max(data, model, branch_id, time_id))
    


    # Objective Function

    @expression(model, obj, 0)
    # TODO: build out this expression
    
    # add costs to the objective 
    add_varibale_gen_cost!(data, model, :vom)
    # TODO: add_fixed_gen_cost! create similar function to add_varibale_gen_cost for fixed costs
    #which are multiplied by capacity and rep_time
    


    model[:obj] = 

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
function get_bus_table(data) end

"""
    get_rep_time(data)

Returns the array of representative time chunks (hours)
""" 
function get_rep_time(data) end

"""
    get_gen_table(data)

Returns gen data table
"""
function get_gen_table(data) end

"""
    get_branch_table(data)

Returns table of the transmission lines (branches) from data. 
"""
function get_branch_table(data) end


"""
    get_pg_bus(data, model, bus_id, time_id)

Returns total power generation for a bus at a time
"""
function get_pg_bus(data, model, bus_id, time_id) end
# function get_pg_bus(data, m, bus_id, time_id)
# 	gen_ids = get_gen_ids(data, bus_id)
# 	isempty(gen_ids) && return 0.0
# 	return sum(gen_id->get_power_gen(data, m, gen_id), gen_ids)
# end


get_pg_gen(data, model, gen_id, time_id)


"""
    get_pl_bus(data, model, bus_id, time_id)

Returns total load served for a bus at a time
"""
function get_pl_bus(data, model, bus_id, time_id) end


"""
    get_pf_bus(data, model, bus_id, time_id)

Returns total power flow out of the bus
""" 
function get_pf_bus(data, model, bus_id, time_id) end


"""
    get_pf_branch(data, model, branch_id, time_id)

Return total power flow out on a branch 
""" 
function get_pf_branch(data, model, branch_id, time_id) end


"""
    get_ref_bus_ids(data)

Returns reference bus ids
"""
function get_ref_bus_ids(data) end


# the get pg min and max functions require capacity which is a variable in model
"""
    get_pg_min(data, model, gen_id, time_id)

Returns min power generation for a generator at a time
""" 
function get_pg_min(data, model, gen_id, time_id) end

"""
    get_pg_max(data, model, gen_id, time_id)

Returns max power generation for a generator at a time
""" 
function get_pg_max(data, model, gen_id, time_id) end


"""
    get_dl(data, model, bus_id, time_id)

Returns the demanded load at a bus at a time. Load served (pl) can be less than demanded when load is curtailed. 
"""
function get_dl(data, model, bus_id, time_id) end


"""
    get_pcap_min(data, model, gen_id)

Returns min capacity for a generator
"""
function get_pcap_min(data, model, gen_id) end

"""
    get_pcap_max(data, model, gen_id)

Returns max capacity for a generator
"""
function get_pcap_max(data, model, gen_id) end


""" 
    get_pf_branch_max(data, model, branch_id, time_id)

Returns max power flow on a branch at a given time. 
"""
function get_pf_branch_max(data, model, branch_id, time_id) end


# Model Mutation Functions
################################################################################

"""
    add_variable_gen_cost!(data, model, s::Symbol)

Defines the expression for variable cost `s` and adds it to the objective function. Variable cost is 
    multiplied by the energy generated. 
"""
function add_variable_gen_cost!(data, model, s::Symbol)
    gen = get_gen_table(data)
    model[s] = @expression(model, [gen_id in 1:nrow(gen)],
        gen[gen_id, s].*get_eg_gen(data, model, gen_id))
    add_obj_cost!(data, model, s::Symbol)
end

"""
    get_eg_gen(data, model, gen_id)

Returns the total energy generation from a gen summed over all rep time. 
"""
function get_eg_gen(data, model, gen_id)
    rep_time = get_rep_time(data)
    return sum(rep_time[time_id] .* model[:pg][gen_id, time_id] for time_id in 1:length(rep_time))
end
  
"""
    add_obj_cost!(data, model, s::Symbol)

Adds cost `s` to the objective function of the `model`.
"""
function add_obj_cost!(data, model, s::Symbol) 
    model[:obj] += sum(model[s])
    #TODO: add documentation of the cost added to some part of data so we have a list of everything in obj function
end



