@doc raw"""
    setup_model(config, data) -> model

Sets up a JuMP Model for E4ST using `config` and `data`.

# Parameters
| Name | Symbol | Letter |
| :--- | :--- | :--- |
| $N_G$ | :num_gen | Number of generators |
| $N_B$ | :num_bus | Number of buses |
| $N_L$ | :num_branch | Number of branches |
| $G = \{1,2,...,N_G \}$ | N/A | Set of generator indices |
| $B = \{1,2,...,N_B \}$ | N/A | Set of bus indices |
| $L = \{1,2,...,N_L \}$ | N/A | Set of branch indices |
| $g \in G$ | :gen_idx | Generator index |
| $b \in B$ | :bus_idx | Bus index |
| $l \in L$ | :branch_idx | Branch index |
| $y \in Y$ | :year_idx | Year index |
| $y_{S_g} \in Y$ | :year_on_idx | Starting Year index for generator `g` |


# Variables
These are the decision variables to be optimized over.  Can be accessed by `model[symbol]`

| Name | Symbol |  Unit | Description |
| :--- | :--- | :--- | :--- |
| $\theta_{b,y,h}$ | `:θ_bus` | Radians | Hourly voltage angle of each bus. Reference buses fixed to 0.0 |
| $P_{G_{g,y,h}}$ | `:pgen_gen` | MW | Hourly avg. power generated by each generator |
| $P_{C_{g,y}}$ | `:pcap_gen` | MW | Annual power generation capacity of each generator |
| $P_{S_{b,y,h}}$ | `:plserv_bus` | MW | Hourly avg. power served to each bus |

# Expressions

Expressions are calculated as linear combinations of variables.  Can be accessed by `model[symbol]`

| Name | Symbol | Unit | Description |
| :--- | :--- | :--- | :--- |
| $P_{F_{l,y,h}}$ | `:pflow_branch` | MW | Hourly avg. power flowing through each branch |
| $P_{F_{b,y,h}}$ | `:pflow_bus` | MW | Hourly avg. net power flowing out of each bus |
| $P_{U_{b,y,h}}$ | `:plcurt_bus` | MW | Hourly avg. power curtailed at each bus |
| $P_{G_{b,y,h}}$ | `:pgen_bus` | MW | Hourly avg. power generated at each bus |

# Constraints

| Name | Constraint | Symbol |  Unit | Description |
| :--- | :--- | :--- | :--- | :--- |
| $C_{PB_{b,y,h}}$ | $P_{G_{b,y,h}} - P_{S_{b,y,h}} \geq P_{F_{b,y,h}}$ | `:cons_pbal_geq` | MW | Constrain the power flow at each bus |
| $C_{PB_{b,y,h}}$ | $P_{G_{b,y,h}} - P_{S_{b,y,h}} \leq P_{F_{b,y,h}}$ | `:cons_pbal_leq` | MW | Constrain the power flow at each bus |
| $C_{PG_{g,y,h}}^{\text{min}}$ | $P_{G_{g,y,h}} \geq P_{C_{b,y}}^{\text{min}}$ | `:cons_pgen_min` | MW | Constrain the generated power to be above minimum capacity factor, if given. |
| $C_{PG_{g,y,h}}^{\text{max}}$ | $P_{G_{g,y,h}} \leq P_{C_{b,y}}^{\text{max}}$ | `:cons_pgen_max` | MW | Constrain the generated power to be below min(availability factor, max capacity factor) |
| $C_{PS_{g,y,h}}^{\text{min}}$ | $P_{S_{b,y,h}} \geq 0$ | `:cons_plserv_min` | MW | Constrain the served power to be greater than zero |
| $C_{PS_{g,y,h}}^{\text{max}}$ | $P_{S_{b,y,h}} \leq P_{D_{b,y,h}}$ | `:cons_plserv_max` | MW | Constrain the served power to be less than or equal to load power. |
| $C_{PC_{g,y}}^{\text{min}}$ | $P_{C_{g,y}} \geq P_{C_{g,y}}^{\text{min}}$ | `:cons_pcap_min` | MW | Constrain the power generation capacity to be less than or equal to its minimum. |
| $C_{PC_{g}}^{\text{max}}$ | $P_{C_{g,y}} \leq P_{C_{g,y}}^{\text{max}}\quad \forall y = y_{S_g}$ | `:cons_pcap_max` | MW | Constrain the power generation capacity to be less than or equal to its minimum for its starting year. |
| $C_{PL_{l,y,h}}^{+}$ | $P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_pos` | MW | Constrain the branch power flow to be less than or equal to its maximum. |
| $C_{PL_{l,y,h}}^{-}$ | $-P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_neg` | MW | Constrain the negative branch power flow to be less than or equal to its maximum. |
| $C_{PCGPB_{g,y}}$ | $P_{C_{g,y}} = 0 \quad \forall \left\{ y<y_{S_g} \right\}$ | `:cons_pcap_gen_prebuild` | MW | Constrain the power generation capacity to be zero before the start year. |
| $C_{PCGNA_{g,y}}$ | $P_{C_{g,y+1}} <= P_{C_{g,y}} \quad \forall \left\{ y >= y_{S_g} \right\}$ | `:cons_pcap_gen_noadd` | MW | Constrain the power generation capacity to be non-increasing after the start year. Generation capacity is only added when building new generators in their start year.|
| $C_{PCGE_{g,y}}$ | $P_{C_{g,y}} == P_{C_{0_{g}}} \quad \forall \left\{ first y >= y_{S_g} \right\}$ | `:cons_pcap_gen_exog` | MW | Constrain unbuilt exogenous generators to be built to `pcap0` in the first year after `year_on`. |

# Objective

The objective is a single expression that can be accessed via `model[:obj]`.  In general, we add things to the objective via:
* [`add_obj_exp!`](@ref)
* [`add_obj_term!`](@ref)

"""
function setup_model(config, data)
    @info summarize(data)

    log_header("SETTING UP MODEL")

    if haskey(config, :model_presolve_file)
        @info "Loading model from:\n$(config[:model_presolve_file])"
        model = deserialize(config[:model_presolve_file])
    else

        #create capex_obj and tranmission_capex_obj
        create_capex_obj!(config, data)

        model = JuMP.Model()

        # Comment this out for debugging so you can see variable names.  Saves quite a bit of RAM to leave out
        set_string_names_on_creation(model, false)

        setup_dcopf!(config, data, model)
    
        for (name, mod) in get_mods(config)
            modify_model!(mod, config, data, model)
        end

        # Set the objective, scaling down for numerical stability.
        obj_scalar = config[:objective_scalar]
        @objective(model, Min, model[:obj]/obj_scalar)

        constrain_pbal!(config, data, model)

        if config[:save_model_presolve] === true
            model_presolve_file = get_out_path(config,"model_presolve.jls")
            @info "Saving model to:\n$model_presolve_file"
            serialize(model_presolve_file, model)
            @info "Model Saved."
        end
    end

    add_optimizer!(config, data, model)

    config[:log_model_summary] === true && @info summarize(model)

    return model
