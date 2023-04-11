@testset "Test Initializing Data" begin
    #Testing initializing data: loading in, setting up, modifying, adding new gens

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = read_config(config_file)

    data = read_data(config)
    import E4ST.Container
    Base.:(==)(c1::Container, c2::Container) = c1.v==c2.v

    @testset "Test Initializing the Data" begin
        config = read_config(config_file)
        data = read_data(config)
        table_names = get_table_names(data)
        for table_name in table_names
            @test has_table(data, table_name)
            table_name == :summary_table && continue
            @test summarize_table(table_name) isa DataFrame
            table = get_table(data, table_name)
            for col_name in names(table)
                @test get_table_col_unit(data, table_name, col_name) isa Type{<:E4ST.Unit}
                @test get_table_col_description(data, table_name, col_name) isa String
                @test get_table_val(data, table_name, col_name, 1) isa get_table_col_type(data, table_name, col_name)
            end
        end

    end

    @testset "Test Initializing the Data with a mod" begin
        struct DoubleVOM <: Modification end
        function E4ST.modify_raw_data!(::DoubleVOM, config, data)
            return
        end
        function E4ST.modify_setup_data!(::DoubleVOM, config, data)
            data[:gen][!, :vom] .*= 2
        end
        config = read_config(config_file)
        data_0 = read_data(config)
        push!(config[:mods], :testmod=>DoubleVOM())
        @test ~isempty(config[:mods])
        data = read_data(config)
        @test data != data_0
        @test sum(data[:gen].vom) == 2*sum(data_0[:gen].vom)

        #TODO: Create test Mod that applied in modify_raw_data!

    end

    #Test yearly and hourly adjustment to data
    include("testadjust.jl")


    @testset "Test load_demand_table! with shaping" begin
        config = load_config(config_file)
        #config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        delete!(config, :demand_match_file)
        delete!(config, :demand_add_file)
        data = load_data(config)
        archenland_buses = findall(==("archenland"), data[:bus].country)
        narnia_buses = findall(==("narnia"), data[:bus].country)
        all_buses = 1:nrow(data[:bus])


        # Check that narnian load power is different across years (look at the load_shape.csv)
        @testset "Test that bus $bus_idx load is different across years $yr_idx and $(yr_idx+1)" for bus_idx in narnia_buses, yr_idx in 1:get_num_years(data)-1
            @test ~all(get_pdem(data, 1, yr_idx, hr_idx) ≈ get_pdem(data, 1, yr_idx+1, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
        
        @testset "Test that bus $bus_idx load is the same across years $yr_idx and $(yr_idx+1)" for bus_idx in archenland_buses, yr_idx in 1:get_num_years(data)-1
            @test all(get_pdem(data, bus_idx, yr_idx, hr_idx) ≈ get_pdem(data, bus_idx, yr_idx+1, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
        
        # Check that each bus changes load across hours
        @testset "Test that bus $bus_idx load is different across hours" for bus_idx in all_buses, yr_idx in 1:get_num_years(data)
            @test any(get_pdem(data, bus_idx, yr_idx, 1) != get_pdem(data, bus_idx, yr_idx, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
    end

    @testset "Test load_demand_table! with shaping and matching" begin
        config = load_config(config_file)
        # config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        # config[:demand_match_file] = abspath(@__DIR__, "data", "3bus","demand_match.csv")
        delete!(config, :demand_add_file)
        data = load_data(config)
        archenland_buses = findall(==("archenland"), data[:bus].country)
        narnia_buses = findall(==("narnia"), data[:bus].country)
        all_buses = 1:nrow(data[:bus])

        # The last row, the all-area match is enabled for 2030 and 2035
        @test get_edem_demand(data, :, "y2030", :) ≈ 16000
        @test get_edem_demand(data, :, "y2035", :) ≈ 18000

        # In 2040, it should be equal to the naria (1.8) + the archenland match (18)
        @test get_edem_demand(data, :, "y2040", :) ≈ 19800

        # Test that ratio between load in naria and archenland stayed the same with scaling
        @testset for y in get_years(data)
            @test get_edem_load(data, :country=>"narnia", y, :)*10 ≈ get_edem_load(data, :country=>"archenland", y, :)
        end
    end

    @testset "Test load_demand_table! with shaping, matching and adding" begin
        config = load_config(config_file)
        # config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        # config[:demand_match_file] = abspath(@__DIR__, "data", "3bus","demand_match.csv")
        # config[:demand_add_file]   = abspath(@__DIR__, "data", "3bus","demand_add.csv")
        data = load_data(config)
        config = read_config(config_file)

        @test get_edem_demand(data, :, "y2030", :) ≈ 16000
        @test get_edem_demand(data, :, "y2035", :) ≈ 18000
        @test get_edem_demand(data, :, "y2040", :) ≈ 19800 + 0.00001*8760
    end

    @testset "Test Adding New Gens" begin
        config = read_config(config_file)
        data = read_data(config)
        gen = get_table(data, :gen)
        build_gen = get_table(data, :build_gen)

        @test "endog" in gen.build_type
        @test "unbuilt" in gen.build_status
        for gen_row in eachrow(gen)
            if gen_row.build_status == "unbuilt" && gen_row.build_type == "endog"
                @test gen_row.pcap0 == 0
            end
        end

        "new" in build_gen.build_status && @test "new" in gen.build_status

        #check that all gentypes in build_gen are in gen as well
        @test nothing ∉ indexin(unique(build_gen.gentype), unique(gen.gentype))

    end

    @testset "Test Setting Up Gen Table" begin 
        config = read_config(config_file)
        data = read_data(config)
        gen = get_table(data, :gen)

        @test hasproperty(gen, :capex_obj)
        @test hasproperty(gen, :age)
        @test typeof(gen.age) == Vector{Container}
        @test all(age->age isa E4ST.ByYear, gen.age)
        @test ~any(bs -> bs == "new", gen.build_status)

    end

end