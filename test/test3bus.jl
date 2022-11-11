config_file = joinpath(@__DIR__, "config", "config_3bus.yml")

@testset "Test Loading the Config File" begin
    @test load_config(config_file) isa AbstractDict    
end

config = load_config(config_file)

@testset "Test Loading the Data" begin    
    data = load_data(config)
    @test data isa AbstractDict
    @test data[:gen] isa DataFrame
    @test data[:bus] isa DataFrame
    @test data[:branch] isa DataFrame
    @test data[:time] isa DataFrame
end

data = load_data(config)

@testset "Test Initializing the Data" begin
    @testset "Test Initializing the Data with no mods" begin
        config = load_config(config_file)
        @test isempty(config[:mods])
        data = load_data(config)
        data_0 = deepcopy(data)
        initialize_data!(config, data)
        @test data == data_0
    end
    @testset "Test Initializing the Data with a mod" begin
        struct DoubleLoad <: Modification end
        function E4ST.initialize!(sym, ::DoubleLoad, config, data)
            data[:bus][!, :pd] .*= 2
        end
        config = load_config(config_file)
        push!(config[:mods], :testmod=>DoubleLoad())
        @test ~isempty(config[:mods])
        data = load_data(config)
        data_0 = deepcopy(data)
        initialize_data!(config, data)
        @test data != data_0
        @test sum(data[:bus].pd) == 2*sum(data_0[:bus].pd)
    end
end

@testset "Test Setting up the model" begin
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    @test model isa JuMP.Model
    optimize!(model)
    @test_broken check(model)
end