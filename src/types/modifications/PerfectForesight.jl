
"""
    struct PerfectForesight <: Modification

    Perfect Foresight(;name, rate)

Discounts future model years so that model runs with perfect foresight.
"""
Base.@kwdef struct PerfectForesight <: Modification
    name::Symbol
    rate::Float64
    function PerfectForesight(;
        name, 
        rate = 0.06    
    )
    if rate > 1
        error("Discount rate can not be greater than 1")
    end

    end
    return new(name, rate)
end
export PerfectForesight

E4ST.mod_rank(::Type{SimpleObjectiveDiscounting}) = 1000 # Make it go at the end

function E4ST.modify_model!(m::PerfectForesight, config, data, model)
    years = get_years(data)
    nyr =  lenght(years)
    y0 = years[1]
    discount_rates = (1 - m.rate) .^ (years .- y0)
    obj =  model[:obj]::Vector{AffExpr} #Should be length nyr
    
    for yr_idx in 1:nyr:
        obj_yr = obj[yr_idx]
        discount_rate = discount_rates[yr_idx]
        add_to_expression!(obj_yr, obj_yr, discount_rate -1)
    end
end