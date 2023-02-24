# DC OPF setup



"""
    setup_dcopf!(config, data, model)

Set up a DC OPF problem
"""
function setup_dcopf!(config, data, model)
    
    # define tables 
    bus = get_table(data, :bus)
    years = get_years(data)
    rep_hours = get_table(data, :hours) # weight of representative time chunks (hours) 
    gen = get_table(data, :gen)
    branch = get_table(data, :branch)
    nbus = nrow(bus)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nbranch = nrow(branch)
    ngen = nrow(gen)


    ## Variables
    @info "Creating Variables"

    # Voltage Angle
    @variable(model, 
        θ_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
        start=0.0,
        lower_bound = -1e6, # Lower value from MATLAB E4ST minimum(res.base.bus(:, VA)) was ~-2.5e5
        upper_bound =  1e6  # Upper value from MATLAB E4ST maximum(res.base.bus(:, VA)) was ~200
    )

    # Capacity
    @variable(model, 
        pcap_gen[gen_idx in 1:ngen, year_idx in 1:nyear], 
        start=0.0, #get_gen_value(data, :pcap0, gen_idx, year_idx, :), # Setting to 0.0 for feasibility
        lower_bound = get_pcap_min(data, gen_idx, year_idx),
        upper_bound = get_pcap_max(data, gen_idx, year_idx),
    )

    # Power Generation
    @variable(model, 
        pgen_gen[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour], 
        start=0.0,
        lower_bound = 0.0,
        upper_bound = get_pcap_max(data, gen_idx, year_idx),
    )

    # Load/Power Served
    @variable(model, 
        pcurt_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
        start=get_pdem_bus(data, bus_idx, year_idx, hour_idx), #get_pdem_bus(data, bus_idx, year_idx, hour_idx), # Theoreritically this is feasible.  May want to change to 0.0
        lower_bound = 0.0,
        upper_bound = get_pdem_bus(data, bus_idx, year_idx, hour_idx),
    )


    ## Expressions to be used later
    @info "Creating Expressions"
    
    # Power flowing through a given branch
    @expression(model, pflow_branch[branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour], get_pflow_branch(data, model, branch_idx, year_idx, hour_idx))

    # Power flowing out of a given bus
    @expression(model, pflow_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_pflow_bus(data, model, bus_idx, year_idx, hour_idx))

    # Curtailed power of a given bus
    @expression(model, pserv_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_pdem(data, bus_idx, year_idx, hour_idx) - pcurt_bus[bus_idx, year_idx, hour_idx])

    # Generated power of a given bus
    @expression(model, pgen_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_pgen_bus(data, model, bus_idx, year_idx, hour_idx))

    # Generated energy at a given generator
    @expression(model, egen_gen[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour], get_egen_gen(data, model, gen_idx, year_idx, hour_idx))


    ## Constraints
    @info "Creating Constraints"
    # Constrain Power Flow / Power Balance
    @constraint(model, cons_pflow[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
            get_pgen_bus(data, model, bus_idx, year_idx, hour_idx) - pserv_bus[bus_idx, year_idx, hour_idx] == 
            pflow_bus[bus_idx, year_idx, hour_idx])

    # Constrain Power Generation
    if hasproperty(gen, :cf_min)
        @constraint(model, cons_pgen_min[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour],
            pgen_gen[gen_idx, year_idx, hour_idx] >= get_pgen_min(data, model, gen_idx, year_idx, hour_idx))
    end
    @constraint(model, cons_pgen_max[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour],
            pgen_gen[gen_idx, year_idx, hour_idx] <= get_pgen_max(data, model, gen_idx, year_idx, hour_idx)) 


    # Constrain Reference Bus
    for ref_bus_idx in get_ref_bus_idxs(data), year_idx in 1:nyear, hour_idx in 1:nhour
        fix(model[:θ_bus][ref_bus_idx, year_idx, hour_idx], 0.0, force=true)
    end

    # Constrain Transmission Lines 
    @constraint(model,
        cons_branch_pflow_pos[
            branch_idx in 1:nbranch,
            year_idx in 1:nyear,
            hour_idx in 1:nhour;
            get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) > 0
        ], 
        pflow_branch[branch_idx, year_idx, hour_idx] <= get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)
    )

    @constraint(model, 
        cons_branch_pflow_neg[
            branch_idx in 1:nbranch, 
            year_idx in 1:nyear, 
            hour_idx in 1:nhour;
            get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) > 0
        ], 
        -pflow_branch[branch_idx, year_idx, hour_idx] <= get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)
    )
    
    # Constrain Capacity to 0 before the start/build year 
    prebuild_year_idxs = map(gen_idx -> get_prebuild_year_idxs(data, gen_idx), 1:ngen)
    if any(!isempty, prebuild_year_idxs)
        @constraint(model, cons_pcap_prebuild[gen_idx in 1:ngen, year_idx in prebuild_year_idxs[gen_idx]],
            pcap_gen[gen_idx, year_idx] == 0) 
    end

    # Constrain existing capacity to only decrease (only retire, not add capacity)
    if nyear > 1
        @constraint(model, cons_pcap_noadd[gen_idx in 1:ngen, year_idx in get_year_on_sim_idx(data, gen_idx):(nyear-1)], 
                pcap_gen[gen_idx, year_idx+1] <= pcap_gen[gen_idx, year_idx])
    end

    
    ## Objective Function 
    @info "Building Objective"
    @expression(model, obj, 0*model[:θ_bus][1,1,1]) 
    # needed to be defined as an GenericAffExp instead of an Int64 so multiplied by an arbitrary var


    # This keeps track of the expressions added to the obj and their signs
    data[:obj_vars] = OrderedDict{Symbol, Any}()

    # This is written as a cost minimization where costs are added to the obj
    
    # Power System Costs
    add_obj_term!(data, model, PerMWhGen(), :vom, oper = +)
    add_obj_term!(data, model, PerMWhGen(), :fuel_cost, oper = +)

    add_obj_term!(data, model, PerMWCap(), :fom, oper = +)
    add_obj_term!(data, model, PerMWCap(), :capex_obj, oper = +) 

    # Curtailment Cost
    add_obj_term!(data, model, PerMWhCurtailed(), :curtailment_cost, oper = +)



    # @objective() goes in the setup after modifications have been made 
    

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
    get_pgen_bus(data, model, bus_idx, year_idx, hour_idx)