end

"""
    constrain_pbal!(config, data, model) -> nothing

Constrain the power balancing equation to equal zero for each bus, at each year and hour.

Depending on `config[:line_loss_type]`, the power balancing equation can be implemented in 2 ways:

* `pflow`:  `plgen_bus - plserv_bus + pflow_in_bus * (1 - line_loss_rate) - pflow_out_bus == 0`
* `plserv`:  `plgen_bus - plserv_bus / (1 - line_loss_rate) - pflow_bus == 0`

Where:
* `pgen_bus` is the power generated at the bus
* `plserv_bus` is the power served/consumed at the bus
* `pflow_bus` is the net power flowing out of the bus (positive or negative)
* `pflow_in_bus` is the (positive) power flowing into the bus
* `pflow_out_bus` is the (positive) power flowing out of the bus
"""
function constrain_pbal!(config, data, model)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nbus = nrow(get_table(data, :bus))
    line_loss_rate = config[:line_loss_rate]::Float64
    line_loss_type = config[:line_loss_type]::String
    if line_loss_type == "pflow"
        pflow_out_bus = model[:pflow_out_bus]
        pflow_in_bus = model[:pflow_in_bus]
        pflow_bus = model[:pflow_bus]
        pgen_bus = model[:pgen_bus]
        plserv_bus = model[:plserv_bus]

        # Constrain power flowing out of the bus.
        @constraint(model, cons_pflow_in_out[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour], 
            pflow_out_bus[bus_idx, year_idx, hour_idx] - pflow_in_bus[bus_idx, year_idx, hour_idx] == pflow_bus[bus_idx, year_idx, hour_idx]
        )
        @constraint(model, 
            cons_pbal_geq[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
            pgen_bus[bus_idx, year_idx, hour_idx] - plserv_bus[bus_idx, year_idx, hour_idx] - pflow_out_bus[bus_idx, year_idx, hour_idx] + (1-line_loss_rate) * pflow_in_bus[bus_idx, year_idx, hour_idx] >= 0.0
        )
        @constraint(model, 
            cons_pbal_leq[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
            pgen_bus[bus_idx, year_idx, hour_idx] - plserv_bus[bus_idx, year_idx, hour_idx] - pflow_out_bus[bus_idx, year_idx, hour_idx] + (1-line_loss_rate) * pflow_in_bus[bus_idx, year_idx, hour_idx] <= 0.0
        )
    elseif line_loss_type == "plserv"
        plserv_scalar = 1/(1-line_loss_rate)
        @constraint(model, 
            cons_pbal_geq[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
            model[:pgen_bus][bus_idx, year_idx, hour_idx] - model[:plserv_bus][bus_idx, year_idx, hour_idx] * plserv_scalar - model[:pflow_bus][bus_idx, year_idx, hour_idx] >= 0.0
        )
        @constraint(model, 
            cons_pbal_leq[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
            model[:pgen_bus][bus_idx, year_idx, hour_idx] - model[:plserv_bus][bus_idx, year_idx, hour_idx] * plserv_scalar - model[:pflow_bus][bus_idx, year_idx, hour_idx] <= 0.0
        )
    else
        error("config[:line_loss_type] must be `plserv` or `pflow`, but $line_loss_type was given")
    end
    return nothing
end
export constrain_pbal!

function add_optimizer!(config, data, model)
    optimizer_factory = getoptimizer(config)
    set_optimizer(model, optimizer_factory; add_bridges=false)
end

"""
    create_capex_obj!(config, data) -> 

Creates capex_obj and transmission_capex_obj columns which are the capex cost seen in the objective function. It is a ByYear column that is only non zero for year_on.
Set to capex for unbuilt generators in and after the year_on
Set to 0 for already built capacity because capacity expansion isn't considered for existing generators  
"""
function create_capex_obj!(config, data)
    gen = get_table(data, :gen)
    years = get_years(data)

    #warn if capex_obj already exists
    :capex_obj in propertynames(data[:gen]) && @warn "capex_obj hasn't been calculated yet but appears in the gen table. It will be overwritten."

    capex_obj = Container[ByNothing(0.0) for i in 1:nrow(gen)]
    transmission_capex_obj = Container[ByNothing(0.0) for i in 1:nrow(gen)]
    add_table_col!(data, :gen, :capex_obj, capex_obj, DollarsPerMWBuiltCapacityPerHour, "Hourly capital expenditures that is passed into the objective function. 0 for already built capacity")
    add_table_col!(data, :gen, :transmission_capex_obj, transmission_capex_obj, DollarsPerMWBuiltCapacityPerHour, "Hourly capital expenditures for transmission that is passed into the objective function. 0 for already built capacity")


    for g in eachrow(gen)
        # Do not change the capex_obj for anything that has been built, unless it is a retrofit
        g.build_status in ("unbuilt", "unretrofitted") || continue
        
        # Retrieve the investment year (either the retrofit year or the build year)
        year_retrofit = get(g, :year_retrofit, "")
        year_invest = isempty(year_retrofit) ? g.year_on : year_retrofit

        # Create a mask that is 1 for years during the econ life of the investment, and 0 before
        capex_filter = ByYear(map(year -> year >= year_invest && year < add_to_year(year_invest, g.econ_life), years))
        g.capex_obj = g.capex .* capex_filter
        g.transmission_capex_obj = g.transmission_capex .* capex_filter
    end
end
export create_capex_obj!

"""
    summarize(data) -> summary::String
"""
function summarize(data)
    buf = IOBuffer()
    df = DataFrame(:Table=>String[], :Rows=>Int64[])
    
    push!(df, ("gen", nrow(get_table(data, :gen))))
    push!(df, ("bus", nrow(get_table(data, :bus))))
    push!(df, ("branch", nrow(get_table(data, :branch))))
    push!(df, ("hours", nrow(get_table(data, :hours))))
    println(buf, "Data Summary:")

    println(buf, df)
    summary = String(take!(buf))
    return summary
end

# These utilities are for summarizing the model, which can be used for debugging numerical issues.
_get_jump_type(ar::AbstractArray) = Base.typename(eltype(ar)).name
_get_jump_type(x) = Base.typename(typeof(x)).name
_get_jump_length(x) = 1
_get_jump_length(x::AbstractArray) = length(x)::Int64
_get_jump_size(x::AbstractArray) = string(size(x))
_get_jump_size(x) = "irregular"
_get_jump_size(x::JuMP.Containers.SparseAxisArray) = "irregular"

"""
    summarize(model::Model) -> summary::String
"""
function summarize(model::Model)
    buf = IOBuffer()
    df = DataFrame(:variable=>Symbol[], :type=>Symbol[], :dimensions=>[], :length=>Int64[], 
        :rhs_min=>Float64[], 
        :rhs_max=>Float64[],
        :matrix_min=>Float64[],
        :matrix_max=>Float64[],
        :bounds_min=>Float64[],
        :bounds_max=>Float64[]
    )
    d = object_dictionary(model)
    for (key, obj) in d
        t = _get_jump_type(obj)
        s = _get_jump_size(obj)
        len = _get_jump_length(obj)

        len == 0 && continue

        rhs_min, rhs_max = get_rhs_range(obj)
        matrix_min, matrix_max = get_matrix_range(obj)
        bounds_min, bounds_max = get_bounds_range(obj)

        push!(df, (key, t, s, len, rhs_min, rhs_max, matrix_min, matrix_max, bounds_min, bounds_max))
    end
    println(buf, "Model Summary:")

    sort!(df, [:type, :variable])

    println(buf, df)
    summary = String(take!(buf))
    close(buf)
    return summary
end
export summarize

"""
    get_matrix_range(c) -> (min, max)

Returns min and max of non-zero absolute value of matrix range
"""
get_matrix_range(c::AbstractArray{<:ConstraintRef}) = (get_limit(minimum, c)::Float64, get_limit(maximum, c)::Float64)
get_matrix_range(c) = (NaN, NaN)

"""
    get_bounds_range(v) -> (min, max)

Returns min and max of non-zero absolute value of variable bounds range
"""
get_bounds_range(v::AbstractArray{<:VariableRef}) = (get_limit(minimum, v)::Float64, get_limit(maximum, v)::Float64)
get_bounds_range(v) = (NaN, NaN)

"""
    get_rhs_range(v) -> (min, max)

Returns min and max of non-zero absolute value of constraint right hand side range range
"""
get_rhs_range(c::AbstractArray{<:ConstraintRef}) = begin
    ll = Inf
    ul = 0.0
    for cons in c
        rhs = get_rhs(cons)
        rhs == 0.0 && continue
        a = abs(rhs)
        a > ul && (ul = a)
        a < ll && (ll = a)
    end
    ll == Inf && (ll = 0.0)
    (ll, ul)
end
get_rhs_range(c) = (NaN, NaN)

get_limit(f, obj::AbstractArray{<:VariableRef}) = try; f(abs(x) for x in get_limit.(f, obj) if x != 0); catch; 0.0; end;

get_limit(f, v::VariableRef) = begin
    hasub = has_upper_bound(v)
    haslb = has_lower_bound(v)
    hasub && haslb && return f(abs, ((lower_bound(v), upper_bound(v))))
    hasub && return abs(upper_bound(v))
    haslb && return abs(lower_bound(v))
    return 0.0
end

get_limit(f, obj::AbstractArray{<:ConstraintRef}) = f(abs(x) for x in get_limit.(f, obj))
get_limit(f, c::ConstraintRef) = try; f(abs(x) for x in get_terms(c) if x != 0); catch; 0.0; end;
function get_terms(c::ConstraintRef)
    co = constraint_object(c)
    f = co.func
    d = f.terms
    return values(d)
end
export get_terms

function get_rhs(c::ConstraintRef)
    co = constraint_object(c)
    rhs = _get_value(co.set)
end
_get_value(s::MOI.GreaterThan) = s.lower
_get_value(s::MOI.LessThan) = s.upper
_get_value(s::MOI.EqualTo) = s.value


"""
    getoptimizer(config) -> optimizer_factory
"""
function getoptimizer(config)
    opt_type_str = config[:optimizer][:type]
    opt_type = getoptimizertype(opt_type_str)
    p = optimizer_attributes_pairs(config)
    @info string("Using $opt_type_str Optimizer with attributes:\n", ("  $attribute: $value\n" for (attribute, value) in p)...)
    # @info s
    return optimizer_with_attributes(
        opt_type,
        p...
    )
end
function optimizer_attributes_pairs(config, args...; kwargs...)
    nt = optimizer_attributes(config, args...; kwargs...)
    return (string(i)=>nt[i] for i in eachindex(nt))
end

"""
    optimizer_attributes(config) -> attributes::NamedTuple

Returns the default optimizer attributes associated with `config`, as a named tuple.
"""
function optimizer_attributes(config::AbstractDict)
    optimizer_attributes(config; config[:optimizer]...)
end
function optimizer_attributes(config; type=nothing, kwargs...)
    optimizer_attributes(config, Val(Symbol(type)); kwargs...)
end


"""
    optimizer_attributes(config, ::Val{T}; kwargs...) -> attributes::NamedTuple

Returns the optimizer attributes associated with `T`, with defaults overwritten by `kwargs`, as a named tuple.
"""
function optimizer_attributes(config, ::Val{T}; kwargs...) where T
    @warn "No default optimizer attributes defined for type $T"
end
function optimizer_attributes(config, ::Val{:HiGHS}; log_file = nothing, kwargs...)
    if log_file === nothing
        log_file_full = ""
    elseif ispath(dirname(log_file))
        log_file_full = log_file
    else
        log_file_full = get_out_path(config, log_file)
    end
    (;
        dual_feasibility_tolerance   = 1e-7, # Notional, not sure what this should be
        primal_feasibility_tolerance = 1e-7,
        log_to_console = false,
        log_file = log_file_full,
        kwargs...
    )
end

function optimizer_attributes(config, ::Val{:Gurobi}; LogFile=nothing, kwargs...)
    # See the issue here for more info on how these defaults were chosen: https://github.com/e4st-dev/E4ST.jl/issues/72
    if LogFile === nothing
        log_file_full = ""
    elseif ispath(dirname(LogFile))
        log_file_full = LogFile
    else
        log_file_full = get_out_path(config, LogFile)
    end
    (;
        LogFile         = log_file_full,
        LogToConsole    = false,
        Method          = 2,
        Crossover       = 0,      # 0 disables crossover
        Threads         = 1,
        # NumericFocus    = 3, # NumericFocus can help with numerical instabilities if model failing to solve
        # BarHomogeneous  = 1, # BarHomogeneous can help with numerical instabilities if model failing to solve
        # BarIterLimit    = 1000,
        # FeasibilityTol  = 1e-2,
        # OptimalityTol   = 1e-6,
        # BarConvTol      = 1e-6,
        # DualReductions  = 0,  # This is only to see if infeasible or unbounded.
        kwargs...
    )
end

function run_optimize!(config, data, model)
    log_header("OPTIMIZING MODEL!")

    t_start = now()
    optimize!(model)
    t_finish = now()

    t_elapsed = Dates.canonicalize(Dates.CompoundPeriod(t_finish - t_start))
    ts = termination_status(model)

    log_header("Model Optimized in $t_elapsed with termination status $ts")
end