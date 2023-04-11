"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.
"""
abstract type Policy <: Modification end


### Loading in Policies -----------------------------------

# TODO: Load in set of policies from a CSV


### Basic Policy Types ------------------------------------
#TODO: These are actually going to be in separate file by basic policy type
"""
    struct CES <: Policy

Clean Energy Standard - Load serving entity must purchase a certain amount of clean energy credits. The number of credits for a type of generation depends on it's emissions relative to a benchmark.
"""
struct CES <: Policy
    name::Symbol
    value::OrderedDict #
    benchmark::Float64

    # function CES(;name,emiscol,benchmark,cap_file)
    #     #create a container of cap value and years 
    #     cap_table = read_table(joinpath(@__DIR__,cap_file))
    #         #for each year in the sim that is in the cap_table, add it to a vector and then call set_yearly
    # end

end
