
"""
    struct PerfectForesight <: Modification

    PerfectForesight(;name, rate)

Calculates discount value for future model years so that model runs with perfect foresight.

## Keyword Arguments
* `name` - the name of the mod, do not need to specify in a config file
* `rate' - the discount rate that will be used to calculate the yearly weights, defaults to 0.06.
"""
struct PerfectForesight <: Modification
    name::Symbol
    rate::Float64
    function PerfectForesight(;
        name, 
        rate = 0.06    
    )
        if rate > 1
            error("Discount rate can not be greater than 1")
        elseif rate < 0
            error("Discount rate can not be negative")
        end
        new(name, rate)
    end 
end
PerfectForesight(name::Symbol, rate::Float64) = PerfectForesight(; name=name, rate=rate)
PerfectForesight(name::Symbol) = PerfectForesight(; name=name)
export PerfectForesight

E4ST.mod_rank(::Type{PerfectForesight}) = -2 

function E4ST.modify_raw_data!(m::PerfectForesight, config, data)
    nyrs = get_num_years(data)
    years = [parse(Int, replace(y, "y" => "")) for y in get_years(data)]
    y0 = years[1]
    discount_rates = (1 - m.rate) .^ (years .- y0)
    config[:yearly_objective_scalars] = discount_rates
    @assert length(config[:yearly_objective_scalars]) == nyrs "Length of perfect foresight discount vector does not match the number of years"
end