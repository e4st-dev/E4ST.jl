using Test
using Gurobi
using HiGHS
using E4ST
using JuMP

@testset "Test Full Model" begin
    @testset "Test Gurobi" begin
        config_2016 = "L:/Project-Gurobi/Workspace3/E4ST/erussell/repos/e4st-input-processing/data/config/config_2016.yml"
        config_gurobi = joinpath(@__DIR__, "config/config_gurobi.yml")
        @testset "Mini Tests First" begin
            # include("../test-gurobi/runtests.jl")
        end

        @testset "Test Data" begin
            config = read_config(config_2016, config_gurobi)
            data = read_data(config)

            # Test that all generators have availability factors less than 1.
            @test all(gen_idx->(hr_idx->get_af(data, gen_idx, 1, hr_idx) < 1, 1:get_num_hours(data)), 1:nrow(get_table(data, :gen)))
        end
        @testset "Full Tests" begin
            base_out_path = joinpath(@__DIR__, "out/gurobi-expansion")
            @time out_path, _ = run_e4st(config_2016, config_gurobi; base_out_path)

            # @time config=read_config(config_file);
            # start_logging!(config)
            # @test config isa AbstractDict

            # @time data=read_data(config)
            # @test data isa AbstractDict

            # @time model = setup_model(config, data)
            # @test model isa JuMP.Model

            # optimize!(model)
            
            # results_raw = parse_results!(config, data, model)
            # model = nothing
            # results_user = process_results!(config, data, results_raw)
            
            data = read_processed_results(out_path)

            @test aggregate_result(total, data, :bus, :elcurt) < 1
            # run_e4st(config_file)
        end
    end

    @testset "Test HiGHS" begin
        @test_broken false
    end
end