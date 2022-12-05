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
    @variable(model, pcap[gen_idx in 1:nrow(gen), year_idx in 1:length(years)])

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
    @constraint(model, cons_pl_min[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            pl[bus_idx, year_idx, hour_idx] >= 0)
    @constraint(model, cons_pl_max[bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:length(rep_hours)], 
            pl[bus_idx, year_idx, hour_idx] <= get_dl(data, model, bus_idx, year_idx, hour_idx))
    

    # Constrain Capacity
    @constraint(model, cons_pcap_min[gen_idx in 1:nrow(gen), year_idx in 1:length(years)], 
            pcap[gen_idx, year_idx] >= get_pcap_min(data, model, gen_idx))
    @constraint(model, cons_pcap_max[gen_idx in 1:nrow(gen), year_idx in 1:length(years)], 
            pcap[gen_idx, year_idx] <= get_pcap_max(data, model, gen_idx))

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


### Data Table Functions

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


### Get Model Variables Functions


"""
    get_pg_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total power generation for a bus at a time
"""
function get_pg_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, model, bus_idx)
    sum(model[:pg][bus_gens, year_idx, hour_idx])
end


"""
    get_pl_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total load served for a bus at a time
"""
function get_pl_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, model, bus_idx)
    sum(model[:pl][bus_gens, year_idx, hour_idx])
end


"""
    get_pf_bus(data, model, f_bus_idx, year_idx, hour_idx)

Returns net power flow out of the bus
""" 
function get_pf_bus(data, model, f_bus_idx, year_idx, hour_idx) 
    sum(t_bus_idx -> get_pf_branch(data, model, f_bus_idx, t_bus_idx, year_idx, hour_idx), get_connected_buses(data, f_bus_idx))
end


"""
    get_pf_branch(data, model, f_bus_idx, t_bus_idx, year_idx, hour_idx)

Return total power flow on a branch. Positive value if power flows from f_bus to t_bus, negative if it flows from t_bus to f_bus. 
""" 
function get_pf_branch(data, model, f_bus_idx, t_bus_idx, year_idx, hour_idx)
    Δθ = model[:θ][f_bus_idx, year_idx, hour_idx] - model[:θ][t_bus_idx, year_idx, hour_idx] #positive for power flow out(f_bus to t_bus)
    branch_idx = get_branch_idx(data, f_bus_idx, t_bus_idx)
    if branch_idx > 0 
        x = get_branch_value(data, :x, branch_idx, year_idx, hour_idx) # not sure I need time indices, check function arguments
    elseif branch_idx < 0
        x = get_branch_value(data, :x, -branch_idx, year_idx, hour_idx) # not sure I need time indices, check function arguments
    return Δθ / x
end
# look at shadow price notebook 

### System Mapping Helper Functions

"""
    get_branch_idx(data, f_bus_idx, t_bus_idx)

Returns a vector with the branch idx and the f_bus and t_bus indices for that branch (could be flipped from inputs). 
"""
function get_branch_idx(data, f_bus_idx, t_bus_idx) 
    branch = get_branch_table(data)
    for i in 1:nrows(branch)
        if branch.f_bus_idx = f_bus_idx && branch.t_bus_idx = t_bus_idx
            return i
        elseif branch.f_bus_idx = t_bus_idx && branch.t_bus_idx = f_bus_idx
            return -i
        else
            error("No branch connecting these buses.") # change this so doesn't error but keeps going or something, maybe returns 0
        end
    end
end

"""
    get_connected_buses(data, bus_idx)

Returns vector of idxs for all buses connected to the specified buses. Returns whether it is the f_bus or the t_bus
"""
function get_connected_buses(data, bus_idx) 
    branch = get_branch_table(data)
    connect_bus_idxs = []
    for r in eachrow(branch)
        r.f_bus_idx == bus_idx ? push!(connect_bus_idxs, r.t_bus_idx)
        r.t_bus_idx == bus_idx ? push!(connect_bus_idxs, r.f_bus_idx)
    end
    unique!(connected_bus_idxs) #removes duplicates
    return connect_bus_idxs
end

"""
    get_bus_gens(data, model, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, model, bus_idx) 
    gen = get_gen_table(data)
    findall(x -> x == bus_idx, gen.bus_idx)
end

"""
    get_ref_bus_idxs(data)

Returns reference bus ids
"""
function get_ref_bus_idxs(data) 
    bus = get_bus_table(data)
    return findall(bus.ref_bus)
end

### Contraint Info Functions

"""
    get_pg_min(data, model, gen_idx, year_idx, hour_idx)

Returns min power generation for a generator at a time, based on the optional gen property `cf_min`
""" 
function get_pg_min(data, model, gen_idx, year_idx, hour_idx) 
   default_pg_min = 0.0;
   if hasproperty(data[:gen], cf_min)
    pcap = model[:pcap][gen_idx, year_idx]
    cf_min = get_gen_value(data, :cf_min, gen_idx, year_idx, hour_idx)
     return pcap .* cf_min 
   else
     return default_pg_min
end

"""
    get_pg_max(data, model, gen_idx, year_idx, hour_idx)

Returns max power generation for a generator at a time, based on the lower of gen properties `af` and `cf_max`
""" 
function get_pg_max(data, model, gen_idx, year_idx, hour_idx) 
    af = get_gen_value(data, :af, gen_idx, year_idx, hour_idx)
    pcap = model[:pcap][gen_idx, year_idx]
    if hasproperty(data[:gen], cf_max)
        cf_max = get_gen_value(data, :cf_max, gen_idx, year_idx, hour_idx)
        cf_max < af ? pg_max = cf_max .* pcap : pg_max = af .* pcap
    else 
        pg_max = af .* pcap
    end
    return pg_max
end


"""
    get_pcap_min(data, model, gen_idx)

Returns min capacity for a generator
"""
function get_pcap_min(data, model, gen_idx) 
    return get_gen_value(data, :pcap_min, gen_idx)
end

"""
    get_pcap_max(data, model, gen_idx)

Returns max capacity for a generator
"""
function get_pcap_max(data, model, gen_idx) 
    return get_gen_value(data, :pcap_max, gen_idx)
end


""" 
    get_pf_branch_max(data, model, branch_idx, year_idx, hour_idx)

Returns max power flow on a branch at a given time. 
"""
function get_pf_branch_max(data, model, branch_idx, year_idx, hour_idx) 
    return get_branch_value(data, :pf_max, branch_idx)
end

### Misc Helper Functions

"""
    get_dl(data, model, bus_idx, year_idx, hour_idx)

Returns the demanded load at a bus at a time. Load served (pl) can be less than demanded when load is curtailed. 
"""
function get_dl(data, model, bus_idx, year_idx, hour_idx) 
    return get_bus_value(data, :pd, bus_idx, year_idx, hour_idx)
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
    get_eg_gen(data, model, gen_idx, year_idx)

Returns the total energy generation from a gen summed over rep time for the given year. 
"""
function get_eg_gen(data, model, gen_idx, year_idx)
    rep_hours = get_rep_hours(data)
    return sum(rep_hours[hour_idx] .* model[:pg][gen_idx, year_idx, hour_idx] for hour_idx in 1:length(rep_hours))
end

"""
    get_voll(data, model, bus_idx, year_idx, hour_idx)

Returns the value of lost load at given bus and time
"""
function get_voll(data, model, bus_idx, year_idx, hour_idx) 
    # If we want voll to be by bus_idx this could be modified and load_voll() will need to be changed
    return data[:voll]
end


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

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx) .* get_eg_gen(data, model, gen_idx, year_idx))

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

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx) .* model[:pcap][gen_idx, year_idx])

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
