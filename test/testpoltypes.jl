# Test basic poltypes 
# Includes PTC, ...

@testset "Test PTC" begin 
    config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)
    @test hasproperty(gen, :example_ptc)

    #test that there are byYear containers with non zero values 
    @test typeof(gen.example_ptc) == Vector{ByYear}


    #test that only has byYear for qualifying gens 

    #test that PTC is added to the obj 

end