@testset "Test Arbitrary Adjustments" begin
    @testset "Test Yearly and Hourly Adjustments" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = read_config(config_file)
        mods = config[:mods] #contains only the yearly adjustment to ch4_gwp
        data0 = read_data(config)

        mods[:adj_yearly] = AdjustYearly(file=joinpath(@__DIR__, "data", "3bus", "adjust_yearly.csv"), name=:adj_yearly) #overwrites previous adj_yearly
        mods[:adj_hourly] = AdjustHourly(file=joinpath(@__DIR__, "data", "3bus", "adjust_hourly.csv"), name=:adj_hourly)
        mods[:adj_by_age] = AdjustByAge(file=joinpath(@__DIR__, "data", "3bus", "adjust_by_age.csv"), name=:adj_by_age)
        data = read_data(config)
        nyr = get_num_years(data)
        @test data isa AbstractDict

        @testset "Test Yearly Adjustments" begin

            # Test that FOM is reduced in narnia for solar generators
            gen_idxs = get_table_row_idxs(data, :gen, ("nation"=>"narnia", "genfuel"=>"solar", "year_on"=>"y2030"))
            @test all(get_table_num(data, :gen, :fom, gen_idx, yr_idx, 1) ≈ get_table_num(data0, :gen, :fom, gen_idx, yr_idx, 1) - 0.2 for yr_idx in 1:nyr, gen_idx in gen_idxs)

            gen_idxs = get_table_row_idxs(data, :gen, ("nation"=>"narnia", "genfuel"=>"solar", "year_on"=>"y2035"))
            @test all(get_table_num(data, :gen, :fom, gen_idx, yr_idx, 1) ≈ get_table_num(data0, :gen, :fom, gen_idx, yr_idx, 1) - 0.3 for yr_idx in 1:nyr, gen_idx in gen_idxs)

            gen_idxs = get_table_row_idxs(data, :gen, ("nation"=>"narnia", "genfuel"=>"solar", "year_on"=>"y2040"))
            @test all(get_table_num(data, :gen, :fom, gen_idx, yr_idx, 1) ≈ get_table_num(data0, :gen, :fom, gen_idx, yr_idx, 1) - 0.4 for yr_idx in 1:nyr, gen_idx in gen_idxs)

            # Test that max branch power flow is greater in later years
            branch_idxs = get_table_row_idxs(data, :branch)
            @test all(branch_idx->(get_table_num(data, :branch, :pflow_max, branch_idx, 3, 1) ≈ get_table_num(data0, :branch, :pflow_max, branch_idx, 3, 1) * 2.653), branch_idxs)

            # Test that yearly value of damage rate of CO2 has been set.
            @test_throws Exception get_num(data0, :rdam_co2, 1, 1)
            @test get_num(data, :r_dam_co2, 1, 1) ≈ 183.56
        end
        @testset "Test Hourly Adjustments" begin

            # Test that wind af is different
            wind_idxs = get_table_row_idxs(data, :gen, "genfuel"=>"wind")
            @test all(wind_idx->(get_af(data, wind_idx, 1, 1) != get_af(data0, wind_idx, 1, 1)), wind_idxs)

            # Test that vom of narnian solar generators is higher in some hours after adjusting
            gen_idxs = get_table_row_idxs(data, :gen, "nation"=>"narnia", "genfuel"=>"solar")
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
        end
        @testset "Test Yearly and Hourly Adjustments" begin
            # Test that the yearly values for summer NOX damages values are increasing by year
            hr_idx_summer = get_hour_idxs(data, "season"=>"summer")
            @test all(hr_idx->all(yr_idx->(get_num(data, :r_dam_nox, yr_idx, hr_idx) < get_num(data, :r_dam_nox, yr_idx+1, hr_idx)) , 1:get_num_years(data)-1), hr_idx_summer)

            # Test that all values for winter NOX damages values are zero
            hr_idx_winter = get_hour_idxs(data, "season"=>"winter")
            @test all(hr_idx->(all(yr_idx->(get_num(data, :r_dam_nox, yr_idx, hr_idx) == 0.0), get_year_idxs(data, :))), hr_idx_winter)
        end

        @testset "Test adjusting by age" begin
            @testset "Test age triggers" begin
                model = setup_model(config, data) # so that capex_obj is added to gen
                gen = get_table(data, :gen)

                # Test age triggers
                coal_idxs = get_table_row_idxs(data, :gen, :genfuel=>"coal")
                coal_idx = first(coal_idxs)
                @test get_table_num(data, :gen, :routine_capex, coal_idx, "y2030", :) == 0.2
                @test get_table_num(data, :gen, :routine_capex, coal_idx, "y2035", :) == 0.2
                @test get_table_num(data, :gen, :routine_capex, coal_idx, "y2040", :) > 0.2

                wind_idxs = get_table_row_idxs(data, :gen, [:genfuel=>"wind", :build_status=>"built"])
                wind_idx = first(wind_idxs)
                @test get_table_num(data, :gen, :routine_capex, wind_idx, "y2030", :) == 0.8
                @test get_table_num(data, :gen, :routine_capex, wind_idx, "y2035", :) == 0.3
                @test get_table_num(data, :gen, :routine_capex, wind_idx, "y2040", :) == 0.3
            end

            @testset "Test exact age and after age" begin
                solar_idxs = get_table_row_idxs(data, :gen, [:genfuel=>"solar", :build_status=>"built"])
                solar_idx = first(solar_idxs)
                @test get_table_num(data, :gen, :af, solar_idx, "y2030", 1) ≈ 0.5 * (1-0.03)
                @test get_table_num(data, :gen, :af, solar_idx, "y2035", 1) ≈ 0.5 * (1-0.08)
                @test get_table_num(data, :gen, :af, solar_idx, "y2040", 1) ≈ 0.5 * (1-0.10)
            end
        end
    end
end