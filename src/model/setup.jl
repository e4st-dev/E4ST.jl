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

# Variables
These are the decision variables to be optimized over.  Can be accessed by `model[symbol]`

| Name | Symbol |  Unit | Description |
| :--- | :--- | :--- | :--- |
| $\theta_{b,y,h}$ | `:θ_bus` | Radians | Hourly voltage angle of each bus |
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
| $C_{PF_{b,y,h}}$ | $P_{G_{b,y,h}} - P_{S_{b,y,h}} = P_{F_{b,y,h}}$ | `:cons_pflow` | MW | Constrain the power flow at each bus |
| $C_{\text{ref}_{b,y,h}}$ | $\theta_{b,y,h} = 0 \quad \forall b \in B_{\text{ref}}$ | `:cons_ref_bus` | MW | Constrain the voltage angle at the reference bus(es) to 0 |
| $C_{PG_{g,y,h}}^{\text{min}}$ | $P_{G_{g,y,h}} \geq P_{C_{b,y}}^{\text{min}}$ | `:cons_pgen_min` | MW | Constrain the generated power to be above minimum capacity factor, if given. |
| $C_{PG_{g,y,h}}^{\text{max}}$ | $P_{G_{g,y,h}} \leq P_{C_{b,y}}^{\text{max}}$ | `:cons_pgen_max` | MW | Constrain the generated power to be below min(availability factor, max capacity factor) |
| $C_{PS_{g,y,h}}^{\text{min}}$ | $P_{S_{b,y,h}} \geq 0$ | `:cons_pserv_min` | MW | Constrain the served power to be greater than zero |
| $C_{PS_{g,y,h}}^{\text{max}}$ | $P_{S_{b,y,h}} \leq P_{D_{b,y,h}}$ | `:cons_pserv_max` | MW | Constrain the served power to be less than or equal to demanded power. |
| $C_{PC_{g,y,h}}^{\text{min}}$ | $P_{C_{g,y}} \geq P_{C_{g,y}}^{\text{min}}$ | `:cons_pcap_min` | MW | Constrain the power generation capacity to be less than or equal to its minimum. |
| $C_{PC_{g,y,h}}^{\text{max}}$ | $P_{C_{g,y}} \leq P_{C_{g,y}}^{\text{max}}$ | `:cons_pcap_max` | MW | Constrain the power generation capacity to be less than or equal to its minimum. |
| $C_{PL_{l,y,h}}^{+}$ | $P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_pos` | MW | Constrain the branch power flow to be less than or equal to its maximum. |
| $C_{PL_{l,y,h}}^{-}$ | $-P_{F_{l,y,h}} \leq P_{L_{l,y,h}}^{\text{max}}$ | `:cons_branch_pflow_neg` | MW | Constrain the negative branch power flow to be less than or equal to its maximum. |

# Objective

The objective is a single expression that can be accessed via `model[:obj]`.  In general, we add things to the objective via 

"""
function setup_model(config, data)
    log_header("SETTING UP MODEL")

    if haskey(config, :model_presolve_file)
        @info "Loading model from $(config[:model_presolve_file])"
        model = deserialize(config[:model_presolve_file])
        @info "Model Summary: $(summarize(model))"
        return model
    end

    optimizer_factory = getoptimizer(config)
    model = JuMP.Model(optimizer_factory)

    setup_dcopf!(config, data, model)

    for (name, mod) in getmods(config)
        apply!(mod, config, data, model)
    end

    @objective(model, Min, model[:obj])

    @info "Model Summary: $(summarize(model))"

    if get(config, :save_model_presolve, true)
        serialize(joinpath(config[:out_path],"model_presolve.jls"), model)
    end

    return model
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
    if log_file == nothing
        log_file_full = abspath(config[:out_path], "HiGHS.log")
    elseif ispath(dirname(log_file))
        log_file_full = log_file
    else
        log_file_full = abspath(config[:out_path], log_file)
    end
    (;
        dual_feasibility_tolerance   = 1e-7, # Notional, not sure what this should be
        primal_feasibility_tolerance = 1e-7,
        log_to_console = false,
        # log_file = log_file_full,
        kwargs...
    )
end
function optimizer_attributes(config, ::Val{:Gurobi}; kwargs...)
    # These defaults came from e4st_core.m
    (;
        NumericFocus    = 0,
        BarHomogeneous  =-1,
        method          = 2,
        BarIterLimit    = 1000,
        Crossover       = 0,
        FeasibilityTol  = 1e-2,
        OptimalityTol   = 1e-6,
        BarConvTol      = 1e-6,
        kwargs...
    )
end