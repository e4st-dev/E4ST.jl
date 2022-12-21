"""
    check(model) -> error if model didn't solve right

Should check the following:
* Optimal termination
* That no constraints artificially limited things they weren't supposed to like carbon capture and storage
"""
function check(model)
    ts = termination_status(model)
    @info "Optimized, termination status: $(ts)"
    return ts == JuMP.OPTIMAL
end