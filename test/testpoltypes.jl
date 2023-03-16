# Test basic poltypes 
# Includes PTC, ITC, ...

# Setup reference case 
####################################################################
config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
config_ref = load_config(config_file_ref)

data_ref = load_data(config_ref)
model_ref = setup_model(config_ref, data_ref)

optimize!(model_ref)

all_results_ref = []

results_raw_ref = parse_results(config_ref, data_ref, model_ref)
results_user_ref = process_results(config_ref, data_ref, results_raw_ref)
push!(all_results_ref, results_user_ref)


# Policy tests
#####################################################################

@testset "Test PTC" begin 
    config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
    config = load_config(config_file_ref, config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)

    @testset "Adding PTC to gen table" begin
        @test hasproperty(gen, :example_ptc)

        #test that there are byYear containers 
        @test typeof(gen.example_ptc) == Vector{Container}

        @test any(ptc -> typeof(ptc) == E4ST.ByYear, gen.example_ptc)
        
        # test that ByYear containers have non zero values
        @test sum(ptc->sum(ptc.v), gen.example_ptc) > 0

        #TODO: test that only has byYear for qualifying gens 
    end

    @testset "Adding PTC to model" begin
        #test that PTC is added to the obj 
        @test haskey(data[:obj_vars], :example_ptc)
        @test haskey(model, :example_ptc) 

        #make sure model still optimizes 
        optimize!(model)
        @test check(model)

        #make sure obj was lowered
        @test objective_value(model) < objective_value(model_ref) #if this isn't working, check that it isn't due to differences between the config files
    end

end


@testset "Test ITC" begin
    config_file = joinpath(@__DIR__, "config", "config_3bus_itc.yml")
    config = load_config(config_file_ref, config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)
    
    @testset "Adding ITC to gen table" begin
        @test hasproperty(gen, :example_itc)

        # Test that there are byYear containers 
        @test typeof(gen.example_itc) == Vector{Container}

        # Check that there are ByYear containers
        @test any(itc -> typeof(itc) == E4ST.ByYear, gen.example_itc)
        
        # test that ByYear containers have non zero values
        tot_itc = 0

        @test sum(itc->sum(itc.v), gen.example_itc) > 0
    end

    @testset "Adding ITC to the model" begin
        #test that ITC is added to the obj 
        @test haskey(data[:obj_vars], :example_itc)
        @test haskey(model, :example_itc) 

        #make sure model still optimizes 
        optimize!(model)
        @test check(model)

        #make sure obj was lowered
        @test objective_value(model) < objective_value(model_ref) #if this isn't working, check that it isn't due to differences between the config files

    end
end


@testset "Test EmissionCap" begin
    config_file = joinpath(@__DIR__, "config", "config_3bus_emiscap.yml")
    config = load_config(config_file_ref, config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)

    @testset "Saving correctly to the config" begin
        # read back into config yaml without the gen_cons
        save_config(config)

        outfile = out_path(config,basename(config[:config_file]))
        savedconfig = YAML.load_file(outfile, dicttype=OrderedDict{Symbol, Any})
        savedmods = savedconfig[:mods]

        @test haskey(savedmods, :example_emiscap)

        emiscap = savedmods[:example_emiscap]
        @test ~haskey(emiscap, :gen_cons)
    end

    @testset "Add constraint to model" begin
        # Creates GenerationConstraint
        @test typeof(config[:mods][:example_emiscap][:gen_cons]) == E4ST.GenerationConstraint


        # Added to the gen table 
        @test hasproperty(gen, :example_emiscap)
        for i in 1:nrow(gen)
            @test gen[i, :example_emiscap] == true
        end


        # Constraint added to the model
        @test haskey(model, :cons_example_emiscap_max)

    end

    @testset "Model optimizes correctly" begin
        ## make sure model still optimizes 
        optimize!(model)
        @test check(model)

        # process results
        all_results = []

        results_raw = parse_results(config, data, model)
        results_user = process_results(config, data, results_raw)
        push!(all_results, results_user)
         


        ## Check that policy impacts results 
        gen = get_table(data, :gen)
        years = get_years(data)
        emis_co2_total = aggregate_result(total, data, results_raw, :gen, :emis_co2)

        gen_ref = get_table(data_ref, :gen)
        emis_co2_total_ref = aggregate_result(total, data_ref, results_raw_ref, :gen, :emis_co2)

        # check that emissions are reduced
        @test emis_co2_total < emis_co2_total_ref

        # check that yearly cap values are actually followed
        idx_2035 = get_year_idxs(data, "y2035")
        emis_co2_total_2035 = aggregate_result(total, data, results_raw, :gen, :emis_co2, :, idx_2035)

        @test emis_co2_total_2035 <= config[:mods][:example_emiscap][:values][:y2035] + 0.001

        idx_2040 = get_year_idxs(data, "y2040")
        emis_co2_total_2040 = aggregate_result(total, data, results_raw, :gen, :emis_co2, :, idx_2040)

        @test emis_co2_total_2040 <= config[:mods][:example_emiscap][:values][:y2040] + 0.001

        #check that policy is binding 
        cap_prices = shadow_price.(model[:cons_example_emiscap_max])
        @test abs(cap_prices[:y2035]) > 1e-6
        @test abs(cap_prices[:y2040]) > 1e-6 #TODO: Not sure what this tolerance should be



    end
end