Returns total power generation for a bus at a time
    * To use this to retieve the variable values after the model has been optimized, wrap the function with value() like this: value.(get_pgen_bus).
"""
function get_pgen_bus(data, model, bus_idx, year_idx, hour_idx) 
    bus_gens = get_bus_gens(data, bus_idx)
    sum(model[:pgen_gen][bus_gens, year_idx, hour_idx])
end
export get_pgen_bus


"""
    get_pflow_bus(data, model, f_bus_idx, year_idx, hour_idx)

Returns net power flow out of the bus
* To use this to retieve the variable values after the model has been optimized, wrap the function with value() like this: value.(get_pflow_bus).
""" 
function get_pflow_bus(data, model, bus_idx, year_idx, hour_idx) 
    branch_idxs = get_table(data, :bus)[bus_idx, :connected_branch_idxs] #vector of the connecting branches with positive values for branches going out (branch f_bus = bus_idx) and negative values for branches coming in (branch t_bus = bus_idx)
    isempty(branch_idxs) && return 0.0
    return sum(get_pflow_branch(data, model, branch_idx, year_idx, hour_idx) for branch_idx in branch_idxs)
end
export get_pflow_bus

"""
    get_pflow_branch(data, model, branch_idx, year_idx, hour_idx)

Return total power flow on a branch. 
* If branch_idx_signed is positive then positive power flow is in the direction f_bus -> t_bus listed in the branch table. It is measuring the power flow out of f_bus.
* If branch_idx_signed is negative then positive power flow is in the opposite direction, t_bus -> f_bus listed in the branch table. It is measuring the power flow out of t_bus. 
* To use this to retieve the variable values after the model has been optimized, wrap the function with value() like this: value.(get_pflow_branch).
""" 
function get_pflow_branch(data, model, branch_idx_signed, year_idx, hour_idx)
    direction = sign(branch_idx_signed)
    branch_idx = abs(branch_idx_signed)

    f_bus_idx = data[:branch].f_bus_idx[branch_idx]
    t_bus_idx = data[:branch].t_bus_idx[branch_idx]
    x = get_branch_value(data, :x, branch_idx, year_idx, hour_idx)
    Δθ = direction * (model[:θ_bus][f_bus_idx, year_idx, hour_idx] - model[:θ_bus][t_bus_idx, year_idx, hour_idx]) #positive for power flow out(f_bus to t_bus)
    return Δθ / x
end
export get_pflow_branch


### Contraint/Expression Info Functions

"""
    get_pgen_min(data, model, gen_idx, year_idx, hour_idx)

Returns min power generation for a generator at a time. 
Default is 0 unless specified by the optional gen property `cf_min` (minimum capacity factor).
""" 
function get_pgen_min(data, model, gen_idx, year_idx, hour_idx) 
    if hasproperty(data[:gen], :cf_min)
        pcap = model[:pcap_gen][gen_idx, year_idx]
        cf_min = get_gen_value(data, :cf_min, gen_idx, year_idx, hour_idx)
        return pcap .* cf_min 
    else
        return 0.0
    end
end
export get_pgen_min

"""
    get_pgen_max(data, model, gen_idx, year_idx, hour_idx)

