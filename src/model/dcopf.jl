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
    hours_per_year = sum(get_hour_weights(data))
    gen = get_table(data, :gen)
    branch = get_table(data, :branch)
    nbus = nrow(bus)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nbranch = nrow(branch)
    ngen = nrow(gen)


    ## Variables
    @info "Creating Variables"

    θ_bound = config[:voltage_angle_bound] |> Float64

    # Voltage Angle
    @variable(model, 
        θ_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
        start=0.0,
        lower_bound = -θ_bound,
        upper_bound =  θ_bound
    )

    # Capacity
    @variable(model, 
        pcap_gen[gen_idx in 1:ngen, year_idx in 1:nyear], 
        start = get_table_num(data, :gen, :pcap0, gen_idx, year_idx, :),
        lower_bound = get_pcap_min(data, gen_idx, year_idx),
        upper_bound = get_pcap_max(data, gen_idx, year_idx),
    )

    # Power Generation
    @variable(model, 
        pgen_gen[gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour], 
        start = get_table_num(data, :gen, :pcap0, gen_idx, year_idx, :) * get_cf_max(config, data, gen_idx, year_idx, hour_idx),
        lower_bound = 0.0,
        upper_bound = get_pcap_max(data, gen_idx, year_idx) * 1.1, # 10% buffer here to allow cons_pgen_max to always be binding
    )

    # Power Curtailed
    @variable(model, 
        plcurt_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
        start=0.0,
        lower_bound = 0.0,
        upper_bound = get_plnom(data, bus_idx, year_idx, hour_idx),
    )

    # # Power flowing through a given branch = (θ_f - θ_t) / x
    # @variable(model, 
    #     pflow_branch[branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour], 
    #     start=0.0,
    #     lower_bound = -get_pflow_branch_max(data, branch_idx, year_idx, hour_idx),
    #     upper_bound = get_pflow_branch_max(data, branch_idx, year_idx, hour_idx),
    # )

    ## Expressions to be used later
    @info "Creating Expressions"

    f_bus_idxs = branch.f_bus_idx::Vector{Int64}
    t_bus_idxs = branch.t_bus_idx::Vector{Int64}
    @expression(
        model,
        pflow_branch[br in 1:nbranch, y in 1:nyear, h in 1:nhour],
        (θ_bus[f_bus_idxs[br], y, h] - θ_bus[t_bus_idxs[br], y, h]) / get_table_num(data, :branch, :x, br, y, h)
    )
    # @expression(model, 
    #     pflow_branch[branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour], 
    #     AffExpr(0.0)
    # )

    # f_bus_idxs = branch.f_bus_idx::Vector{Int64}
    # t_bus_idxs = branch.t_bus_idx::Vector{Int64}
    # for branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour
    #     x = get_table_num(data, :branch, :x, branch_idx, year_idx, hour_idx)
    #     b = 1/x
    #     f_bus_idx = f_bus_idxs[branch_idx]
    #     t_bus_idx = t_bus_idxs[branch_idx]
    #     add_to_expression!(pflow_branch[branch_idx, year_idx, hour_idx], θ_bus[f_bus_idx, year_idx, hour_idx], b)
    #     add_to_expression!(pflow_branch[branch_idx, year_idx, hour_idx], θ_bus[t_bus_idx, year_idx, hour_idx], -b)
    # end

    # Power flowing out of a given bus
    @expression(model, 
        pflow_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
        AffExpr(0.0)
    )

    # Loop through each branch and add to the corresponding bus expression.
    for branch_idx in 1:nbranch, year_idx in 1:nyear, hour_idx in 1:nhour
        f_bus_idx = f_bus_idxs[branch_idx]
        t_bus_idx = t_bus_idxs[branch_idx]
        add_to_expression!(
            pflow_bus[f_bus_idx, year_idx, hour_idx], 
            pflow_branch[branch_idx, year_idx, hour_idx],
        )
        add_to_expression!(
            pflow_bus[t_bus_idx, year_idx, hour_idx], 
            pflow_branch[branch_idx, year_idx, hour_idx],
            -1
        )
    end


    # Power flowing in/out of buses, only necessary if modeling line losses from pflow.
    if config[:line_loss_type] == "pflow"
        # Make variables for positive and negative power flowing out of the bus.
        @variable(model, pflow_out_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], lower_bound = 0)
        @variable(model, pflow_in_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], lower_bound = 0)
    end

    # Served power of a given bus
    @expression(model, plserv_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], get_plnom(data, bus_idx, year_idx, hour_idx) - plcurt_bus[bus_idx, year_idx, hour_idx])

    # Generated power of a given bus
    @expression(model, 
        pgen_bus[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
        AffExpr(0.0)
    )
    gen_bus_idxs = gen.bus_idx::Vector{Int64}
    for gen_idx in 1:ngen, year_idx in 1:nyear, hour_idx in 1:nhour
        bus_idx = gen_bus_idxs[gen_idx]
        add_to_expression!(pgen_bus[bus_idx, year_idx, hour_idx], pgen_gen[gen_idx, year_idx, hour_idx])
    end

    ## Constraints
    @info "Creating Constraints"
    
    # Constrain Power Generation
    if hasproperty(gen, :cf_min)
        cf_min = gen.cf_min
        @constraint(model, 
            cons_pgen_min[gen_idx in 1:ngen, yr_idx in 1:nyear, hr_idx in 1:nhour],
            pgen_gen[gen_idx, yr_idx, hr_idx] >= 
            cf_min[gen_idx][yr_idx, hr_idx] * pcap_gen[gen_idx, yr_idx]
        )
    end

    pgen_scalar = Float64(config[:pgen_scalar])

    @constraint(model, 
        cons_pgen_max[gen_idx in 1:ngen, yr_idx in 1:nyear, hr_idx in 1:nhour],
        pgen_scalar * pgen_gen[gen_idx, yr_idx, hr_idx] <= # Scale by pgen_scalar in this constraint to improve matrix coefficient range.  Some af values are very small.
        pgen_scalar * get_cf_max(config, data, gen_idx, yr_idx, hr_idx) * pcap_gen[gen_idx, yr_idx]
    )

    # Constrain Reference Bus
    for ref_bus_idx in get_ref_bus_idxs(data), yr_idx in 1:nyear, hr_idx in 1:nhour
        fix(θ_bus[ref_bus_idx, yr_idx, hr_idx], 0.0, force=true)
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
    @expression(model, obj, AffExpr(0.0)) 

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
    add_obj_term!(data, model, PerMWCap(), :routine_capex, oper = +)

    @expression(model,
        pcap_gen_inv_sim[gen_idx in axes(gen,1)],
        AffExpr(0.0)
    )

    for (gen_idx,g) in enumerate(eachrow(gen))
        g.build_status in ("unbuilt", "unretrofitted") || continue

        # Retrieve the investment year (either the retrofit year or the build year)
        year_retrofit = get(g, :year_retrofit, "")
        year_invest = isempty(year_retrofit) ? g.year_on : year_retrofit

        year_invest > last(years) && continue
        yr_idx_on = findfirst(>=(year_invest), years)
        add_to_expression!(pcap_gen_inv_sim[gen_idx], pcap_gen[gen_idx, yr_idx_on])
    end

    add_obj_term!(data, model, PerMWCapInv(), :capex_obj, oper = +) 
    add_obj_term!(data, model, PerMWCapInv(), :transmission_capex_obj, oper = +) 

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

### Contraint/Expression Info Functions
"""
    get_cf_max(data, gen_idx, year_idx, hour_idx)

Returns max capacity factor at a given time.  It is based on the lower of gen properties `af` (availability factor) and optional `cf_max` (capacity factor).  If it is below `config[:cf_threshold]`, it is rounded to zero.
""" 
function get_cf_max(config, data, gen_idx, year_idx, hour_idx)
    cf_threshold = config[:cf_threshold]::Float64
    af = get_table_num(data, :gen, :af, gen_idx, year_idx, hour_idx)
    gen = get_table(data, :gen)
    if hasproperty(gen, :cf_max)
        cf = get_table_num(data, :gen, :cf_max, gen_idx, year_idx, hour_idx)
    else 
        cf = 1.0
    end
    cf_max = min(af, cf)

    cf_max < cf_threshold && return 0.0

    return cf_max
end
export get_cf_max

"""
    add_obj_term!(data, model, ::Term, s::Symbol; oper)

Adds or subtracts cost/revenue `s` to the objective function of the `model` based on the operator `oper`. Adds the cost/revenue to the objective variables list in data. 
"""
function add_obj_term!(data, model, term::Term, s::Symbol; oper) end

function add_obj_term!(data, model, ::PerMWhGen, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"

    #write expression for the term
    pgen_gen = model[:pgen_gen]::Array{VariableRef, 3}
    gen = get_table(data, :gen)
    col = gen[!,s]
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    hour_weights = get_hour_weights(data)
    model[s] = @expression(model, 
        [gen_idx in axes(gen,1), yr_idx in 1:nyr],
        sum(col[gen_idx][yr_idx,hr_idx] * pgen_gen[gen_idx, yr_idx, hr_idx] * hour_weights[hr_idx] for hr_idx in 1:nhr)
    )

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWhGen(), s; oper = oper)  
end

function add_obj_term!(data, model, ::PerMMBtu, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    pgen_gen = model[:pgen_gen]::Array{VariableRef, 3}
    col = gen[!,s]
    hr = gen[!,:heat_rate]
    nhr = get_num_hours(data)
    nyr = get_num_years(data)
    hour_weights = get_hour_weights(data)
    model[s] = @expression(model, 
        [gen_idx in axes(gen,1), yr_idx in 1:nyr],
        sum(col[gen_idx][yr_idx,hr_idx] * hr[gen_idx][yr_idx, hr_idx] * pgen_gen[gen_idx, yr_idx, hr_idx] * hour_weights[hr_idx] for hr_idx in 1:nhr)
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
    pcap_gen = model[:pcap_gen]

    model[s] = @expression(model, 
        [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_table_num(data, :gen, s, gen_idx, year_idx, :) .* 
        pcap_gen[gen_idx, year_idx] *
        hours_per_year
    )

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWCap(), s; oper = oper) 
    
end

function add_obj_term!(data, model, ::PerMWCapInv, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    gen = get_table(data, :gen)
    years = get_years(data)
    hours_per_year = sum(get_hour_weights(data))
    pcap_gen_inv_sim = model[:pcap_gen_inv_sim]

    model[s] = @expression(model, 
        [gen_idx in 1:nrow(gen), year_idx in 1:length(years)],
        get_table_num(data, :gen, s, gen_idx, year_idx, :) .* 
        pcap_gen_inv_sim[gen_idx] *
        hours_per_year
    )

    # add or subtract the expression from the objective function
    add_obj_exp!(data, model, PerMWCapInv(), s; oper = oper) 
    
end


function add_obj_term!(data, model, ::PerMWhCurtailed, s::Symbol; oper) 
    #Check if s has already been added to obj
    Base.@assert s ∉ keys(data[:obj_vars]) "$s has already been added to the objective function"
    
    #write expression for the term
    bus = get_table(data, :bus)
    years = get_years(data)

    plcurt_bus = model[:plcurt_bus]::Array{VariableRef, 3}
    hour_weights = get_hour_weights(data)
    nhr = length(hour_weights)

    # Use this expression for single VOLL
    model[s] = @expression(model, 
        [bus_idx in 1:nrow(bus)],
        sum(
            get_voll(data, bus_idx, year_idx, hour_idx) * 
            hour_weights[hour_idx] * 
            plcurt_bus[bus_idx, year_idx, hour_idx] 
            for year_idx in 1:length(years), hour_idx in 1:nhr
        )
    )

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
    obj = model[:obj]::AffExpr
    if oper == + 
        for new_term in expr
            add_to_expression!(obj, new_term)
        end
    elseif oper == -
        for new_term in expr
            add_to_expression!(obj, -1, new_term)
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