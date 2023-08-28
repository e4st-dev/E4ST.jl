
Base.@kwdef struct CO2eCalc <: Modification 
    name::Symbol
end
export CO2eCalc

mod_rank(::Type{<:CO2eCalc}) = -1.0
"""
    modify_setup_data!(mod::CO2eCalc, config, data)

Calculated the CO2e value for each generator based on CO2 and methane emissions, including upstream leakage and sequestration. 
"""
function modify_setup_data!(mod::CO2eCalc, config, data)
    @info "$(mod.name) calculating co2e in setup data"

    gen = get_table(data, :gen)
    nyears = get_num_years(data)


    hasproperty(gen, :emis_co2e) && @warn "The CO2e values specified in the input gen table will be overwritten by the CO2eCalc mod."
    
    if !hasproperty(gen, :chp)
        @warn "The gen table has no column `chp`. Assuming all generators are not combined heat and power (setting gen[:,:chp] .= 0), and not adjusting CO2e calculation for CHP."
        gen[:, :chp] .= 0
    end
    
    # set to the emis_co2 rate as a default
    emis_co2e = Container[Container(row[:emis_co2]) for row in eachrow(gen)]  
    add_table_col!(data, :gen, :emis_co2e, emis_co2e, ShortTonsPerMWhGenerated,
    "CO2e emission rate including adjustments for eor leakage, biomass and CHP adjustments, and upstream methane.")

    # get necessary parameters from data
    ch4_gwp = get_val(data, :ch4_gwp) # ByYear container (or possibly vector) of methane global warming potential 
    ng_upstream_ch4_leakage = get_val(data, :ng_upstream_ch4_leakage)
    coal_upstream_ch4_leakage = get_val(data, :coal_upstream_ch4_leakage)
    bio_pctco2e = get_val(data, :bio_pctco2e)

    #iterate through gen and change co2e as needed
    calc_co2e!(gen, ch4_gwp, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage, bio_pctco2e)
    
    # add column for upstream ch4 rate
    add_upstream_methane_col!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage)
  
end

"""
    calc_co2e!(gen, ch4_gwp, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage, bio_pctco2e)

Calculate CO2e based on genfuel (ng, biomass, coal) and then adjusted for CHP plants. 
Includes upstream methane leakage for ng and coal in CO2e calculation. 
"""
function calc_co2e!(gen, ch4_gwp, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage, bio_pctco2e)
    for r in eachrow(gen)
        if r.genfuel == "ng"
            r.emis_co2e = Container(r.emis_co2 .+ ng_upstream_ch4_leakage .* r.heat_rate .* ch4_gwp)
        elseif r.genfuel == "coal"
            r.emis_co2e = Container(r.emis_co2 .+ coal_upstream_ch4_leakage .* r.heat_rate .* ch4_gwp)
        elseif r.genfuel == "biomass"
            r.emis_co2e = Container(r.emis_co2 .* bio_pctco2e)
        end

        if r.chp == 1
            r.emis_co2e = Container(r.emis_co2e .* r.chp_co2_multi)
        end
    end
    return nothing
end

"""
    add_upstream_methane_col!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage) -> 

Adding the emis_upstream_ch4 column to the gen table for ng and coal. 
"""
function add_upstream_methane_col!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage)
    gen = get_table(data, :gen)

    add_table_col!(data, :gen, :emis_upstream_ch4,  Container[ByNothing(0.0) for i in 1:nrow(gen)], ShortTonsPerMWhGenerated,
    "Upstream methane emission rate per MWh generated, primarily for coal and ng.")

    for row in eachrow(gen)
        row.genfuel == "ng" && (row.emis_upstream_ch4 = ByNothing(row.heat_rate * ng_upstream_ch4_leakage))
        row.genfuel == "coal" && (row.emis_upstream_ch4 = ByNothing(row.heat_rate * coal_upstream_ch4_leakage))
    end
end