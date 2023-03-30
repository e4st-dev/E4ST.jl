@testset "Test CCUS" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    ccus_config_file = joinpath(@__DIR__, "config/config_ccus.yml")
    out_path, _ = run_e4st(config_file, ccus_config_file)

    data = load_processed_results(out_path)
    nyear = get_num_years(data)
    ccus_paths = get_table(data, :ccus_paths)
    
    for yr_idx in 1:nyear
        # Test that profit is greater than or equal to zero
        storer_profit = aggregate_result(total, data, :ccus_paths, :storer_profit, :, yr_idx)

        @test storer_profit >= 0

        # Test that some carbon was stored
        co2 = aggregate_result(total, data, :ccus_paths, :stored_co2, :, yr_idx)

        @test co2 > 0
    end
end