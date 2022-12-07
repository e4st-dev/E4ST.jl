# DC OPF setup



"""
    setup_dcopf!(config, data, model)

Set up a DC OPF problem
"""
function setup_dcopf!(config, data, model)
    
    # define tables 
    bus = get_bus_table(data)
    years = get_years(data)
    rep_hours = get_hours_table(data) # weight of representative time chunks (hours) 
    gen = get_gen_table(data)
    branch = get_branch_table(data)


    ## Variables

    # Voltage Angle
    @variable(model, θ[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)])

    # Power Generation
    @variable(model, pg[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)])

    # Capacity
    @variable(model, pcap[gen_idx in 1:nrow(gen), year_idx in 1:length(years)])

    # Load Served
    @variable(model, pl[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)] >= 0)


    ## Constraints

    # Constrain Power Flow
    @constraint(model, cons_pf[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)], 
            get_pg_bus(data, model, bus_idx, year_idx, hour_idx) - get_pl_bus(data, model, bus_idx, year_idx, hour_idx) == 
            get_pf_bus(data, model, bus_idx, year_idx, hour_idx))

    # Constrain Reference Bus 
    @constraint(model, cons_ref_bus[ref_bus_idx in get_ref_bus_idxs(data)], 
            model[:θ][ref_bus_idx] == 0)

    # Constrain Power Generation 
    @constraint(model, cons_pg_min[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)],
            pg[gen_idx, year_idx, hour_idx] >= get_pg_min(data, model, gen_idx, year_idx, hour_idx))
    @constraint(model, cons_pg_max[gen_idx in 1:nrow(gen), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)],
            pg[gen_idx, year_idx, hour_idx] <= get_pg_max(data, model, gen_idx, year_idx, hour_idx)) 

    # Constrain Load Served 
    @constraint(model, cons_pl_min[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)], 
            pl[bus_idx, year_idx, hour_idx] >= 0)
    @constraint(model, cons_pl_max[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)], 
            pl[bus_idx, year_idx, hour_idx] <= get_dl(data, bus_idx, year_idx, hour_idx))
    

    # Constrain Capacity
    @constraint(model, cons_pcap_min[gen_idx in 1:nrow(gen), year_idx in 1:length(years)], 
            pcap[gen_idx, year_idx] >= get_pcap_min(data, gen_idx, year_idx))
    @constraint(model, cons_pcap_max[gen_idx in 1:nrow(gen), year_idx in 1:length(years)], 
            pcap[gen_idx, year_idx] <= get_pcap_max(data, gen_idx, year_idx))

    # Constrain Transmission Lines 
    @constraint(model, cons_branch_pf_pos[branch_idx in 1:nrow(branch), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)], 
            get_pf_branch(data, model, branch_idx, year_idx, hour_idx) <= get_pf_branch_max(data, branch_idx, year_idx, hour_idx))

    @constraint(model, cons_branch_pf_neg[branch_idx in 1:nrow(branch), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)], 
            -get_pf_branch(data, model, branch_idx, year_idx, hour_idx) <= get_pf_branch_max(data, branch_idx, year_idx, hour_idx))
    


    # Objective Function

    # This is written as a benefits maximization function, so costs are subtracted and benefits are added. 

    @expression(model, obj, 0)
    # TODO: build out this expression

    data[:obj_vars] = OrderedDict{Symbol, Any}()


    # Power System Costs
    add_obj_term!(data, model, PerMWhGen(), :vom, oper = -)
    add_obj_term!(data, model, PerMWhGen(), :fuel_cost, oper = -)

    add_obj_term!(data, model, PerMWCap(), :fom, oper = -)
    add_obj_term!(data, model, PerMWCap(), :capex, oper = -)

    # Consumer Benefits
    add_obj_term!(data, model, ConsumerBenefit(), :consumer_benefit, oper = +)


    # @objective() goes in the setup
    

    return model
end
export setup_dcopf!

################################################################################
# Helper Functions
################################################################################


# Accessor Functions
################################################################################



### Get Model Variables Functions


"""
    get_pg_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total power generation for a bus at a time
"""
function get_pg_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, bus_idx)
    sum(model[:pg][bus_gens, year_idx, hour_idx])
end

export get_pg_bus


"""
    get_pl_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total load served for a bus at a time
"""
function get_pl_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, bus_idx)
    sum(model[:pl][bus_gens, year_idx, hour_idx])
end
export get_pl_bus

"""
    get_pf_bus(data, model, f_bus_idx, year_idx, hour_idx)

Returns net power flow out of the bus
""" 
function get_pf_bus(data, model, bus_idx, year_idx, hour_idx) 
    branches = [] #vector of the connecting branches with positive values for branches going out (branch f_bus = bus_idx) and negative values for branches coming in (branch t_bus = bus_idx)
    for t_bus_idx in get_connected_buses(data, bus_idx)
        push!(branches, get_branch_idx(data, bus_idx, t_bus_idx))
    end
    return sum(get_pf_branch(data, model, branch_idx, year_idx, hour_idx) for branch_idx in branches)
