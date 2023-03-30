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

        storer_revenue = aggregate_result(total, data, :ccus_paths, :storer_revenue, :, yr_idx)
        storer_revenue_check = sum((ccus_paths.price_total_clearing[i][yr_idx] - ccus_paths.price_trans[i]) * ccus_paths.stored_co2[i][yr_idx] for i in 1:nrow(ccus_paths))
        @test storer_revenue ≈ storer_revenue_check

        storer_cost = aggregate_result(total, data, :ccus_paths, :storer_cost, :, yr_idx)
        storer_cost_check = sum(ccus_paths.price_store[i] .* ccus_paths.stored_co2[i][yr_idx] for i in 1:nrow(ccus_paths))
        @test storer_cost ≈ storer_cost_check

        @test storer_profit ≈ storer_revenue - storer_cost

        @test all(ccus_paths.price_total_clearing[i][yr_idx] >= ccus_paths.price_total[i] for i in 1:nrow(ccus_paths) if ccus_paths.stored_co2[i][yr_idx]>0)

        # Test that some carbon was stored
        co2 = aggregate_result(total, data, :ccus_paths, :stored_co2, :, yr_idx)

        @test co2 > 0

        # We should be maxing out the 4th and 5th paths, and storing in the 6th but not maxing it out
        co2_by_path = [aggregate_result(total, data, :ccus_paths, :stored_co2, i, yr_idx) for i in 1:nrow(ccus_paths)]
        @test co2_by_path[4] ≈ ccus_paths.step_quantity[4]
        @test co2_by_path[5] ≈ ccus_paths.step_quantity[5]
        @test 0 < co2_by_path[6] < ccus_paths.step_quantity[6]
    end
end