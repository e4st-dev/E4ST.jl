@testset "Test Arbitrary Adjustments" begin
    @testset "Test Yearly Adjustments" begin
        # TODO: prepare a Yearly adjustment file that does the things 

    end

    @testset "Test Hourly Adjustments" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = load_config(config_file)
        data0 = load_data(config)
        config[:adjust_hourly_file] = joinpath(@__DIR__, "data","3bus","adjust_hourly.csv")
        data = load_data(config)
        @test data isa AbstractDict
        @test get_table(data, :adjust_hourly) isa DataFrame
        
        # Test that wind af is different
        wind_idxs = get_table_row_idxs(data, :gen, "genfuel"=>"wind")
        @test all(wind_idx->(get_af(data, wind_idx, 1, 1) != get_af(data0, wind_idx, 1, 1)), wind_idxs)

    end

    @testset "Test Yearly and Hourly Adjustments" begin

    end
end