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
        @test !("" in gen.gen_hash) # all new builds given a hash
        @test length(unique(gen.gen_hash)) == nrow(gen) #all hashes are unique

        # this is mostly to make sure that the parse doesn't error
        gen_hash_test = parse.(UInt64, gen.gen_hash, base = 16)
        @test typeof(gen_hash_test[1]) == UInt64
        
    end
    
    @testset "Test LeftJoinCols mod" begin
        # test with just the mod that applies in modify_setup_data
        config = read_config(config_file, joinpath(@__DIR__, "config", "config_joincol.yml"))
        delete!(config[:mods], :add_nation_mapping_raw)
        data = read_data(config)
        bus = get_table(data, :bus)
        @test "is_narnia" in names(bus)
        @test "is_archenland" in names(bus)
        @test sum(bus.is_narnia) == 1
        @test sum(bus.is_archenland) == 2

        # test with just the mod that applies in modify_raw_data
        config = read_config(config_file, joinpath(@__DIR__, "config", "config_joincol.yml"))
        delete!(config[:mods], :add_nation_mapping_setup)
        data = read_data(config)
        bus = get_table(data, :bus)

        @test "is_narnia" in names(bus)
        @test "is_archenland" in names(bus)
        @test sum(bus.is_narnia) == 1
        @test sum(bus.is_archenland) == 2

        @test "is_beaverdam" in names(bus)
        @test count(==(true), bus.is_beaverdam) == 1
        @test count(==(false), bus.is_beaverdam) == 2
    end

    @testset "Test Column Defaults" begin
        config_file = joinpath(@__DIR__, "config/config_3bus_extra_col.yml")
        config = read_config(config_file)
        
        # Test before specifying, that the column gets dropped
        if !hasmethod(E4ST.get_default_column_value, Tuple{Val{:annual_fish_displacement}})
            data = read_data(config)
            gen = get_table(data, :gen)
            @test !hasproperty(gen, :annual_fish_displacement)
            @test !hasproperty(gen, :capt_co2_percent)
            @test !hasproperty(gen, :extra_col)
        end

        # Insert a test that the gen table has the extra column.
        E4ST.get_default_column_value(::Val{:annual_fish_displacement}) = 0
        E4ST.get_default_column_value(::Val{:capt_co2_percent}) = 0
        E4ST.get_default_column_value(::Val{:extra_col}) = ""

        data = read_data(config)
        gen = get_table(data, :gen)

        # Test that everything is working properly with column `annual_fish_displacement`
        @test hasproperty(gen, :annual_fish_displacement)

        # Make sure that exactly one generator has annual_fish_displacement == 3
        @test count(==(3), gen.annual_fish_displacement) == 1

        # Make sure that all the rest of the generators have annual_fish_displacement == 0
        @test count(==(0), gen.annual_fish_displacement) == nrow(gen) - 1

        # Now test that the `extra_col`, introduced through `build_gen`, is added to the gen table
        @test hasproperty(gen, :extra_col) 
        @test count(==(""), gen.extra_col) > 0

    end


end