# Test loading in the data to the model

config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
config = load_config(config_file)

@testset "Test Loading the Data" begin    
    data = load_data(config)
    @test get_gen_table(data) isa DataFrame
    @test get_build_gen_table(data) isa DataFrame
    @test get_bus_table(data) isa DataFrame
    @test get_branch_table(data) isa DataFrame
    @test get_hours_table(data) isa DataFrame
    @test get_num_hours(data) isa Int
    @test get_hour_weights(data) isa Vector
    @test get_num_years(data) isa Int
end


@testset "Test load_af_table!" begin
    config = load_config(config_file)
    data = load_data(config)

    # generator 1 is a natural gas plant, defaults to 1.0

    # AF not specified for ng, should be default of 1.0
    @test all(get_af(data, 1, yr_idx, hr_idx) == 1.0 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))

    # AF not specified for solar in narnia in 2030 or 2035, should be default of 1.0
    @test get_af(data, 2, 1, 1) == 1.0
    @test get_af(data, 2, 1, 2) == 1.0
    @test get_af(data, 2, 1, 3) == 1.0
    @test get_af(data, 2, 1, 4) == 1.0
    @test get_af(data, 2, 2, 1) == 1.0
    @test get_af(data, 2, 2, 2) == 1.0
    @test get_af(data, 2, 2, 3) == 1.0
    @test get_af(data, 2, 2, 4) == 1.0

    # Generator 2 is a solar generator in narnia, should be equal to 0.5 in hours 1 and 4, 0.6 in hours 2 and 3 for 2040.
    @test get_af(data, 2, 3, 1) == 0.5
    @test get_af(data, 2, 3, 2) == 0.6
    @test get_af(data, 2, 3, 3) == 0.6
    @test get_af(data, 2, 3, 4) == 0.5
end


@testset "Test load_demand_table!" begin
    config = load_config(config_file)
    data = load_data(config)

    # generator 1 is a natural gas plant, defaults to 1.0

    # AF not specified for ng, should be default of 1.0
    @test all(get_pdem(data, 1, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
    @test all(get_pdem(data, 2, yr_idx, hr_idx) ≈ 1.6 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
    @test all(get_pdem(data, 3, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
end


