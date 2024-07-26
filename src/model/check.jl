"""
    check(config, data, model) -> ::Bool

Logs the termination status, and returns true if OPTIMAL, or if `config[:require_optimal]` is false and the status is LOCALLY_SOLVED.
"""
function check(config, data, model)
    ts = termination_status(model)
    if ts == JuMP.OPTIMAL
        return true
    elseif config[:require_optimal] == false && ts == JuMP.LOCALLY_SOLVED
        return true
    else
        return false
    end
end