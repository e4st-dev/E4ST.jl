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
    
    @testset "Test gen_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        
        # Provide a function for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :emis_co2 => <=(0.1)) + get_gen_result(data, model, PerMWhGen(), :emis_co2 => >(0.1))

        # Provide a region for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :country => "narnia") + get_gen_result(data, model, PerMWhGen(), :country => !=("narnia"))

        # Provide a tuple for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :vom => (0,1.1) ) + get_gen_result(data, model, PerMWhGen(), :vom => (1.1,Inf))

        # Provide a set for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :genfuel => in(["ng", "coal"]) ) + get_gen_result(data, model, PerMWhGen(), :genfuel => !in(["ng", "coal"]))
        
        # Provide an index(es) for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), 1 ) + get_gen_result(data, model, PerMWhGen(), 2:nrow(data[:gen]))
    end

    @testset "Test year_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        nyr = get_num_years(data)

        # Year index
        @test tot == get_gen_result(data, model, PerMWhGen(), :, 1) + get_gen_result(data, model, PerMWhGen(), :, 2:nyr)

        # Year string
        @test tot == get_gen_result(data, model, PerMWhGen(), :, "y2030") + get_gen_result(data, model, PerMWhGen(), :, ["y2035", "y2040"])
        
        # Range of years
        @test tot == get_gen_result(data, model, PerMWhGen(), :, ("y2020", "y2031")) + get_gen_result(data, model, PerMWhGen(), :, ("y2032","y2045"))

        # Test function of years
        @test tot == get_gen_result(data, model, PerMWhGen(), :, <=("y2031")) + get_gen_result(data, model, PerMWhGen(), :, >("y2031"))
    end

    @testset "Test hour_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        nhr = get_num_hours(data)

        # Hour index
        @test tot == get_gen_result(data, model, PerMWhGen(), :, :, 1) + get_gen_result(data, model, PerMWhGen(), :, :, 2:nhr)

        # Hour table label
        @test tot == get_gen_result(data, model, PerMWhGen(), :, :, (:time_of_day=>"morning", :season=>"summer")) + 
            get_gen_result(data, model, PerMWhGen(), :, :, (:time_of_day=>"morning", :season=>!=("summer"))) +
            get_gen_result(data, model, PerMWhGen(), :, :, :time_of_day=>!=("morning"))
            
    end

end
