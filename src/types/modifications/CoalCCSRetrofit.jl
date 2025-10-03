
"""
    CoalCCSRetrofit(;kwargs...) <: Retrofit

`CoalCCSRetrofit` represents a [`Retrofit`](@ref) for changing coal-burning plants (gentype="coal"), to have carbon capture technology, and be changed to (gentype="coal_ccsus_retrofit")

Keyword Arguments:
* `crf = 0.115642438` - the capital recovery factor (default value assumes 12 year economic lifetime)
* `capt_co2_percent = 0.9` - (between 0 and 1) the percentage of CO₂ captured by the retrofit
* `reduce_nox_percent =  0.25` - (between 0 and 1) the percent reduction in NOₓ emissions (default is midpoint of 0% and 50% reduction)
* `reduce_so2_percent = 0.985` - (between 0 and 1) the percent reduction in SO₂ emissions (default is midpoint of 97% and 100% reduction)
* `reduce_pm25_percent = 0.33` - (between 0 and 1) the percent reduction in PM2.5 emissions (default is midpoint of -4% and 70% reduction)
* `econ_life = 12.0` - the assumed economic life of the retrofit.  Moves out the planned year_shutdown to be at the end of the retrofit economic lifetime if year_shutdown is earlier than the end of the econ life.

Other Requirements:
* The `gen` table must have a `heat_rate` column
* The `gen` table must either have a `pcap_plant_avg` column, or it will be assumed that each generator represents a single plant.  This value is used with the cost curves.

Cost adjustment values come from a regression in EPA Schedule 6 data.


Note: If simulation includes capacity adjustments (e.g. yearly retirements via Adjust mod) make sure the adjusment comes before Retrofits so that the penalty is applied to the adjusted capacity value.
"""
Base.@kwdef struct CoalCCSRetrofit <: Retrofit 
    crf::Float64 = 0.115642438 # 12 year economic lifetime
    capt_co2_percent::Float64 = 0.9
    reduce_nox_percent::Float64 = 0.25  # midpoint of 0% and 50% reduction
    reduce_so2_percent::Float64 = 0.985 # midpoint of 97% and 100% reduction
    reduce_pm25_percent::Float64 = 0.33 # midpoint of -4% and 70% reduction
    econ_life::Float64 = 12.0
end

export CoalCCSRetrofit

function mod_rank(::Type{CoalCCSRetrofit})
    mod_rank(CCUS) - 0.5
end

function init!(ret::CoalCCSRetrofit, config, data)
    gen = get_table(data, :gen)
    if !hasproperty(gen, :pcap_plant_avg)
        @warn "gen table does not have column pcap_plant_avg, representing the average nameplate plant capacity of a generator, in MW.  \nAssuming that the average plant capacity is the same as the max capacity."
        add_table_col!(data, :gen, :pcap_plant_avg, copy(gen.pcap_max), MWCapacity, "Average MW capacity of each plant in a representative generator.")
    elseif any(x -> x == -Inf, gen.pcap_plant_avg)
        @warn "gen table has some default pcap_plant_avg values (-inf), representing the average nameplate plant capacity of a generator, in MW.  \nFor these values, assuming that the average plant capacity is the same as the max capacity."
        gen.pcap_plant_avg = ifelse.(gen.pcap_plant_avg .== -Inf, gen.pcap_max, gen.pcap_plant_avg)  
    end
    return
end

function can_retrofit(ret::CoalCCSRetrofit, row)
    return row.gentype == "coal" 
end

function retrofit!(ret::CoalCCSRetrofit, newgen)
    hr = newgen[:heat_rate]

    pcap_avg = newgen[:pcap_plant_avg] # Could give lower/upper bounds

    # Calculate the heat rate penalty
    hr_pen = 0.89774 + -0.002513148 * pcap_avg + 0.0000012907 * pcap_avg.^2 + 0.05 * hr;
    if hr_pen < 0
        @warn "Heat rate penalty is less than zero for CoalCCSRetrofit with heat_rate = $hr, and pcap_plant_avg=$pcap_avg"
    end

    # Calculate the capacity penalty
    pcap_pen = 0.492333 + -0.00112000 * pcap_avg + 0.000000533333 * pcap_avg.^2 + 0.024333333333 * hr;
    if pcap_pen < 0
        @warn "Pcap penalty is less than zero for CoalCCSRetrofit with heat_rate = $hr, and pcap_plant_avg=$pcap_avg"
    end
    
    # Adjust the costs.  These costs come from a regression in EPA
    # Schedule 6 data. For more information, see the folder:
    # L:\Project-Gurobi\Workspace3\E4ST_InputDev\02_gen\03_NewGenerators\CCS\EPA

    newgen[:capex] += ret.crf * (274.41969538864595 + -0.7588175218134591 * pcap_avg + 0.0003898559487070511 * pcap_avg.^2 + 29.376250844468696 * hr;)
    newgen[:fom] += 5.319790777926144  + -0.012826250368711684 * pcap_avg + 6.761709569376475e-6 * pcap_avg.^2 + 0.33100000951514025 * hr;
    newgen[:vom] += 1.3763849270664505 + -0.005877951956471406 * pcap_avg + 3.037289187311878e-6 * pcap_avg.^2 + 0.40775063672146333 * hr;

    newgen[:heat_rate] *= (1+hr_pen)
    newgen[:emis_co2] *= (1 + hr_pen) # This will get multiplied by the capt_co2_percent in the CCUS mod
    newgen[:capt_co2_percent] = ret.capt_co2_percent

    haskey(newgen, :emis_nox)  && (newgen[:emis_nox]  *= ((1 - ret.reduce_nox_percent)  * (1 + hr_pen)))
    haskey(newgen, :emis_so2)  && (newgen[:emis_so2]  *= ((1 - ret.reduce_so2_percent)  * (1 + hr_pen)))
    haskey(newgen, :emis_pm25) && (newgen[:emis_pm25] *= ((1 - ret.reduce_pm25_percent) * (1 + hr_pen)))

    # works with a multi-year of single year pcap-max
    scale!(newgen[:pcap_max], 1-pcap_pen)
    
    newgen[:gentype] = "coal_ccus_retrofit"
    
    # adjust plant id column so that retrofits are distinct from non-retrofits
    if !hasproperty(newgen, :pcap_plant_avg)
        newgen[:plant_id] = string(newgen[:plant_id], " retrofit")
    end

    newgen[:econ_life] = ret.econ_life
    # if year_shutdown is within new econ_life, extend to the end of the new econ life
    ret_shutdown_year = year2float(newgen[:year_retrofit]) + ret.econ_life
    year2float(newgen[:year_shutdown]) < ret_shutdown_year && (newgen[:year_shutdown] = year2str(ret_shutdown_year))

    return newgen
end