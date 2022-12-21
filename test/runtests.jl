using Test
using E4ST
using HiGHS
using JuMP
using DataFrames
using Logging
import OrderedCollections: OrderedDict
rm(joinpath(@__DIR__, "out"), force=true, recursive=true)

original_logger = global_logger(NullLogger())
@testset "Test E4ST" begin
    @testset "Unit Tests" begin
        @testset "Test Loading Config" begin
            include("testloadconfig.jl")
        end
        @testset "Test Saving Config" begin
            include("testsaveconfig.jl")
        end
        @testset "Test Loading Data" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Initializing Data" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Setting Up Model" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Optimizing Model" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Parsing and Saving Results" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Iteration" begin
            @test_skip "No Tests Written"
        end
    end
    @testset "System Tests" begin
        include("test3bus.jl")
    end
end

global_logger(original_logger)
rm(joinpath(@__DIR__, "out"), force=true, recursive=true)
