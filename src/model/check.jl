"""
    check(config, data, model) -> ::Bool

Logs the termination status, and returns true if OPTIMAL, or if `config[:require_optimal]` is false and the status is LOCALLY_SOLVED.
"""
function check(config, data, model)
    ts = termination_status(model)
    if ts == JuMP.OPTIMAL
        return true
    elseif ts == JuMP.LOCALLY_SOLVED && config[:require_optimal] == false
        return true
    elseif ts == JuMP.INFEASIBLE
        compute_conflict!(model) # This is where JuMP computes the solution

        # Compose a list of conflicting constraints
        conflicting_constraints = ConstraintRef[]
        for (F, S) in list_of_constraint_types(model)
            for con in all_constraints(model, F, S)
                if get_attribute(con, MOI.ConstraintConflictStatus()) == MOI.IN_CONFLICT
                    push!(conflicting_constraints, con)
                end
            end
        end

        io = IOBuffer()
        println(io, "Model is infeasible, here is a list of conflicting constraints:")
        for cons in conflicting_constraints
            print(io, name(cons))
            print(io, ": ")
            print(io, cons)
        end
        s = String(take!(io))
        @info s
        
        return false
    else
        return false
    end
end