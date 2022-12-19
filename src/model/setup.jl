"""
    setup_model(config, data) -> model
"""
function setup_model(config, data)
    @info "# SETTING UP MODEL #############################################################################"
    optimizer_factory = getoptimizer(config)
    model = JuMP.Model(optimizer_factory)

    # set_silent(model)
    # set_optimizer_attribute(model, MOI.Silent(), true)

    # TODO: setup basics of model
    setup_dcopf!(config, data, model)

    for mod in getmods(config)
        apply!(mod, config, data, model)
    end

    @objective(model, Min, model[:obj])

    @info "Model Summary: $(summarize(model))"

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
        log_to_console = true,
        log_file = log_file_full,
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