Returns max power generation for a generator at a time.
It is based on the lower of gen properties `af` (availability factor) and optional `cf_max` (capacity factor).
""" 
function get_pgen_max(data, model, gen_idx, year_idx, hour_idx) 
    af = get_gen_value(data, :af, gen_idx, year_idx, hour_idx)
    pcap = model[:pcap_gen][gen_idx, year_idx]
    if hasproperty(data[:gen], :cf_max)
        cf_max = get_gen_value(data, :cf_max, gen_idx, year_idx, hour_idx)
        cf_max < af ? pgen_max = cf_max .* pcap : pgen_max = af .* pcap
    else 
        pgen_max = af .* pcap
    end
    return pgen_max
end
export get_pgen_max


"""
    get_egen_gen(data, model, gen_idx)

Returns the total energy generation from a gen summed over all rep time. 

    get_egen_gen(data, model, gen_idx, year_idx)

Returns the total energy generation from a gen summed over rep time for the given year. 

    get_egen_gen(data, model, gen_idx, year_idx, hour_idx)

Returns the total energy generation from a gen for the given year and hour.  This is pgen_gen multiplied by the number of hours spent at that representative hour.  See [`get_hour_weight`](@ref) 

* To use this to retieve the variable values after the model has been optimized, wrap the function with `value()` like this: `value.(get_egen_gen(args...))`.
"""
function get_egen_gen(data, model, gen_idx)
    rep_hours = get_table(data, :hours)
    years = get_years(data)
    return sum(rep_hours.hours[hour_idx] .* model[:pgen_gen][gen_idx, year_idx, hour_idx] for hour_idx in 1:nrow(rep_hours), year_idx in 1:length(years))
end

function get_egen_gen(data, model, gen_idx, year_idx)
    rep_hours = get_table(data, :hours)
    return sum(rep_hours.hours[hour_idx] .* model[:pgen_gen][gen_idx, year_idx, hour_idx] for hour_idx in 1:nrow(rep_hours))
end

function get_egen_gen(data, model, gen_idx, year_idx, hour_idx)
    return model[:pgen_gen][gen_idx, year_idx, hour_idx] * get_hour_weight(data, hour_idx)
end

export get_egen_gen




# Model Mutation Functions
################################################################################
"""
    abstract type Term

Abstract type Term is used to add variables (terms) to the objective function or other functions. Subtypes include PerMWhGen, PerMWCap, and PerMWhCurtailed. 
"""        
abstract type Term end

struct PerMWhGen <: Term end
struct PerMWCap <: Term end
struct PerMWhCurtailed <: Term end

  

"""
    add_obj_term!(data, model, ::Term, s::Symbol; oper)

Adds or subtracts cost/revenue `s` to the objective function of the `model` based on the operator `oper`. Adds the cost/revenue to the objective variables list in data. 
"""
function add_obj_term!(data, model, term::Term, s::Symbol; oper) end

function add_obj_term!(data, model, ::PerMWhGen, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    years = get_years(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx, :) .* get_egen_gen(data, model, gen_idx, year_idx))

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhGen(), s; oper = oper) 
    
end

function add_obj_term!(data, model, ::PerMWCap, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    years = get_years(data)

    model[s] = @expression(model, [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_gen_value(data, s, gen_idx, year_idx, :) .* model[:pcap_gen][gen_idx, year_idx])

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWCap(), s; oper = oper) 
    
end


function add_obj_term!(data, model, ::PerMWhCurtailed, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    bus = get_table(data, :bus)
    rep_hours = get_table(data, :hours)
    years = get_years(data)

    # Use this expression for single VOLL
    model[s] = @expression(model, [bus_idx in 1:nrow(bus)],
        sum(get_voll(data, bus_idx, year_idx, hour_idx) .* rep_hours.hours[hour_idx] .* model[:pcurt_bus][bus_idx, year_idx, hour_idx] for year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)))

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhCurtailed(), s; oper = oper)  
end

"""
    function add_obj_exp!(data, model, term::Term, s::Symbol; oper)

Adds expression s (already defined in model) to the objective expression model[:obj]. 
Adds the name, oper, and type of the term to data[:obj_vars].
"""
function add_obj_exp!(data, model, term::Term, s::Symbol; oper)
    new_term = sum(model[s])
    if oper == + 
        add_to_expression!(model[:obj], new_term)
    elseif oper == -
        add_to_expression!(model[:obj], -1, new_term)
    else
        Base.error("The entered operator isn't valid, oper must be + or -")
    end
    #Add s to array of variables included obj
    data[:obj_vars][s] = OrderedDict{Symbol, Any}(
        :term_sign => oper,
        :term_type => typeof(term)
    )
end

export add_obj_term!
export add_obj_exp!
export Term
export PerMWCap
export PerMWhGen
export PerMWhCurtailed