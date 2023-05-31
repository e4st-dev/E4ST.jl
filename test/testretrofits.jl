@testset "Test Retrofits" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    config = read_config(config_file)
    mods = get_mods(config)
    mods[:coal_ccs_retro] = CoalCCSRetrofit()

    data = read_data(config)
    gen = get_table(data, :gen)
    years = get_years(data)
    
    # Test that data has 3 retrofits - one for each year
    @test length(get_table_row_idxs(data, :gen, :gentype=>"coal_ccus_retrofit")) == 3
    retrofits = data[:retrofits]

    for (gen_idx, ret_idxs) in retrofits
        for ret_idx in ret_idxs
            @test gen.emis_co2[ret_idx] < gen.emis_co2[gen_idx]
            @test gen.pcap_max[ret_idx] < gen.pcap_max[gen_idx]
            @test gen.heat_rate[ret_idx] > gen.heat_rate[gen_idx]
            @test gen.year_retrofit[ret_idx] in years
        end
    end

    model = setup_model(config, data)

    @test haskey(model, :cons_pcap_gen_retro_max)
    @test haskey(model, :cons_pcap_gen_retro_min)

end