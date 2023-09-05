@testset "Test Retrofits" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    config_ccus_file = joinpath(@__DIR__, "config/config_ccus.yml")
    config = read_config(config_file, config_ccus_file)
    mods = get_mods(config)
    mods[:coal_ccs_retro] = CoalCCSRetrofit()
    E4ST.sort_mods_by_rank!(config)

    data = read_data(config)
    gen = get_table(data, :gen)
    years = get_years(data)
    nyr = get_num_years(data)

    model = setup_model(config, data)
    
    # Test that data has 6 retrofits - one for each year x 1 for each CCUS type
    @test length(get_table_row_idxs(data, :gen, :gentype=>"coal_ccus_retrofit")) == 6
    retrofits = data[:retrofits]

    for (gen_idx, ret_idxs) in retrofits
        for ret_idx in ret_idxs
            @test gen.capt_co2_percent[ret_idx] > gen.capt_co2_percent[gen_idx]
            @test gen.pcap_max[ret_idx] < gen.pcap_max[gen_idx]
            @test gen.heat_rate[ret_idx] > gen.heat_rate[gen_idx]
            @test gen.year_retrofit[ret_idx] in years
        end
    end

    @test haskey(model, :cons_pcap_gen_retro_max)
    @test haskey(model, :cons_pcap_gen_retro_min)

    optimize!(model)
    parse_results!(config, data, model)
    process_results!(config, data)


    @testset "Test Retrofit Capex" begin
        for (year_idx, year) in enumerate(years)
            gen_idxs = get_table_row_idxs(data, :gen, :gentype=>"coal_ccus_retrofit", :year_retrofit=>year)
            for gen_idx in gen_idxs
                # Check that capex_obj is > 0 for years >= year_retrofit
                for y in 1:nyr
                    if y < year_idx
                        @test get_table_num(data, :gen, :capex_obj, gen_idx, y, :) == 0
                    else
                        @test get_table_num(data, :gen, :capex_obj, gen_idx, y, :) > 0
                    end
                end
            end
        end
    end
end