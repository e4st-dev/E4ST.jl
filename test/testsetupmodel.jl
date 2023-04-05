@testset "Test Setting Up Model" begin
    
    #Test setting up the model, including the dcopf

    @testset "Test variables added to objective" begin

        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = load_config(config_file)

        data = load_data(config)
        model = setup_model(config, data)
        @test model isa JuMP.Model

        @test haskey(data[:obj_vars], :fom)
        @test haskey(data[:obj_vars], :fuel_cost)
        @test haskey(data[:obj_vars], :vom)
        @test haskey(data[:obj_vars], :capex_obj)
        @test haskey(data[:obj_vars], :curtailment_cost)
        @test model[:obj] == sum(model[:curtailment_cost]) + sum(model[:fom]) + sum(model[:fuel_cost]) + sum(model[:vom]) + sum(model[:capex_obj]) #this won't be a good system level test
    end
end