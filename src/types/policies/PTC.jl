@doc raw"""
    struct PTC <: Policy
    
Production Tax Credit - A \$/MWh tax incentive for the generation of specific technology or under specific conditions.

# Keyword Arguments

* `name`: policy name 
* `values`: \$/MWh values of the PTC, stored as an OrderedDict with years and the value `(:y2020=>10)`, note `year` is a `Symbol`
* `first_year_adj`: If the PTC is for the first year that a generator is on, it is sometimes adjusted to be the average PTC value over the expected lifetime of the generator. This is the adjustement factor between the original and first year value `first_year_ptc = original_ptc*first_year_adj`
* `years_after_ref_min`: Min (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to min gen age. 
* `years_after_ref_max`: Max (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to max gen age.
* `ref_year_col`: Column name to use as reference year for min and max above. Must be a year column. If this is :year_on, then the years_after_ref filters will filter gen age. If this is :year_retrofit, the the years_after_ref filters will filter by time since retrofit. 

* `gen_filters`: filters for qualifying generators, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1)
"""
Base.@kwdef struct PTC <: Policy
    name::Symbol
    values::OrderedDict
    first_year_adj::Float64 = 1.
    years_after_ref_min::Float64 = 0.
    years_after_ref_max::Float64 = 999.
    ref_year_col::String = "year_on"
    gen_filters::OrderedDict
end
export PTC

"""
    E4ST.modify_setup_data!(pol::PTC, config, data)

Creates a column in the gen table with the PTC value in each simulation year for the qualifying generators.
"""
function E4ST.modify_setup_data!(pol::PTC, config, data)
    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying PTC $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)
    years_int = year2float.(years)

    #create column of PTC values
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Production tax credit value for $(pol.name)")

    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]
        ref_year = year2float(g[Symbol(pol.ref_year_col)])
        year_min = ref_year + pol.years_after_ref_min
        year_max = ref_year + pol.years_after_ref_max
        g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
        vals_tmp = [(i in g_qual_year_idxs) ? credit_yearly[i] : 0.0  for i in 1:length(years)]
        gen[gen_idx, pol.name] = ByYear(vals_tmp)
    end
end


"""
    function E4ST.modify_model!(pol::PTC, config, data, model)

Subtracts the PTC price * generation in that year from the objective function using [`add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::PTC, config, data, model)
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = -)
end


"""
    E4ST.modify_results!(pol::PTC, config, data) -> 

Adjust the value of PTC to be the full value if it was adjusted as a first year PTC (PTC averaged over lifetime of the gen)
"""
function E4ST.modify_results!(pol::PTC, config, data)

    # adjust value of PTC by the first_year_adj to get it back to actual value for welfare transfers
    if pol.first_year_adj != 1
        gen = get_table(data, :gen)
        for g in eachrow(gen)
            g[pol.name] = g[pol.name] ./ pol.first_year_adj
        end
    end
    
end
