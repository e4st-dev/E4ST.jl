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
        start=0.0, #get_table_num(data, :gen, :pcap0, gen_idx, year_idx, :), # Setting to 0.0 for feasibility
        lower_bound = get_pcap_min(data, gen_idx, year_idx),
        upper_bound = get_pcap_max(data, gen_idx, year_idx),
    )

    # Power Generation
    @variable(model, 
        pgen_gen[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour], 
        start=0.0,
        lower_bound = 0.0,
        upper_bound = get_pcap_max(data, gen_idx, year_idx)+1, # +1 here to allow cons_pgen_max to always be binding
    )

    # Power Curtailed
    @variable(model, 
        plcurt_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
        start=0.0,
        lower_bound = 0.0,
        upper_bound = get_plnom(data, bus_idx, year_idx, hour_idx),
    )

    ## Expressions to be used later
    @info "Creating Expressions"
    
    # Power flowing through a given branch
    @expression(model, pflow_branch[branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour], get_pflow_branch(data, model, branch_idx, year_idx, hour_idx))

    # Power flowing out of a given bus
    @expression(model, pflow_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_pflow_bus(data, model, bus_idx, year_idx, hour_idx))

    # Power flowing in/out of buses, only necessary if modeling line losses from pflow.
    if config[:line_loss_type] == "pflow"

        # Make variables for positive and negative power flowing out of the bus.
        @variable(model, pflow_out_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], lower_bound = 0)
        @variable(model, pflow_in_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], lower_bound = 0)
    end

    # Served power of a given bus
    @expression(model, plserv_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_plnom(data, bus_idx, year_idx, hour_idx) - plcurt_bus[bus_idx, year_idx, hour_idx])

    # Generated power of a given bus
    @expression(model, pgen_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_pgen_bus(data, model, bus_idx, year_idx, hour_idx))

    # Generated energy at a given generator
    @expression(model, egen_gen[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour], get_egen_gen(data, model, gen_idx, year_idx, hour_idx))

    ## Constraints
    @info "Creating Constraints"
    
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

    # Constrain Transmission Lines, positive and negative
    @constraint(model,
        cons_branch_pflow_pos[
            branch_idx in 1:nbranch,
            year_idx in 1:nyear,
            hour_idx in 1:nhour;
            get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) > 0 # Only constrain for branches with nonzero pflow_max
        ], 
        pflow_branch[branch_idx, year_idx, hour_idx] <= get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)
    )

    @constraint(model, 
        cons_branch_pflow_neg[
            branch_idx in 1:nbranch, 
            year_idx in 1:nyear, 
            hour_idx in 1:nhour;
            get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) > 0 # Only constrain for branches with nonzero pflow_max
        ], 
        -pflow_branch[branch_idx, year_idx, hour_idx] <= get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)
    )

    add_build_constraints!(data, model, :gen, :pcap_gen)
    
    ## Objective Function 
    @info "Building Objective"
    @expression(model, obj, 0*model[:θ_bus][1,1,1]) 
    # needed to be defined as an GenericAffExp instead of an Int64 so multiplied by an arbitrary var


    # This keeps track of the expressions added to the obj and their signs
    data[:obj_vars] = OrderedDict{Symbol, Any}()

    # This is written as a cost minimization where costs are added to the obj
    
    # Power System Costs
    add_obj_term!(data, model, PerMWhGen(), :vom, oper = +)

    # Only add fuel cost if included and non-zero.
    if hasproperty(gen, :fuel_price) && anyany(!=(0), gen.fuel_price)
        add_obj_term!(data, model, PerMMBtu(), :fuel_price, oper = +)
    end

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
    isempty(branch_idxs) && return AffExpr(0.0)
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
    x = get_table_num(data, :branch, :x, branch_idx, year_idx, hour_idx)
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
        cf_min = get_table_num(data, :gen, :cf_min, gen_idx, year_idx, hour_idx)
        isnan(cf_min) && return 0.0
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
    af = get_table_num(data, :gen, :af, gen_idx, year_idx, hour_idx)
    pcap = model[:pcap_gen][gen_idx, year_idx]
    if hasproperty(data[:gen], :cf_max)
        cf_max = get_table_num(data, :gen, :cf_max, gen_idx, year_idx, hour_idx)
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
    egen_gen = model[:egen_gen]
    col = gen[!,s]
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    model[s] = @expression(model, 
        [gen_idx in axes(gen,1), yr_idx in 1:nyr],
        sum(col[gen_idx][yr_idx,hr_idx] * egen_gen[gen_idx, yr_idx, hr_idx] for hr_idx in 1:nhr)
    )

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhGen(), s; oper = oper)  
end

function add_obj_term!(data, model, ::PerMMBtu, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    egen_gen = model[:egen_gen]
    col = gen[!,s]
    hr = gen[!,:heat_rate]
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    model[s] = @expression(model, 
        [gen_idx in axes(gen,1), yr_idx in 1:nyr],
        sum(col[gen_idx][yr_idx,hr_idx] * hr[gen_idx][yr_idx, hr_idx] * egen_gen[gen_idx, yr_idx, hr_idx] for hr_idx in 1:nhr)
    )

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhGen(), s; oper = oper) 
end


function add_obj_term!(data, model, ::PerMWCap, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    years = get_years(data)
    hours_per_year = sum(get_hour_weights(data))

    model[s] = @expression(model, 
        [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_table_num(data, :gen, s, gen_idx, year_idx, :) .* 
        model[:pcap_gen][gen_idx, year_idx] *
        hours_per_year
    )

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
        sum(get_voll(data, bus_idx, year_idx, hour_idx) .* rep_hours.hours[hour_idx] .* model[:plcurt_bus][bus_idx, year_idx, hour_idx] for year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours)))

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhCurtailed(), s; oper = oper)  
end

"""
    function add_obj_exp!(data, model, term::Term, s::Symbol; oper)

Adds expression s (already defined in model) to the objective expression model[:obj]. 
Adds the name, oper, and type of the term to data[:obj_vars].
"""
function add_obj_exp!(data, model, term::Term, s::Symbol; oper)
    expr = model[s]
    if oper == + 
        for new_term in expr
            add_to_expression!(model[:obj], new_term)
        end
    elseif oper == -
        for new_term in expr
            add_to_expression!(model[:obj], -1, new_term)
        end
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