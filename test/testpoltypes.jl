# Test basic poltypes 
# Includes PTC, ITC, ...

# Setup reference case 
config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
config_ref = load_config(config_file_ref)

data_ref = load_data(config_ref)
model_ref = setup_model(config_ref, data_ref)

optimize!(model_ref)

@testset "Test PTC" begin 
    config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
    config = load_config(config_file)

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
    config = load_config(config_file)

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
    
    # Creates GenerationConstraint

    # read back into config yaml without the gen_cons

    # Constraint added to the model

    # Reduced the emissions (may been to calibrate)


end