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
    return optimizer_with_attributes(
        HiGHS.Optimizer, # TODO: think through how we want to support custom solver types
        # Insert parameters here, as done below (the following is just a placeholder):
        "dual_feasibility_tolerance" => 1e-07,
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