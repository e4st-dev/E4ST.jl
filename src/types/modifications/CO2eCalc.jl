
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
    # set to the emis_co2 rate as a default
    emis_co2e = Container[Container(row[:emis_co2]) for row in eachrow(gen)]  

    # get necessary parameters from data
    ch4_gwp = get_val(data, :ch4_gwp) # ByYear container (or possibly vector) of methane global warming potential 
    ng_upstream_ch4_leakage = get_val(data, :ng_upstream_ch4_leakage)
    coal_upstream_ch4_leakage = get_val(data, :coal_upstream_ch4_leakage)
    bio_pctco2e = get_val(data, :bio_pctco2e)

    #iterate through gen and change co2e as needed
    genfuel = gen.genfuel
    gentype = gen.gentype
    emis_co2 = gen.emis_co2
    heat_rate = gen.heat_rate
    chp_co2_multi = gen.chp_co2_multi

    calc_co2e!(emis_co2e, genfuel, gentype, emis_co2, heat_rate, chp_co2_multi, ch4_gwp, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage, bio_pctco2e)
    add_table_col!(data, :gen, :emis_co2e, emis_co2e, ShortTonsPerMWhGenerated,
    "CO2e emission rate including adjustments for eor leakage, biomass and CHP adjustments, and methane.")

    add_upstream_methane!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage)
    
    # # add methane emissions for ng, coal, and DAC
    # ch4_gwp = get_val(data, :ch4_gwp) # ByYear container (or possibly vector) of methane global warming potential 

    # ng_upstream_ch4_leakage = get_val(data, :ng_upstream_ch4_leakage)
    # ng_rows = get_subtable(gen, :genfuel=>"ng") #when DAC is added it can be grouped into this for loop because it uses ng ch4 fuel content
    # #ng_rows.emis_co2e .= ByYear([ng_rows.emis_co2 + ng_upstream_ch4_leakage*ng_rows.hr*ch4_gwp[year_idx] for year_idx in 1:nyears])
    # for row in eachrow(ng_rows)
    #     co2e = row.emis_co2 + ng_upstream_ch4_leakage*row.hr*ch4_gwp
    #     row[:emis_co2e] = co2e
    # end

    # coal_upstream_ch4_leakage = get_val(data, :coal_upstream_ch4_leakage)
    # coal_rows = get_subtable(gen, :genfuel=>"coal")
    # #coal_rows.emis_co2e .= ByYear([coal_rows.emis_co2 + coal_upstream_ch4_leakage*ng_rows.hr*ch4_gwp[year_idx] for year_idx in 1:nyears])
    # for row in eachrow(coal_rows)
    #     co2e = row.emis_co2 + coal_upstream_ch4_leakage*ch4_gwp*row.hr
    #     row[:emis_co2e] = ByYear(co2e)
    # end

    # # update biomass CO2e with percentage that we want to reduce from upstream carbon sequestering from plants 
    # biomass_rows = get_subtable(gen, :genfuel=>"biomass")
    # bio_pctco2e = get_val(data, :bio_pctco2e)
    # #biomass_rows.emis_co2e .= bio_pctco2e.*biomass_rows.emis_co2
    # for row in eachrow(biomass_rows)
    #     co2e = row.emis_co2*bio_pctco2e
    #     row[:emis_co2e] = ByYear(co2e)
    # end

    # # update for CHP plants
    # chp_rows = get_subtable(gen, :gentype=>"chp")
    # chp_rows.emis_co2e .= chp_rows.emisco2e .* chp_rows.chp_co2_multi

    # eor leakage is already accounted for in the emis_co2 for CCS (and also planned to be for DAC)
    
end

function calc_co2e!(emis_co2e, genfuel, gentype, emis_co2, heat_rate, chp_co2_multi, ch4_gwp, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage, bio_pctco2e)
    for i in eachindex(emis_co2e)
        if genfuel[i] == "ng"
            emis_co2e[i] = Container(emis_co2[i] .+ ng_upstream_ch4_leakage .* heat_rate[i] .* ch4_gwp)
        elseif genfuel[i] == "coal"
            emis_co2e[i] = Container(emis_co2[i] .+ coal_upstream_ch4_leakage .* heat_rate[i] .* ch4_gwp)
        elseif genfuel[i] == "biomass"
            emis_co2e[i] = Container(bio_pctco2e .*  emis_co2[i])
        end

        if gentype[i] == "chp"
            emis_co2e[i] = Container(emis_co2e[i] .* chp_co2_multi[i])
        end
    end
    return nothing
end

"""
    add_upstream_methane!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage) -> 
"""
function add_upstream_methane!(data, ng_upstream_ch4_leakage, coal_upstream_ch4_leakage)
    gen = get_table(data, :gen)

    add_table_col!(data, :gen, :emis_upstream_ch4,  Container[ByNothing(0.0) for i in 1:nrow(gen)], ShortTonsPerMWhGenerated,
    "Upstream methane emission rate per MWh generated, primarily for coal and ng.")

    for row in eachrow(gen)
        row.genfuel == "ng" && (row.emis_upstream_ch4 = ByNothing(row.heat_rate * ng_upstream_ch4_leakage))
        row.genfuel == "coal" && (row.emis_upstream_ch4 = ByNothing(row.heat_rate * coal_upstream_ch4_leakage))
    end
    
end