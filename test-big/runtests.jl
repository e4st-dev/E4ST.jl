using Test
using Gurobi
using HiGHS
using E4ST
using JuMP

@testset "Test Full Model" begin
    @testset "Test Gurobi" begin
        @testset "Mini Tests First" begin
            include("../test-gurobi/runtests.jl")
        end
        @testset "Full Tests" begin
            config_2016 = "L:/Project-Gurobi/Workspace3/E4ST/Data/config/config_2016.yml"
            config_gurobi = joinpath(@__DIR__, "config/config_gurobi.yml")
            @time out_path, _ = run_e4st(config_2016, config_gurobi)

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