end
export get_pf_bus

"""
    get_pf_branch(data, model, branch_idx, year_idx, hour_idx)

Return total power flow on a branch. 
If branch_idx is positive then positive power flow is in the direction f_bus -> t_bus listed in the branch table. It is measuring the power flow out of f_bus.
If branch_idx is negative then positive power flow is in the opposite direction, t_bus -> f_bus listed in the branch table. It is measuring the power flow out of t_bus. 
""" 
function get_pf_branch(data, model, branch_idx, year_idx, hour_idx)
    if branch_idx == 0 
        return 0
    else
        f_bus_idx = data[:branch].f_bus_idx[branch_idx]
        t_bus_idx = data[:branch].t_bus_idx[branch_idx]
        if branch_idx > 0 
            x = get_branch_value(data, :x, branch_idx, year_idx, hour_idx)
            Δθ = model[:θ][f_bus_idx, year_idx, hour_idx] - model[:θ][t_bus_idx, year_idx, hour_idx] #positive for power flow out(f_bus to t_bus)
            return Δθ / x
        elseif branch_idx < 0
            x = get_branch_value(data, :x, -branch_idx, year_idx, hour_idx)
            Δθ = model[:θ][t_bus_idx, year_idx, hour_idx] - model[:θ][f_bus_idx, year_idx, hour_idx] 
            return Δθ / x
        end
    end
end
export get_pf_branch


### Contraint Info Functions

"""
    get_pg_min(data, model, gen_idx, year_idx, hour_idx)

Returns min power generation for a generator at a time, based on the optional gen property `cf_min`
""" 
function get_pg_min(data, model, gen_idx, year_idx, hour_idx) 
   default_pg_min = 0.0;
   if hasproperty(data[:gen], :cf_min)
    pcap = model[:pcap][gen_idx, year_idx]
    cf_min = get_gen_value(data, :cf_min, gen_idx, year_idx, hour_idx)
     return pcap .* cf_min 
   else
     return default_pg_min
   end
end
export get_pg_min

"""
    get_pg_max(data, model, gen_idx, year_idx, hour_idx)

Returns max power generation for a generator at a time, based on the lower of gen properties `af` and `cf_max`
""" 
function get_pg_max(data, model, gen_idx, year_idx, hour_idx) 
    af = get_gen_value(data, :af, gen_idx, year_idx, hour_idx)
    pcap = model[:pcap][gen_idx, year_idx]
    if hasproperty(data[:gen], :cf_max)
        cf_max = get_gen_value(data, :cf_max, gen_idx, year_idx, hour_idx)
        cf_max < af ? pg_max = cf_max .* pcap : pg_max = af .* pcap
    else 
        pg_max = af .* pcap
    end
    return pg_max
end
export get_pg_max


### Misc Helper Functions



"""
    get_eg_gen(data, model, gen_idx)

Returns the total energy generation from a gen summed over all rep time. 

    get_eg_gen(data, model, gen_idx, year_idx)

Returns the total energy generation from a gen summed over rep time for the given year. 
"""
function get_eg_gen(data, model, gen_idx)
    rep_hours = get_hours_table(data)
    years = get_years(data)
    return sum(rep_hours.hours[hour_idx] .* model[:pg][gen_idx, year_idx, hour_idx] for year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
end

function get_eg_gen(data, model, gen_idx, year_idx)
    rep_hours = get_hours_table(data)
    return sum(rep_hours.hours[hour_idx] .* model[:pg][gen_idx, year_idx, hour_idx] for hour_idx in 1:nrow(rep_hours))
end

"""
    get_eg_gen(data, model, gen_idx, year_idx, hour_idx)

Returns the total energy generation from a gen summed over rep time for the given year. 
"""
function get_eg_gen(data, model, gen_idx, year_idx)
    return model[:pg][gen_idx, year_idx, hour_idx]
end

export get_eg_gen




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
    years = get_years(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx, :) .* get_eg_gen(data, model, gen_idx, year_idx))

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
    years = get_years(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx, :) .* model[:pcap][gen_idx, year_idx])

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
    rep_hours = get_hours_table(data)
    years = get_years(data)

    # Use this expression for single VOLL
    model[s] = @expression(model, [bus_idx in 1:nrow(bus)],
        sum(get_voll(data, bus_idx, year_idx, hour_idx) .* rep_hours.hours[hour_idx] .* get_pl_bus(data, model, bus_idx, year_idx, hour_idx) for year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)))

    # # Use this expression if we ever get VOLL for each bus 

    # model[s] = @expression(model, [bus_idx in 1:nrow(bus)],
    #     bus[bus_idx, s] .* sum(rep_hours.hours[hour_idx] .* get_pl_bus(data, model, bus_idx, year_idx, hour_idx) for year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)))

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
export add_obj_term!