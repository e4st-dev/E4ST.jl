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

            config_file = joinpath(@__DIR__, "config/config_gurobi.yml")

            @time config=load_config(config_file);
            @test config isa AbstractDict

            @time data=load_data(config)
            @test data isa AbstractDict

            @time model = setup_model(config, data)
            @test model isa JuMP.Model

            optimize!(model)
            
            results_raw = parse_results(config, data, model)
            model = nothing
            results_user = process_results(config, data, results_raw)
            
            @test aggregate_result(total, data, results_raw, :bus, :ecurt) < 1e-3
            # run_e4st(config_file)
        end
    end

    @testset "Test HiGHS" begin
        @test_broken false
    end
end