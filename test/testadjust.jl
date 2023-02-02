@testset "Test Arbitrary Adjustments" begin
    @testset "Test Yearly and Hourly Adjustments" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = load_config(config_file)
        data0 = load_data(config)
        config[:adjust_yearly_file] = joinpath(@__DIR__, "data","3bus","adjust_yearly.csv")
        config[:adjust_hourly_file] = joinpath(@__DIR__, "data","3bus","adjust_hourly.csv")
        data = load_data(config)
        @test data isa AbstractDict

        @testset "Test Yearly Adjustments" begin
            @test get_table(data, :adjust_yearly) isa DataFrame

            # Test that FOM is reduced in narnia for solar generators
            gen_idxs = get_table_row_idxs(data, :gen, "country"=>"narnia", "genfuel"=>"solar")
            @test all(gen_idx->(get_table_num(data, :gen, :fom, gen_idx, 3, 1) ≈ get_table_num(data0, :gen, :fom, gen_idx, 3, 1) - 0.4), gen_idxs)

            # Test that max branch power flow is greater in later years
            branch_idxs = get_table_row_idxs(data, :branch)
            @test all(branch_idx->(get_table_num(data, :branch, :pflow_max, branch_idx, 3, 1) ≈ get_table_num(data0, :branch, :pflow_max, branch_idx, 3, 1) * 2.653), branch_idxs)

            # Test that yearly value of damage rate of CO2 has been set.
            @test_throws Exception get_num(data0, :rdam_co2, 1, 1)
            @test get_num(data, :r_dam_co2, 1, 1) ≈ 183.56
        end
        @testset "Test Hourly Adjustments" begin
            @test get_table(data, :adjust_hourly) isa DataFrame


            # Test that wind af is different
            wind_idxs = get_table_row_idxs(data, :gen, "genfuel"=>"wind")
            @test all(wind_idx->(get_af(data, wind_idx, 1, 1) != get_af(data0, wind_idx, 1, 1)), wind_idxs)

            # Test that vom of narnian solar generators is higher in some hours after adjusting
            gen_idxs = get_table_row_idxs(data, :gen, "country"=>"narnia", "genfuel"=>"solar")
            @test all(gen_idx -> (get_table_num(data, :gen, :vom, gen_idx, 1, 4)>get_table_num(data0, :gen, :vom, gen_idx, 1, 4)), gen_idxs)

            # Test that vom of narnian solar generators is even higher in 2030
            yr_idx_2030 = get_year_idxs(data, "y2030")
            yr_idx_2040 = get_year_idxs(data, "y2040")
            @test all(gen_idx->(get_table_num(data, :gen, :vom, gen_idx, yr_idx_2030, 4) > get_table_num(data, :gen, :vom, gen_idx, yr_idx_2040, 4)), gen_idxs)
            

            # Test that emis_co2 of ng generators is higher in some hours after adjusting
            gen_idxs = get_table_row_idxs(data, :gen, "genfuel"=>"ng")
            @test all(gen_idx -> (get_table_num(data, :gen, :emis_co2, gen_idx, 1, 5)>get_table_num(data0, :gen, :emis_co2, gen_idx, 1, 5)), gen_idxs)

            # Test that vom of narnian solar generators is even higher in 2030
            @test all(gen_idx->(get_table_num(data, :gen, :emis_co2, gen_idx, yr_idx_2030, 5) > get_table_num(data, :gen, :emis_co2, gen_idx, yr_idx_2040, 5)), gen_idxs)

            # TODO: Test the yearly and hourly NOX damages
        end
    end
end