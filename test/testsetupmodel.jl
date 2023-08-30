@testset "Test Setting Up Model" begin
    
    #Test setting up the model, including the dcopf

    @testset "Test variables added to objective" begin

        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = read_config(config_file)

        data = read_data(config)
        model = setup_model(config, data)
        @test model isa JuMP.Model

        gen = get_table(data, :gen)
        years = get_years(data)
        # test that capex_obj is calculated correctly
        @test hasproperty(gen, :capex_obj)
        @test !any(g -> g.build_status != "unbuilt" && sum(g.capex_obj.v) > 0, eachrow(gen)) # test that no existing generators have capex_obj
        for g in eachrow(gen)
            g.build_status == "unbuilt" || continue
            @test all(g.capex_obj[findall(year -> year < g.year_on, years)] .== 0.0)
        end

        @test haskey(data[:obj_vars], :fom)
        @test haskey(data[:obj_vars], :fuel_price)
        @test haskey(data[:obj_vars], :vom)
        @test haskey(data[:obj_vars], :capex_obj)
        @test haskey(data[:obj_vars], :curtailment_cost)
        @test model[:obj] == 
            sum(model[:curtailment_cost]) + 
            sum(model[:fom]) + 
            sum(model[:fuel_price]) + 
            sum(model[:vom]) + 
            sum(model[:capex_obj]) +
            sum(model[:transmission_capex_obj]) + 
            sum(model[:routine_capex]) #this won't be a good system level test
    end
end