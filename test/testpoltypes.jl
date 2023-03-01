# Test basic poltypes 
# Includes PTC, ...

@testset "Test PTC" begin 
    config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)
    @test hasproperty(gen, :example_ptc)

    #test that there are byYear containers 
    @test typeof(gen.example_ptc) == Vector{Container}

    idxs = findall(ptc -> typeof(ptc) == E4ST.ByYear, gen.example_ptc)
    @test sum(idxs) != 0
    
    # test that ByYear containers have non zero values
    for i in idxs
        @test sum(gen.example_ptc[i].v) != 0
    end

    #test that only has byYear for qualifying gens 

    #test that PTC is added to the obj 
    @test haskey(data[:obj_vars], :example_ptc)
    @test typeof(model[:example_ptc]) == Matrix{AffExpr} #mostly just trying to test that model[:example_ptc] exists

    #make sure model still optimizes 
    optimize!(model)
    @test check(model)

end


@testset "Test ITC" begin
    config_file = joinpath(@__DIR__, "config", "config_3bus_itc.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)

    gen = get_table(data, :gen)
    @test hasproperty(gen, :example_itc)

    #test that there are byYear containers 
    @test typeof(gen.example_itc) == Vector{Container}

    idxs = findall(itc -> typeof(itc) == E4ST.ByYear, gen.example_itc)
    @test sum(idxs) != 0 #TODO: change to meaningful test name, change idxs also in PTC
    
    # test that ByYear containers have non zero values
    tot_itc = 0
    for i in idxs
        tot_itc += sum(gen.example_itc[i].v)
    end
    @test tot_itc != 0

    #test that ITC is added to the obj 
    @test haskey(data[:obj_vars], :example_itc)
    @test typeof(model[:example_itc]) == Matrix{AffExpr} #mostly just trying to test that model[:example_ptc] exists

    #make sure model still optimizes 
    optimize!(model)
    @test check(model)

end