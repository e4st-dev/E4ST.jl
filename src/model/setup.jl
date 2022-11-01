"""
    setup_model(config, data) -> model
"""
function setup_model(config, data)
    optimizer_factory = getoptimizer(config)
    model = JuMP.Model(optimizer_factory)

    # TODO: setup basics of model
    setup_dcopf!(config, data, model)

    for mod in getmods(config)
        apply!(mod, config, data, model)
    end
    return model
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
function optimizer_attributes_pairs(args...; kwargs...)
    nt = optimizer_attributes(args...; kwargs...)
    return (string(i)=>nt[i] for i in eachindex(nt))
end

"""
    optimizer_attributes(config) -> attributes::NamedTuple

Returns the default optimizer attributes associated with `config`, as a named tuple.
"""
function optimizer_attributes(config::AbstractDict)
    optimizer_attributes(;config[:optimizer]...)
end
function optimizer_attributes(; type=nothing, kwargs...)
    optimizer_attributes(Val(Symbol(type)); kwargs...)
end


"""
    optimizer_attributes(::Val{T}; kwargs...) -> attributes::NamedTuple

Returns the optimizer attributes associated with `T`, with defaults overwritten by `kwargs`, as a named tuple.
"""
function optimizer_attributes(::Val{T}; kwargs...) where T
    @warn "No default optimizer attributes defined for type $T"
end
function optimizer_attributes(::Val{:HiGHS}; kwargs...)
    (;
        dual_feasibility_tolerance   = 1e-7, # Notional, not sure what this should be
        primal_feasibility_tolerance = 1e-7,
        kwargs...
    )
end
function optimizer_attributes(::Val{:Gurobi}; kwargs...)
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


"""
    setup_dcopf!(config, data, model)

Set up a DC OPF problem
"""
function setup_dcopf!(config, data, model)
    # TODO: setup DC OPF
    return model
end