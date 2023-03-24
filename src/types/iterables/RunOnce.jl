"""
    struct RunOnce <: Iterable end

This is the most basic Iterable.  It only allows E4ST to run a single time.
"""
struct RunOnce <: Iterable end
export RunOnce

function should_iterate(::RunOnce, args...)
    return false
end