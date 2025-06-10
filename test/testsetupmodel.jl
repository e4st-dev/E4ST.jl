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
            @test all(g.capex_obj[findall(year -> year < g.year_on, years)] .== 0.0) #capex_obj is 0 before year_on
        end

        @test haskey(data[:obj_vars], :fom)
        @test haskey(data[:obj_vars], :fuel_price)
        @test haskey(data[:obj_vars], :vom)
        @test haskey(data[:obj_vars], :capex_obj)
        @test haskey(data[:obj_vars], :curtailment_cost)

        @test sum(model[:obj_unscaled]) == 
            sum(model[:curtailment_cost]) + 
            sum(model[:fom]) + 
            sum(model[:fuel_price]) + 
            sum(model[:vom]) + 
            sum(model[:capex_obj]) +
            sum(model[:transmission_capex_obj]) + 
            sum(model[:routine_capex]) #this won't be a good system level test
       
        @testset "Test invalid operators" begin
        
            # test 1d case
            dims = 3  # Dimensions of the 3D array
            aff_array = Array{AffExpr}(undef, dims...)

            for i in 1:dims
                aff_array[i] = rand()  # this creates an AffExpr with just a constant
            end

            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test_var, aff_array, oper = *)
                nothing
            catch e
                e
            end

            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)

            # test 2d case
            dims = (3, 4)  # Dimensions of the 3D array
            aff_array = Array{AffExpr}(undef, dims...)

            for i in CartesianIndices(dims)
                aff_array[i] = rand()  # this creates an AffExpr with just a constant
            end

            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test_var, aff_array, oper = *)
                nothing
            catch e
                e
            end

            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)

            # test 3d case
            dims = (3, 4, 2)  # Dimensions of the 3D array
            aff_array = Array{AffExpr}(undef, dims...)

            for i in CartesianIndices(dims)
                aff_array[i] = rand()  # this creates an AffExpr with just a constant
            end

            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test_var, aff_array, oper = *)
                nothing
            catch e
                e
            end

            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)

        end

        @testset "Test sparse array" begin
            # 1d array
            sparse_array = Containers.@container([i = 1:3; i > 1], (i))
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = +)
                true
            end
            
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = -)
                true
            end
           
            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = *)
                nothing
            catch e
                e
            end
            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)

            # 2d array
            sparse_array = Containers.@container([i = 1:3, j = [1, 2]; i > 1], (i))
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = +)
                true
            end
            
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = -)
                true
            end
            
            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test_var, sparse_array, oper = *)
                nothing
            catch e
                e
            end
            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)
            
            # 3d array
            sparse_array = Containers.@container([i = 1:3, j = [2,3], k=[1,2];  i > 1], (i))
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test, sparse_array, oper = +)
                true
            end
            
            @test begin
                add_obj_exp!(data, model, PerMWhGen(), :test, sparse_array, oper = -)
                true
            end
           
            err = try
                add_obj_exp!(data, model, PerMWhGen(), :test, sparse_array, oper = *)
                nothing
            catch e
                e
            end
            @test isa(errs, ErrorException)
            @test occursin("The entered operator isn't valid, oper must be + or -", err.msg)
        end

    end
    
end