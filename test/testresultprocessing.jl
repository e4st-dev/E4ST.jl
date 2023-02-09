# Tests parsing, processing, and saving of results 

@testset "Test loading/saving data from .jls file" begin
    config = load_config(config_file)
    config[:out_path] = "../out/3bus1"
    E4ST.make_out_path!(config)
    data1 = load_data(config)

    # Check that it is trying to load in the data file
    config[:data_file] = "../out/3bus1/blah.jls"
    @test_throws Exception load_data(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:data_file] = "../out/3bus1/data.jls"
    config[:demand_file] = "blah.csv"
    data2 = load_data(config)
    @test data1 == data2
end

@testset "Test loading/saving model from .jls file" begin
    config = load_config(config_file)
    config[:out_path] = "../out/3bus1"
    config[:save_model_presolve] = true
    E4ST.make_paths_absolute!(config, config_file)
    E4ST.make_out_path!(config)
    data = load_data(config)
    model1 = setup_model(config, data)

    # Check that it is trying to load in the model file
    config[:model_presolve_file] = "bad/path/to/blah.jls"
    @test_throws Exception setup_model(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:model_presolve_file] = "../out/3bus1/model_presolve.jls"
    E4ST.make_paths_absolute!(config, config_file)
    model2 = setup_model(config, data)
    optimize!(model1)
    optimize!(model2)
    @test value.(model1[:θ_bus]) ≈ value.(model2[:θ_bus])
end


@testset "Test get_gen_result access" begin
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    res_raw = parse_results(config, data, model)
    res_user = process_results(config, data, res_raw)
    
    @testset "Test gen_idx filters" begin
        tot = aggregate_result(total, data, model, :gen, :egen)
        
        # Provide a function for filtering
        @test tot == aggregate_result(total, data, model, :gen, :egen, :emis_co2 => <=(0.1)) + aggregate_result(total, data, model, :gen, :egen, :emis_co2 => >(0.1))

        # Provide a region for filtering
        @test tot == aggregate_result(total, data, model, :gen, :egen, :country => "narnia") + aggregate_result(total, data, model, :gen, :egen, :country => !=("narnia"))

        # Provide a tuple for filtering
        @test tot == aggregate_result(total, data, model, :gen, :egen, :vom => (0,1.1) ) + aggregate_result(total, data, model, :gen, :egen, :vom => (1.1,Inf))

        # Provide a set for filtering
        @test tot == aggregate_result(total, data, model, :gen, :egen, :genfuel => in(["ng", "coal"]) ) + aggregate_result(total, data, model, :gen, :egen, :genfuel => !in(["ng", "coal"]))
        
        # Provide an index(es) for filtering
        @test tot == aggregate_result(total, data, model, :gen, :egen, 1 ) + aggregate_result(total, data, model, :gen, :egen, 2:nrow(data[:gen]))
    end

    @testset "Test year_idx filters" begin
        tot = aggregate_result(total, data, model, :gen, :egen)
        nyr = get_num_years(data)

        # Year index
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, 1) + aggregate_result(total, data, model, :gen, :egen, :, 2:nyr)

        # Year string
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, "y2030") + aggregate_result(total, data, model, :gen, :egen, :, ["y2035", "y2040"])
        
        # Range of years
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, ("y2020", "y2031")) + aggregate_result(total, data, model, :gen, :egen, :, ("y2032","y2045"))

        # Test function of years
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, <=("y2031")) + aggregate_result(total, data, model, :gen, :egen, :, >("y2031"))
    end

    @testset "Test hour_idx filters" begin
        tot = aggregate_result(total, data, model, :gen, :egen)
        nhr = get_num_hours(data)

        # Hour index
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, :, 1) + aggregate_result(total, data, model, :gen, :egen, :, :, 2:nhr)

        # Hour table label
        @test tot == aggregate_result(total, data, model, :gen, :egen, :, :, (:time_of_day=>"morning", :season=>"summer")) + 
            aggregate_result(total, data, model, :gen, :egen, :, :, (:time_of_day=>"morning", :season=>!=("summer"))) +
            aggregate_result(total, data, model, :gen, :egen, :, :, :time_of_day=>!=("morning"))
            
    end




    # Here is the new stuff - consider removing above.
    @testset "Test Aggregation" begin

        # Test that summing the co2 emissions for solar in 2030 is zero
        @test aggregate_result(total, data, res_raw, :gen, :emis_co2, :gentype=>"solar", "y2030", :) == 0.0
    
        # Test that the average co2 emissions rate is between the min and max
        all_emis_co2 = get_table_col(data, :gen, :emis_co2)
        emis_co2_min, emis_co2_max = extrema(all_emis_co2)
        @test emis_co2_min <= aggregate_result(average, data, res_raw, :gen, :emis_co2, :, "y2030", :) <= emis_co2_max

        # Test that the average capacity factor for solar generators is between 0 and 1
        @test 0 <= aggregate_result(average, data, res_raw, :gen, :cf, :gentype=>"solar", :, :) <= aggregate_result(average, data, res_raw, :gen, :af, :gentype=>"solar", :, :)

        # Test that the average LMP times energy served equals the sum of LMP
        elec_cost = aggregate_result(total, data, res_raw, :bus, :lmp_eserv, :, :, :)
        elec_price = aggregate_result(average, data, res_raw, :bus, :lmp_eserv, :, :, :)
        elec_quantity = aggregate_result(total, data, res_raw, :bus, :eserv, :, :, :)
        @test elec_cost ≈ elec_price * elec_quantity

        # Test that there is no curtailment across all time
        ecurt = aggregate_result(total, data, res_raw, :bus, :ecurt, :, :, :)
        @test ecurt < eps(Float64)

        # Test that total power capacity is greater than or equal to average demand
        pcap = aggregate_result(total, data, res_raw, :gen, :pcap)
        pdem = aggregate_result(total, data, res_raw, :bus, :pdem)
        @test pcap >= pdem

        # Test that the maximum of pcap is less than the total
        pcap_max = aggregate_result(maximum, data, res_raw, :gen, :pcap)
        pcap_min = aggregate_result(minimum, data, res_raw, :gen, :pcap)
        @test pcap_max > pcap_min
        @test pcap_max <= pcap

        # Check on the MWh generated by each gen fuel.
        gen = get_table(data, :gen)
        genfuels = unique(gen.genfuel)
        egen_by_genfuel = map(genfuels) do gf
            aggregate_result(total, data, res_raw, :gen, :egen, :genfuel=>gf)
        end
        egen_total = aggregate_result(total, data, res_raw, :gen, :egen)
        @test sum(egen_by_genfuel) ≈ egen_total
    end

    @testset "Test AggregationTemplate" begin
        mods = config[:mods]
        name = :agg_res
        mods[name] = AggregationTemplate(;file=joinpath(@__DIR__, "data/3bus/aggregate_template.csv"), name)
        data = load_data(config)
        model = setup_model(config, data)
        optimize!(model)
        res_raw = parse_results(config, data, model)
        res_user = process_results(config, data, res_raw)
        @test isfile(out_path(config, "agg_res.csv"))
    end

end


