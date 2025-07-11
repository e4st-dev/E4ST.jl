@testset "Test Parsing and Saving Results" begin
    # Tests parsing, processing, and saving of results
    config_file =  joinpath(@__DIR__, "config", "config_3bus.yml")

    @testset "Test reading/saving data from .jls file" begin
        config = read_config(config_file)
        config[:base_out_path] = "../out/3bus1"
        E4ST.make_out_path!(config)
        data1 = read_data(config)

        # Need to delete results_formulas for this test, because there are functions stored in there which will not exactly equivalent (though they should still function)
        delete!(data1, :results_formulas)

        # Check that it is trying to read in the data file
        config[:data_file] = get_out_path(config, "blah.jls")
        @test_throws Exception read_data(config)

        # Check that data file is read in and identical.  Also check that other files aren't touched
        config[:data_file] = get_out_path(config, "data.jls")
        config[:nominal_load_file] = "blah.csv"
        data2 = read_data(config)
        delete!(data2, :results_formulas)
        @test data1 == data2 || data1 === data2
    end

    @testset "Test welfare calculations" begin
        config = read_config(config_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)

        # Test that the objective values are the same as the accounting values, at least for this simplified example
        @test compute_result(data, :gen, :obj_pgen_cost_total_unscaled) ≈ compute_result(data, :gen, :variable_cost)
        @test compute_result(data, :gen, :obj_pcap_cost_total_unscaled) ≈ compute_result(data, :gen, :fixed_cost)
    end

    @testset "Test reading/saving model from .jls file" begin
        config = read_config(config_file)
        config[:base_out_path] = "../out/3bus1"
        config[:save_model_presolve] = true
        E4ST.make_paths_absolute!(config, config_file)
        E4ST.make_out_path!(config)
        data = read_data(config)
        model1 = setup_model(config, data)

        # Check that it is trying to read in the model file
        config[:model_presolve_file] = "bad/path/to/blah.jls"
        @test_throws Exception setup_model(config)

        # Check that data file is read in and identical.  Also check that other files aren't touched
        config[:model_presolve_file] = get_out_path(config, "model_presolve.jls")
        E4ST.make_paths_absolute!(config, config_file)
        model2 = setup_model(config, data)
        optimize!(model1)
        optimize!(model2)
        @test value.(model1[:θ_bus]) ≈ value.(model2[:θ_bus])
    end


    @testset "Test Aggregation" begin
        config = read_config(config_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)

        @testset "Test that we can compute all of the standard results" begin
            filter_results_formulas!(data)
            results_formulas = get_results_formulas(data)

            for (table_name, result_name) in keys(results_formulas)
                @test compute_result(data, table_name, result_name) isa Float64
            end

            # Test that NaN values turn to zero
            @test compute_result(data, :gen, :vom_per_mwh, :genfuel=>"not a real genfuel so that generation is zero") == 0.0
        end
        
        @testset "Test gen_idx filters" begin
            tot = compute_result(data, :gen, :egen_total)
            
            # Provide a function for filtering
            @test tot ≈ compute_result(data, :gen, :egen_total, :emis_co2 => <=(0.1)) + compute_result(data, :gen, :egen_total, :emis_co2 => >(0.1))

            # Provide a region for filtering
            @test tot ≈ compute_result(data, :gen, :egen_total, :bus_nation => "narnia") + compute_result(data, :gen, :egen_total, :bus_nation => !=("narnia"))

            # Provide a tuple for filtering
            @test tot ≈ compute_result(data, :gen, :egen_total, :vom => (0,1.1) ) + compute_result(data, :gen, :egen_total, :vom => (1.1,Inf))

            # Provide a set for filtering
            @test tot ≈ compute_result(data, :gen, :egen_total, :genfuel => in(["ng", "coal"]) ) + compute_result(data, :gen, :egen_total, :genfuel => !in(["ng", "coal"]))
            
            # Provide an index(es) for filtering
            @test tot ≈ compute_result(data, :gen, :egen_total, 1 ) + compute_result(data, :gen, :egen_total, 2:nrow(data[:gen]))

            @test aggregate_generation(data, :gentype, [:bus_nation=>"archenland"], "y2030", :season=>"summer") isa OrderedDict
        end

        @testset "Test year_idx filters" begin
            tot = compute_result(data, :gen, :egen_total)
            nyr = get_num_years(data)

            # Year index
            @test tot ≈ compute_result(data, :gen, :egen_total, :, 1) + compute_result(data, :gen, :egen_total, :, 2:nyr)

            # Year string
            @test tot ≈ compute_result(data, :gen, :egen_total, :, "y2030") + compute_result(data, :gen, :egen_total, :, ["y2035", "y2040"])
            
            # Range of years
            @test tot ≈ compute_result(data, :gen, :egen_total, :, ("y2020", "y2031")) + compute_result(data, :gen, :egen_total, :, ("y2032","y2045"))

            # Test function of years
            @test tot ≈ compute_result(data, :gen, :egen_total, :, <=("y2031")) + compute_result(data, :gen, :egen_total, :, >("y2031"))
        end

        @testset "Test hour_idx filters" begin
            tot = compute_result(data, :gen, :egen_total)
            nhr = get_num_hours(data)

            # Hour index
            @test tot ≈ compute_result(data, :gen, :egen_total, :, :, 1) + compute_result(data, :gen, :egen_total, :, :, 2:nhr)

            # Hour table label
            @test tot ≈ compute_result(data, :gen, :egen_total, :, :, (:time_of_day=>"morning", :season=>"summer")) + 
                compute_result(data, :gen, :egen_total, :, :, (:time_of_day=>"morning", :season=>!=("summer"))) +
                compute_result(data, :gen, :egen_total, :, :, :time_of_day=>!=("morning"))
                
        end

        @testset "Other Aggregation Tests" begin
            @test compute_welfare(data, :government) isa Float64
            @test compute_welfare(data, :producer) isa Float64
            @test compute_welfare(data, :user) isa Float64
            

            # Test that summing the co2 emissions for solar in 2030 is zero
            @test compute_result(data, :gen, :emis_co2_total, :gentype=>"solar", "y2030", :) ≈ 0.0
        
            # Test that the average co2 emissions rate is between the min and max
            all_emis_co2 = get_table_col(data, :gen, :emis_co2)
            emis_co2_min, emis_co2_max = extrema(all_emis_co2)
            @test emis_co2_min <= compute_result(data, :gen, :emis_co2_rate, :, "y2030", :) <= emis_co2_max
        
            # Test that the average capacity factor for solar generators is between 0 and af_avg, and that cf_hourly_max is < 1
            @test 0 <= compute_result(data, :gen, :cf_avg, :gentype=>"solar", :, :) <= compute_result(data, :gen, :af_avg, :gentype=>"solar", :, :)
            @test 0 <= compute_result(data, :gen, :cf_hourly_max, :, :, :) <= 1 + 1e-9
            @test 0 <= compute_result(data, :gen, :cf_hourly_min, :, :, :) <= 1 + 1e-9
        
            # Test that the average LMP times energy served equals the sum of LMP
            elec_cost = compute_result(data, :bus, :electricity_cost)
            elec_price = compute_result(data, :bus, :electricity_price)
            elec_quantity = compute_result(data, :bus, :elserv_total)
            @test elec_cost ≈ elec_price * elec_quantity
        
            # Test that there is no curtailment across all time
            elcurt = compute_result(data, :bus, :elcurt_total, :, :, :)
            @test elcurt < 1e-6
        
            # Test that total power capacity is greater than or equal to average load
            ecap = compute_result(data, :gen, :ecap_total)
            elnom = compute_result(data, :bus, :elnom_total)
            @test ecap >= elnom
                
            # Check on the MWh generated by each gen fuel.
            gen = get_table(data, :gen)
            genfuels = unique(gen.genfuel)
            egen_by_genfuel = map(genfuels) do gf
                compute_result(data, :gen, :egen_total, :genfuel=>gf)
            end
            egen_total = compute_result(data, :gen, :egen_total)
            @test sum(egen_by_genfuel) ≈ egen_total

            #test that CO2e formulas are working and are higher than CO2
            process_results!(config, data) #need to process so that mod is applied

            co2e_total = compute_result(data, :gen, :emis_co2e_total)
            co2_total = compute_result(data, :gen, :emis_co2_total)
            @test co2e_total > co2_total

            co2e_rate = compute_result(data, :gen, :emis_co2e_rate)
            co2_rate = compute_result(data, :gen, :emis_co2_rate)
            @test co2e_rate > co2_rate

            ch4_total = compute_result(data, :gen, :emis_upstream_ch4_total)
            @test ch4_total > 0
            ch4_rate = compute_result(data, :gen, :emis_upstream_ch4_rate)
            @test ch4_rate > 0


        end

    end

    @testset "Test Results Mods" begin
        # Setup
        config = read_config(config_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)

        @testset "Test ResultsTemplate" begin
            # Make new mod
            agg_file=joinpath(@__DIR__, "data/3bus/aggregate_template.csv")
            name = :agg_res
            mod = ResultsTemplate(;file=agg_file, name)

            mods = get_mods(config)
            empty!(mods)
            mods[name] = mod
            
            process_results!(config, data)
            @test isfile(get_out_path(config, "$name.csv"))
            results = get_results(data)
            @test haskey(results, name)
            table = get_result(data, name)
            @test table[end, :filter1] |> contains("=>")

            welfare_idx = findfirst(==(Symbol("")), table.table_name)
            @test table.value[welfare_idx] == compute_welfare(data, :user, :nation=>"narnia")

            @test sum(filter(row -> row.result_name == :egen_total && isempty(row.filter_years) == true && row.filter1 == "genfuel=>ng", table).value) ≈ 
            sum(filter(row -> row.result_name == :egen_total && isempty(row.filter_years) == false && row.filter1 == "genfuel=>ng", table).value)

        end

        @testset "Test YearlyTable" begin
            @testset "Test yearly bus table grouped by nation, season, and time of day" begin
                # Make new mod
                name = :bus_res_season_time_of_day
                mod = YearlyTable(;
                    name,
                    table_name = :bus,
                    groupby = "nation",
                    group_hours_by = [:season, :time_of_day]
                )

                mods = get_mods(config)
                empty!(mods)
                mods[name] = mod
                
                process_results!(config, data)
                results = get_results(data)

                table = get_table(data, mod.table_name)
                hours = get_table(data, :hours)
                len = length(groupby(table, mod.groupby)) * length(groupby(hours,mod.group_hours_by))

                for year in get_years(data)
                    table_name = Symbol("$(name)_$year")
                    @test isfile(get_out_path(config, "$table_name.csv"))
                    @test haskey(results, table_name)
                    df = results[table_name]
                    @test hasproperty(df, :nation)
                    @test hasproperty(df, :season)
                    @test hasproperty(df, :time_of_day)
                    @test nrow(df) == len
                end
            end
            @testset "Test yearly gen table" begin
                # Make new mod
                name = :bus_res_season_time_of_day
                mod = YearlyTable(;
                    name,
                    table_name = :gen,
                    groupby = ":"
                )

                mods = get_mods(config)
                empty!(mods)
                mods[name] = mod
                
                process_results!(config, data)
                results = get_results(data)

                table = get_table(data, mod.table_name)
                hours = get_table(data, :hours)
                len = length(groupby(table, mod.groupby)) * length(groupby(hours,mod.group_hours_by))

                for year in get_years(data)
                    table_name = Symbol("$(name)_$year")
                    @test isfile(get_out_path(config, "$table_name.csv"))
                    @test haskey(results, table_name)
                    df = results[table_name]
                    @test nrow(df) == len
                end
            end

        end
    end

    @testset "Test results processing from already-saved results" begin
        ### Run E4ST
        out_path = run_e4st(config_file, log_model_summary=true)

        # Now read the config from the out_path, with some results processing mods too.  Could also add the mods manually here.
        mod_file= joinpath(@__DIR__, "config/config_res.yml")
        config = read_config(out_path, mod_file)
        data = process_results!(config)

        # Test that the results contain the raw results and the agg_res from the added mod_file.
        res = get_results(data)
        @test haskey(res, :agg_res)
        @test haskey(res, :raw)

        ### Do the same test with just the out_path and the mod file
        data = process_results!(mod_file, out_path)

        # Test that the results contain the raw results and the agg_res from the added mod_file.
        res = get_results(data)
        @test haskey(res, :agg_res)
        @test haskey(res, :raw)
    end
end