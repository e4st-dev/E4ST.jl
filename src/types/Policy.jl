"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.
"""
abstract type Policy <: Modification end


"""
    struct CES <: Policy

Clean Energy Standard - Load serving entity must purchase a certain amount of clean energy credits. The number of credits for a type of generation depends on it's emissions relative to a benchmark.
"""
#= struct CES <: Policy
    name::
    emiscol::Symbol 
    benchmark::Float64
    cap_file::AbstractString 

    function CES(;name,emiscol,benchmark,cap_file)
        #create a container of cap value and years 
        cap_table = load_table(joinpath(@__DIR__,cap_file))
            #for each year in the sim that is in the cap_table, add it to a vector and then call set_yearly
    end

end =#

"""
    struct PTC <: Policy
    
Production Tax Credit - A \$/MWh tax incentive for the generation of specific technology or under specific conditions.
"""
Base.@kwdef struct PTC <: Policy
    name::Symbol
    value::OrderedDict
    gen_age_min::Float64
    gen_age_max::Float64
    gen_filters::OrderedDict #Ethan adding a parse comparison that will work for ordered dicts 


    # TODO: how to put a doc string here, or just document this function
    # function PTC(value, start_year, end_year, gen_filters)
    #     gen_filters = collect(gen_filters) #turn dictionary of filters into array of pairs
    #     return new(Symbol(name), Float64(value), start_year, end_year, gen_filters)
    # end

end

function E4ST.modify_model!(pol::PTC, config, data, model)
    
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))
    years = get_years(data)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value for $(pol.name)")

    #update column for gen_idx 
    sim_values = [get(pol.value, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
        vals_tmp = [(i in g_qual_year_idxs) ? sim_values[i] : 0.0  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
    data[:gen] = gen
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end

#TODO: something about how to process this in results
#TODO: log statements


struct ITC <: Policy
    name::Symbol
    value::OrderedDict
    #start_year::AbstractString
    #end_year::AbstractString
    gen_age_min::Float64
    gen_age_max::Float64
    gen_filters::OrderedDict

    # function ITC(name, value, gen_age_min, gen_age_max, gen_filters)
    #     gen_filters = collect(gen_filters) #turn dictionary of filters into array of pairs

    #     #append!(gen_filters, [(:year_on=>(start_year,end_year))]) 
    #     return new(Symbol(name), value, gen_age_min, gen_age_max, gen_filters)
    # end
end

function E4ST.modify_model!(pol::ITC, config, data, model)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, pol.gen_filters)
    years = get_years(data)
   
    #create column of annualized ITC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWBuiltCapacity,
        "Investment tax credit value for $(pol.name)")

    #update column for gen_idx 
    #TODO: do we want the ITC value to apply to all years within econ life? Will get multiplied by capex_obj so will only be non zero for year_on but maybe for accounting? 
    sim_values = [get(pol.value, year, 0.0) for year in years] #values for the years in the sim

    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        g_qual_year_idxs = findall(age -> pol.gen_age_min <= age <= pol.gen_age_max, g.age.v)
        vals_tmp = [(i in g_qual_year_idxs) ? sim_values[i]* : 0.0  for i in 1:length(years)]
        g[pol.name] = ByYear(g[:capex_obj] .* vals_tmp)
    end
    
    add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)
end

#TODO: something about how to process this in results