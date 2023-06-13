# Test iterating the model

@testset "Test Iteration" begin
    config_file =  joinpath(@__DIR__, "config", "config_3bus.yml")
    
    @testset "Test Default Iteration" begin
        out_path, results = run_e4st(config_file)
        @test results isa AbstractVector
        @test length(results) == 1
    end
    @testset "Test Custom Iteration" begin
        Base.@kwdef struct TargetAvgAnnualNGGen <: E4ST.Iterable
            target::Float64
            tol::Float64
            avg_ng_prices::Vector{Float64}=Float64[]
            avg_ng_egen::Vector{Float64}=Float64[]
        end
        E4ST.fieldnames_for_yaml(::Type{TargetAvgAnnualNGGen}) = (:target, :tol)
        function E4ST.should_iterate(iter::TargetAvgAnnualNGGen, config, data)
            tgt = iter.target
            tol = iter.tol
            ng_gen_total = compute_result(data, :gen, :egen_total, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            return abs(ng_gen_ann-tgt) > tol            
        end
        function E4ST.iterate!(iter::TargetAvgAnnualNGGen, config, data)
            tgt = iter.target
            ng_gen_total = compute_result(data, :gen, :egen_total, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            
            diff = ng_gen_ann - tgt
            gen = get_table(data, :gen, :genfuel=>"ng")
            ng_price_avg = sum(gen.fuel_price)/length(gen.fuel_price)
            if any(≈(ng_gen_ann), iter.avg_ng_egen)
                idx = findfirst(≈(ng_gen_ann), iter.avg_ng_egen)
                iter.avg_ng_prices[idx] = ng_price_avg
            else
                push!(iter.avg_ng_prices, ng_price_avg)
                push!(iter.avg_ng_egen, ng_gen_ann)
            end

            sort!(iter.avg_ng_prices, rev=true)
            sort!(iter.avg_ng_egen)

            # Find the price difference
            if length(iter.avg_ng_prices) < 2
                ng_price_new = ng_price_avg + sign(diff) * 10.0
            else
                interp = LinearInterpolator(iter.avg_ng_egen, iter.avg_ng_prices, NoBoundaries())
                ng_price_new = interp(tgt)
            end
            ng_price_diff = ng_price_new - ng_price_avg
            gen.fuel_price .+= ng_price_diff
            return nothing            
        end
        E4ST.should_reread_data(::TargetAvgAnnualNGGen) = false
        
        config_iter_file = joinpath(@__DIR__, "config", "config_3bus_iter.yml")
        config = read_config(config_file, config_iter_file)
        
        @test config[:iter] isa TargetAvgAnnualNGGen

        # TODO: test saving and reading with iter
        all_results = run_e4st(config)
        @test length(all_results) > 1
    end

    @testset "Test Sequential Iteration" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        iter_file = joinpath(@__DIR__, "config", "iter_seq.yml")

        config = read_config(config_file, iter_file)

        @test get_iterator(config) isa RunSequential

        run_e4st(config)

        op = latest_out_path(config[:base_out_path])
        
        @test isdir(joinpath(op, "iter1"))
        @test isdir(joinpath(op, "iter2"))
        @test isfile(joinpath(op, "E4ST.log"))
        @test isfile(joinpath(op, "iter1", "gen.csv"))
        @test isfile(joinpath(op, "iter2", "gen.csv"))

        # TODO: think of any tests here that would better check the functionality
    end

    @testset "Test past capex calculations in sequential simulations" begin
        config_itc_file = joinpath(@__DIR__, "config", "config_3bus_itc.yml")
        config_stor_file = joinpath(@__DIR__, "config", "config_stor.yml")
        config = read_config(config_file, config_itc_file, config_stor_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)
        process_results!(config, data)

        @test compute_result(data, :gen, :past_invest_cost_total)    == 0.0
        @test compute_result(data, :gen, :past_invest_subsidy_total) == 0.0

        gen_updated_file = get_out_path(config, "gen.csv")
        gen_updated = read_table(gen_updated_file)
        storage_updated_file = get_out_path(config, "storage.csv")
        storage_updated = read_table(storage_updated_file)

        # Make sure that the past invest costs get updated for the next sim
        @test any(>(0.0), gen_updated.past_invest_cost)
        @test any(>(0.0), gen_updated.past_invest_subsidy)

        # Now run another sim with the updated gen table
        config = read_config(config_file, config_itc_file, config_stor_file)
        config[:years] = ["y2050", "y2060", "y2070"]
        config[:year_gen_data] = "y2040"
        config[:gen_file] = gen_updated_file
        config[:mods][:stor] = Storage(;name=:stor, file=storage_updated_file, build_file = config[:mods][:stor].build_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        @test check(model)
        parse_results!(config, data, model)
        process_results!(config, data)
        gen = get_table(data, :gen)

        @test compute_result(data, :gen, :past_invest_cost_total)    > 0.0
        @test compute_result(data, :gen, :past_invest_subsidy_total) > 0.0
        @test compute_result(data, :storage, :past_invest_cost_total)    > 0.0
        @test compute_result(data, :storage, :past_invest_subsidy_total) > 0.0

        # Test that no past invest cost for exogenous generators
        @test compute_result(data, :gen, :past_invest_cost_total, :build_type=>"exog") == 0.0
        @test compute_result(data, :gen, :past_invest_cost_total, :build_status=>"new") == 0.0
        @test compute_result(data, :gen, :past_invest_subsidy_total, :build_type=>"exog") == 0.0
        @test compute_result(data, :gen, :past_invest_subsidy_total, :build_status=>"new") == 0.0

        @test any(==("y2020"), gen.year_unbuilt)
        gen_idxs_unbuilt_2020 = get_row_idxs(gen, [:year_unbuilt=>"y2020", :build_type=>"endog"])
        for gen_idx in gen_idxs_unbuilt_2020
            # In 2050, the investment cost should be half of the full amount.
            @test gen.econ_life[gen_idx] == 35
            @test gen.past_invest_cost[gen_idx][1] ≈ 1.0 * (gen.transmission_capex[gen_idx] + gen.capex[gen_idx])
            @test gen.past_invest_cost[gen_idx][2] ≈ 0.5 * (gen.transmission_capex[gen_idx] + gen.capex[gen_idx])
            @test gen.past_invest_cost[gen_idx][3] ≈ 0.0
        end
    end
end