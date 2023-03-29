"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.
"""
abstract type Policy <: Modification end


### Loading in Policies -----------------------------------

# TODO: Load in set of policies from a CSV


### Helper functions



"""
    set_gs_credits!(pol::Policy, config, data) -> 

Sets the generation standard credit level for each generator. 
Default is to give all generation that is filtered credit = 1.  
"""
function set_gs_credits!(pol::Policy, config, data) #TODO: should this be for GenerationStandards instead of Policy? Policy doesn't necessarily have these struct fields
    gen = get_table(data, :gen)

    #get qualifying gen idxs
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    v = zeros(Bool, nrow(gen))
    add_table_col!(data, :gen, pol.name, v, NA,
        "Credit level for generators that qualify under the $(cons.name) generation standard")
    gen[gen_idxs, cons.name] .= 1 
end



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
    #     cap_table = load_table(joinpath(@__DIR__,cap_file))
    #         #for each year in the sim that is in the cap_table, add it to a vector and then call set_yearly
    # end

end
