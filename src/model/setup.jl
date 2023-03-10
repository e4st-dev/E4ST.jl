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
| $P_{S_{b,y,h}}$ | `:pserv_bus` | MW | Hourly avg. power served to each bus |

# Expressions

Expressions are calculated as linear combinations of variables.  Can be accessed by `model[symbol]`

| Name | Symbol | Unit | Description |
| :--- | :--- | :--- | :--- |
| $P_{F_{l,y,h}}$ | `:pflow_branch` | MW | Hourly avg. power flowing through each branch |
| $P_{F_{b,y,h}}$ | `:pflow_bus` | MW | Hourly avg. power flowing out of each bus |
| $P_{U_{b,y,h}}$ | `:pcurt_bus` | MW | Hourly avg. power curtailed at each bus |
| $P_{G_{b,y,h}}$ | `:pgen_bus` | MW | Hourly avg. power generated at each bus |

# Constraints

| Name | Constraint | Symbol |  Unit | Description |
| :--- | :--- | :--- | :--- | :--- |
| $C_{PB_{b,y,h}}$ | $P_{G_{b,y,h}} - P_{S_{b,y,h}} = P_{F_{b,y,h}}$ | `:cons_pbal` | MW | Constrain the power flow at each bus |
| $C_{PG_{g,y,h}}^{\text{min}}$ | $P_{G_{g,y,h}} \geq P_{C_{b,y}}^{\text{min}}$ | `:cons_pgen_min` | MW | Constrain the generated power to be above minimum capacity factor, if given. |
| $C_{PG_{g,y,h}}^{\text{max}}$ | $P_{G_{g,y,h}} \leq P_{C_{b,y}}^{\text{max}}$ | `:cons_pgen_max` | MW | Constrain the generated power to be below min(availability factor, max capacity factor) |
| $C_{PS_{g,y,h}}^{\text{min}}$ | $P_{S_{b,y,h}} \geq 0$ | `:cons_pserv_min` | MW | Constrain the served power to be greater than zero |
| $C_{PS_{g,y,h}}^{\text{max}}$ | $P_{S_{b,y,h}} \leq P_{D_{b,y,h}}$ | `:cons_pserv_max` | MW | Constrain the served power to be less than or equal to demanded power. |
| $C_{PC_{g,y}}^{\text{min}}$ | $P_{C_{g,y}} \geq P_{C_{g,y}}^{\text{min}}$ | `:cons_pcap_min` | MW | Constrain the power generation capacity to be less than or equal to its minimum. |
| $C_{PC_{g}}^{\text{max}}$ | $P_{C_{g,y}} \leq P_{C_{g,y}}^{\text{max}}\quad \forall y = y_{S_g}$ | `:cons_pcap_max` | MW | Constrain the power generation capacity to be less than or equal to its minimum for its starting year. |
| $C_{PL_{l,y,h}}^{+}$ | $P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_pos` | MW | Constrain the branch power flow to be less than or equal to its maximum. |
| $C_{PL_{l,y,h}}^{-}$ | $-P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_neg` | MW | Constrain the negative branch power flow to be less than or equal to its maximum. |
| $C_{PCPB_{g,y}}$ | $P_{C_{g,y}} = 0 \quad \forall \left\{ y<y_{S_g} \right\}$ | `:cons_pcap_prebuild` | MW | Constraint the power generation capacity to be zero before the start year. |
| $C_{PCNA_{g,y}}$ | $P_{C_{g,y+1}} <= P_{C_{g,y}} \quad \forall \left\{ y >= y_{S_g} \right\}$ | `:cons_pcap_noadd` | MW | Constraint the power generation capacity to be non-increasing after the start year. Generation capacity is only added when building new generators in their start year.|

# Objective

The objective is a single expression that can be accessed via `model[:obj]`.  In general, we add things to the objective via 

"""
function setup_model(config, data)
    log_header("SETTING UP MODEL")

    if haskey(config, :model_presolve_file)
        @info "Loading model from:\n$(config[:model_presolve_file])"
        model = deserialize(config[:model_presolve_file])
    else
        model = JuMP.Model()

        # Comment this out for debugging so you can see variable names.  Saves quite a bit of RAM to leave out
        set_string_names_on_creation(model, false)

        setup_dcopf!(config, data, model)
    
        for (name, mod) in getmods(config)
            modify_model!(mod, config, data, model)
        end

        # Set the objective, scaling down for numerical stability.
        obj_scalar = get(config, :objective_scalar, 1e6)
        @objective(model, Min, model[:obj]/obj_scalar)

        constrain_pbal!(config, data, model)

        if get(config, :save_model_presolve, true)
            model_presolve_file = joinpath(config[:out_path],"model_presolve.jls")
            @info "Saving model to:\n$model_presolve_file"
            serialize(model_presolve_file, model)
            @info "Model Saved."
        end
    end

    add_optimizer!(config, data, model)

    @info "Model Summary:\n$(summarize(model))"
    return model
end

"""
    constrain_pbal!(config, data, model) -> nothing

Constrain the power balancing equation to equal zero for each bus, at each year and hour.

`pgen_bus - pserv_bus - pflow_bus == 0`

* `pgen_bus` is the power generated at the bus
* `pserv_bus` is the power served/consumed at the bus
* `pflow_bus` is the power flowing out of the bus
"""
function constrain_pbal!(config, data, model)
    nyear = get_num_years(data)
    nhour = get_num_hours(data)
    nbus = nrow(get_table(data, :bus))
    @constraint(model, 
        cons_pbal[bus_idx in 1:nbus, year_idx in 1:nyear, hour_idx in 1:nhour],
        model[:pgen_bus][bus_idx, year_idx, hour_idx] - model[:pserv_bus][bus_idx, year_idx, hour_idx] - model[:pflow_bus][bus_idx, year_idx, hour_idx] == 0.0
    )
    return nothing
end
export constrain_pbal!

function add_optimizer!(config, data, model)
    optimizer_factory = getoptimizer(config)
    set_optimizer(model, optimizer_factory; add_bridges=false)
end

"""
    summarize(model::Model) -> summary::String

Returns the string that would be output by show(model).
"""
function summarize(model::Model)
    buf = IOBuffer() 
    show(buf, model)
    summary = String(take!(buf))
    return summary
end

"""
    getoptimizer(config) -> optimizer_factory
"""
function getoptimizer(config)
    opt_type_str = config[:optimizer][:type]
    opt_type = getoptimizertype(opt_type_str)
    return optimizer_with_attributes(
        opt_type,
        optimizer_attributes_pairs(config)...
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
        log_file_full = abspath(config[:out_path], log_file)
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
    if LogFile === nothing
        log_file_full = ""
    elseif ispath(dirname(LogFile))
        log_file_full = LogFile
    else
        log_file_full = abspath(config[:out_path], LogFile)
    end
    # These defaults came from e4st_core.m
    (;
        LogFile         = log_file_full,
        LogToConsole    = false,
        NumericFocus    = 3,
        BarHomogeneous  = 1,
        method          = 2,
        # BarIterLimit    = 1000,   # 
        Crossover       = 0,      # 0 disables crossover
        # FeasibilityTol  = 1e-2,
        # OptimalityTol   = 1e-6,
        # BarConvTol      = 1e-6,
        Threads         = 1,
        # DualReductions  = 0,  # This is only to see if infeasible or unbounded.
        kwargs...
    )
end