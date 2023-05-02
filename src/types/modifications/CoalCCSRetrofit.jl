Base.@kwdef struct CoalCCSRetrofit <: Retrofit 
    crf::Float64 = 0.115642438 # 12 year economic lifetime
    capt_co2_percent::Float64 = 0.9
    reduce_nox_percent::Float64 = 0.5
    reduce_so2_percent::Float64 = 1.0
    reduce_pm25_percent::Float64 = 0.35
end

export CoalCCSRetrofit

function mod_rank(::Type{CoalCCSRetrofit})
    mod_rank(CCUS) - 1e-6
end

function init!(ret::CoalCCSRetrofit, config, data)
    gen = get_table(data, :gen)
    if !hasproperty(gen, :pcap_plant_avg)
        @warn "gen table does not have column pcap_plant_avg, representing the average nameplate plant capacity of a generator, in MW.  \nAssuming that the average plant capacity is the same as the max capacity."
        add_table_col!(data, :gen, :pcap_plant_avg, copy(gen.pcap_max), MWCapacity, "Average MW capacity of each plant in a representative generator.")
    end
    return
end

function can_retrofit(ret::CoalCCSRetrofit, row)
    return row.gentype == "coal" 
end

function get_retrofit(ret::CoalCCSRetrofit, row)
    newgen = Dict(pairs(row))
    hr = row.heat_rate

    pcap_avg = row.pcap_plant_avg # Could give lower/upper bounds
    
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
    newgen[:fom] += 5.319790777926144 + -0.012826250368711684 * pcap_avg + 6.761709569376475e-6 * pcap_avg.^2 +  0.33100000951514025 * hr;
    newgen[:vom] += 1.3763849270664505 + -0.005877951956471406 * pcap_avg + 3.037289187311878e-6 * pcap_avg.^2 + 0.40775063672146333 * hr;

    newgen[:heat_rate] *= (1+hr_pen)
    newgen[:emis_co2] *= ((1 - ret.capt_co2_percent) * (1 + hr_pen))

    haskey(newgen, :emis_nox) && (newgen[:emis_nox] *= ((1 - ret.reduce_nox_percent) * (1 + hr_pen)))
    haskey(newgen, :emis_so2) && (newgen[:emis_so2] *= ((1 - ret.reduce_so2_percent) * (1 + hr_pen)))
    haskey(newgen, :emis_pm25) && (newgen[:emis_pm25] *= ((1 - ret.reduce_pm25_percent) * (1 + hr_pen)))
    newgen[:pcap_max] *= (1 - pcap_pen)
    newgen[:pcap0] = 0

    newgen[:gentype] = "coal_ccus_retrofit"

    return newgen
end