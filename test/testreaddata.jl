@testset "Test Reading Data" begin
            

    # Test reading in the data to the model

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = read_config(config_file)

    @testset "Test Reading the Data" begin    
        data = read_data(config)
        @test get_table(data, :gen) isa DataFrame
        @test get_table(data, :build_gen) isa DataFrame
        @test get_table(data, :bus) isa DataFrame
        @test get_table(data, :branch) isa DataFrame
        @test get_table(data, :hours) isa DataFrame
        @test get_num_hours(data) isa Int
        @test get_hour_weights(data) isa Vector
        @test get_num_years(data) isa Int
    end


    @testset "Test read_af_table!" begin
        config = read_config(config_file)
        data = read_data(config)

        # generator 1 is a natural gas plant, defaults to 1.0

        # AF not specified for ng, should be default of 1.0
        @test all(get_af(data, 1, yr_idx, hr_idx) == 1.0 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))

        # Generator 2 is a solar generator in narnia, should be equal to 0.5 in hour 1, 0.6 in hours 2 and 3 for 2040, 0 in hour 4.
        @test get_af(data, 2, 3, 1) == 0.5
        @test get_af(data, 2, 3, 2) == 0.6
        @test get_af(data, 2, 3, 3) == 0.6
        @test get_af(data, 2, 3, 4) == 0.0
    end

    @testset "Test duplicate lines combination" begin
        config = read_config(config_file)
        config[:branch_file] = joinpath(@__DIR__, "data/3bus/branch_dup.csv")
        data = read_data(config)
        branch = get_table(data, :branch)
        @test nrow(branch) == 2
        @test all(x->x≈0.01, branch.x)
        @test all(x->x≈10, branch.pflow_max)
    end


    @testset "Test GenHashID mod" begin
        config = read_config(config_file, joinpath(@__DIR__, "config", "config_gen_hash.yml"))
        data = read_data(config)
        gen = get_table(data, :gen)
        @test "gen_hash" in names(gen)
        @test !(0. in gen.gen_hash) # all new builds given a hash
        @test length(unique(gen.gen_hash)) == nrow(gen) #all hashes are unique
    end
end