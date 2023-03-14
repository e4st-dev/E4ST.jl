"""
    check(model) -> ::Bool

Logs the termination status, and returns true if OPTIMAL.
"""
function check(model)
    ts = termination_status(model)
    @info "Optimized, termination status: $(ts)"
    return ts == JuMP.OPTIMAL
end