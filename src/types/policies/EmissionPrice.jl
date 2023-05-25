
@doc raw"""
    struct EmissionPrice <: Policy

Emission Price - A price on a certain emission for a given set of generators.

* `name`: name of the policy (Symbol)
* `emis_col`: name of the emission rate column in the gen table (ie. emis_co2) (Symbol)
* `prices`: OrderedDict of prices by year. Given as price per unit of emissions (ie. \$/short ton)
* `first_year_adj`: If the PTC is for the first year that a generator is on, it is sometimes adjusted to be the average PTC value over the expected lifetime of the generator. This is the adjustement factor between the original and first year value `first_year_ptc = original_ptc*first_year_adj`
* `years_after_ref_min`: Min (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to min gen age. 
* `years_after_ref_max`: Max (inclusive) number of years the sim year can be after gen reference year (ie. year_on, year_retrofit). If ref year is year_on then this would be equivaled to max gen age.
* `ref_year_col`: Column name to use as reference year for min and max above. Must be a year column. If this is :year_on, then the years_after_ref filters will filter gen age. If this is :year_retrofit, the the years_after_ref filters will filter by time since retrofit. 

* `gen_filters`: OrderedDict of generator filters
"""
Base.@kwdef struct EmissionPrice <: Policy
    name::Symbol
    emis_col::Symbol
    prices::OrderedDict
    first_year_adj::Float64 = 1.
    years_after_ref_min::Float64 = 0.
    years_after_ref_max::Float64 = 999.
    ref_year_col::String = "year_on"
    gen_filters::OrderedDict
end
export EmissionPrice


"""
    E4ST.modify_model!(pol::EmissionPrice, config, data, model)

Adds a column to the gen table containing the emission price as a per MWh value (gen emission rate * emission price). 
Adds this as a `PerMWhGen` price to the objective function using [`add_obj_term!`](@ref)
"""
function E4ST.modify_model!(pol::EmissionPrice, config, data, model)
    @info ("$(pol.name) modifying the model")

    gen = get_table(data, :gen)
    gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

    @info "Applying Emission Price $(pol.name) to $(length(gen_idxs)) generators"

    years = get_years(data)
    years_int = year2float.(years)

    #create column of Emission prices
    add_table_col!(data, :gen, pol.name, Container[ByNothing(0.0) for i in 1:nrow(gen)], DollarsPerMWhGenerated,
        "Emission price per MWh generated for $(pol.name)")
    
    #update column for gen_idx 
    price_yearly = [get(pol.prices, Symbol(year), 0.0) for year in years] #prices for the years in the sim
    for gen_idx in gen_idxs
        g = gen[gen_idx, :]

        # Get the years that qualify
        ref_year = year2float(g[pol.ref_year_col])
        year_min = ref_year + pol.years_after_ref_min
        year_max = ref_year + pol.years_after_ref_max
        g_qual_year_idxs = findall(y -> year_min <= y <= year_max, years_int)
        qual_price_yearly = ByYear([(i in g_qual_year_idxs) ? price_yearly[i] : 0.0  for i in 1:length(years)])
        gen[gen_idx, pol.name] = qual_price_yearly .* gen[gen_idx, pol.emis_col] #emission rate [st/MWh] * price [$/st] 
    end
    
    add_obj_term!(data, model, PerMWhGen(), pol.name, oper = +)
end

"""
    E4ST.modify_results!(pol::EmissionPrice, config, data) -> 

Adjust the value of EmissionPrice to be the full value if it was adjusted as a first year EmissionPrice (EmissionPrice averaged over lifetime of the gen)
"""
function E4ST.modify_results!(pol::EmissionPrice, config, data)

    # adjust value of emis price by the first_year_adj to get it back to actual value for welfare transfers
    if pol.first_year_adj != 1
        gen = get_table(data, :gen)
        for g in eachrow(gen)
            g[pol.name] = g[pol.name] ./ pol.first_year_adj
        end
    end
    
end