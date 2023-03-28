# Tests parsing, processing, and saving of results 


@testset "Test loading/saving data from .jls file" begin
    config = load_config(config_file)
    config[:base_out_path] = "../out/3bus1"
    E4ST.make_out_path!(config)
    data1 = load_data(config)

    # Check that it is trying to load in the data file
    config[:data_file] = get_out_path(config, "blah.jls")
    @test_throws Exception load_data(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:data_file] = get_out_path(config, "data.jls")
    config[:demand_file] = "blah.csv"
    data2 = load_data(config)
    @test data1 == data2
end

@testset "Test loading/saving model from .jls file" begin
    config = load_config(config_file)
    config[:base_out_path] = "../out/3bus1"
    config[:save_model_presolve] = true
    E4ST.make_paths_absolute!(config, config_file)
    E4ST.make_out_path!(config)
    data = load_data(config)
    model1 = setup_model(config, data)

    # Check that it is trying to load in the model file
    config[:model_presolve_file] = "bad/path/to/blah.jls"
    @test_throws Exception setup_model(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:model_presolve_file] = get_out_path(config, "model_presolve.jls")
    E4ST.make_paths_absolute!(config, config_file)
    model2 = setup_model(config, data)
    optimize!(model1)
    optimize!(model2)
    @test value.(model1[:θ_bus]) ≈ value.(model2[:θ_bus])
end


@testset "Test Aggregation" begin
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    parse_results!(config, data, model)
    
    @testset "Test gen_idx filters" begin
        tot = aggregate_result(total, data, :gen, :egen)
        
        # Provide a function for filtering
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :emis_co2 => <=(0.1)) + aggregate_result(total, data, :gen, :egen, :emis_co2 => >(0.1))

        # Provide a region for filtering
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :country => "narnia") + aggregate_result(total, data, :gen, :egen, :country => !=("narnia"))

        # Provide a tuple for filtering
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :vom => (0,1.1) ) + aggregate_result(total, data, :gen, :egen, :vom => (1.1,Inf))

        # Provide a set for filtering
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :genfuel => in(["ng", "coal"]) ) + aggregate_result(total, data, :gen, :egen, :genfuel => !in(["ng", "coal"]))
        
        # Provide an index(es) for filtering
        @test tot ≈ aggregate_result(total, data, :gen, :egen, 1 ) + aggregate_result(total, data, :gen, :egen, 2:nrow(data[:gen]))
    end

    @testset "Test year_idx filters" begin
        tot = aggregate_result(total, data, :gen, :egen)
        nyr = get_num_years(data)

        # Year index
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, 1) + aggregate_result(total, data, :gen, :egen, :, 2:nyr)

        # Year string
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, "y2030") + aggregate_result(total, data, :gen, :egen, :, ["y2035", "y2040"])
        
        # Range of years
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, ("y2020", "y2031")) + aggregate_result(total, data, :gen, :egen, :, ("y2032","y2045"))

        # Test function of years
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, <=("y2031")) + aggregate_result(total, data, :gen, :egen, :, >("y2031"))
    end

    @testset "Test hour_idx filters" begin
        tot = aggregate_result(total, data, :gen, :egen)
        nhr = get_num_hours(data)

        # Hour index
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, :, 1) + aggregate_result(total, data, :gen, :egen, :, :, 2:nhr)

        # Hour table label
        @test tot ≈ aggregate_result(total, data, :gen, :egen, :, :, (:time_of_day=>"morning", :season=>"summer")) + 
            aggregate_result(total, data, :gen, :egen, :, :, (:time_of_day=>"morning", :season=>!=("summer"))) +
            aggregate_result(total, data, :gen, :egen, :, :, :time_of_day=>!=("morning"))
            
    end

    @testset "Other Aggregation Tests" begin

        # Test that summing the co2 emissions for solar in 2030 is zero
        @test aggregate_result(total, data, :gen, :emis_co2, :gentype=>"solar", "y2030", :) ≈ 0.0
    
        # Test that the average co2 emissions rate is between the min and max
        all_emis_co2 = get_table_col(data, :gen, :emis_co2)
        emis_co2_min, emis_co2_max = extrema(all_emis_co2)
        @test emis_co2_min <= aggregate_result(average, data, :gen, :emis_co2, :, "y2030", :) <= emis_co2_max
    
        # Test that the average capacity factor for solar generators is between 0 and 1
        @test 0 <= aggregate_result(average, data, :gen, :cf, :gentype=>"solar", :, :) <= aggregate_result(average, data, :gen, :af, :gentype=>"solar", :, :)
    
        # Test that the average LMP times energy served equals the sum of LMP
        elec_cost = aggregate_result(total, data, :bus, :lmp_eserv, :, :, :)
        elec_price = aggregate_result(average, data, :bus, :lmp_eserv, :, :, :)
        elec_quantity = aggregate_result(total, data, :bus, :eserv, :, :, :)
        @test elec_cost ≈ elec_price * elec_quantity
    
        # Test that there is no curtailment across all time
        ecurt = aggregate_result(total, data, :bus, :ecurt, :, :, :)
        @test ecurt < 1e-6
    
        # Test that total power capacity is greater than or equal to average demand
        pcap = aggregate_result(total, data, :gen, :pcap)
        pdem = aggregate_result(total, data, :bus, :pdem)
        @test pcap >= pdem
    
        # Test that the maximum of pcap is less than the total
        pcap_max = aggregate_result(maximum, data, :gen, :pcap)
        pcap_min = aggregate_result(minimum, data, :gen, :pcap)
        @test pcap_max > pcap_min
        @test pcap_max <= pcap
    
        # Check on the MWh generated by each gen fuel.
        gen = get_table(data, :gen)
        genfuels = unique(gen.genfuel)
        egen_by_genfuel = map(genfuels) do gf
            aggregate_result(total, data, :gen, :egen, :genfuel=>gf)
        end
        egen_total = aggregate_result(total, data, :gen, :egen)
        @test sum(egen_by_genfuel) ≈ egen_total
    end

end

@testset "Test Results Mods" begin
    # Setup
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    parse_results!(config, data, model)

    @testset "Test AggregationTemplate" begin
        # Make new mod
        agg_file=joinpath(@__DIR__, "data/3bus/aggregate_template.csv")
        name = :agg_res
        mod = AggregationTemplate(;file=agg_file, name)

        mods = get_mods(config)
        empty!(mods)
        mods[name] = mod
        
        process_results!(config, data)
        @test isfile(get_out_path(config, "$name.csv"))
        results = get_results(data)
        @test haskey(results, name)
    end

    @testset "Test YearlyTable" begin
        @testset "Test yearly bus table grouped by country, season, and time of day" begin
            # Make new mod
            name = :bus_res_season_time_of_day
            mod = YearlyTable(;
                name,
                table_name = :bus,
                groupby = "country",
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
                @test hasproperty(df, :country)
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
    out_path, _ = run_e4st(config_file)

    # Now load the config from the out_path, with some results processing mods too.  Could also add the mods manually here.
    mod_file= joinpath(@__DIR__, "config/config_res.yml")
    config = load_config(out_path, mod_file)
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


