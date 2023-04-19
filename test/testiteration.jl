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
            ng_gen_total = aggregate_result(total, data, :gen, :egen, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            return abs(ng_gen_ann-tgt) > tol            
        end
        function E4ST.iterate!(iter::TargetAvgAnnualNGGen, config, data)
            tgt = iter.target
            ng_gen_total = aggregate_result(total, data, :gen, :egen, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            
            diff = ng_gen_ann - tgt
            gen = get_table(data, :gen, :genfuel=>"ng")
            ng_price_avg = sum(gen.fuel_cost)/length(gen.fuel_cost)
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
            gen.fuel_cost .+= ng_price_diff
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
end