Base.@kwdef struct CoalCCSRetrofit <: Retrofit 
    crf::Float64 = 0.0533
    capt_co2_percent::Float64 = 0.9
    reduce_nox_percent::Float64 = 0.5
    reduce_so2_percent::Float64 = 1.0
    reduce_pm25_percent::Float64 = 0.35
end

export CoalCCSRetrofit

function init!(ret::CoalCCSRetrofit, config, data)
    gen = get_table(data, :gen)
    @assert hasproperty(gen, :pcap_avg) "gen table must have column pcap_avg, representing the average nameplate plant capacity of a generator, in MW."
    return
end

function can_retrofit(ret::CoalCCSRetrofit, row)
    return row.gentype == "coal" 
end

function get_retrofit(ret::CoalCCSRetrofit, row)
    newgen = Dict(pairs(row))
    hr = row.heat_rate
    pcap_avg = row.pcap_avg
    
    hr_pen = 0.89774 + -0.002513148 * pcap_avg + 0.0000012907 * pcap_avg.^2 + .0500000 * hr;
    if hr_pen < 0
        @warn "Heat rate penalty is less than zero for CoalCCSRetrofit with heat_rate = $hr, and pcap_avg=$pcap_avg"
    end

    newgen[:capex] += ret.crf * (273.7373632038955 + -0.7568324086472454 * pcap_avg + 0.00038860277248498125 * pcap_avg.^2 + 29.31333565393884 * hr)
    newgen[:fom] += 5.318474562694942 + -0.012794614702993803 * pcap_avg + 6.5587463644567325e-6 * pcap_avg.^2 +  0.3289526855121173 * hr;
    newgen[:vom] += 1.3717498041251759 + -0.00585575122952756 * pcap_avg + 3.0238817718412338e-6 * pcap_avg.^2 + 0.40662937961902723 * hr;
    newgen[:heat_rate] *= (1+hr_pen)
    newgen[:emis_co2] *= ((1 - ret.capt_co2_percent) * (1 + hr_pen))
    newgen[:emis_nox] *= ((1 - ret.reduce_so2_percent) * (1 + hr_pen))
    newgen[:emis_pm25] *= ((1 - ret.reduce_pm25_percent) * (1 + hr_pen))
    newgen[:pcap_max] /= (1 + hr_pen)
    newgen[:pcap0] = 0
    newgen[:gentype] = "coal_ccus_retrofit"

    return newgen
end