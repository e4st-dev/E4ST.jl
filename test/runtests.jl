using Test
using E4ST
using HiGHS
using JuMP
using DataFrames
using Logging
using BasicInterpolators
import OrderedCollections: OrderedDict

# Garbage collect any random things that might be locking a resource
GC.gc()
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
            include("testloaddata.jl")
        end
        @testset "Test Initializing Data" begin
            include("testinitializedata.jl")
        end
        @testset "Test Setting Up Model" begin
            include("testsetupmodel.jl")
        end
        @testset "Test Optimizing Model" begin
            include("testoptimizemodel.jl")
        end
        @testset "Test Parsing and Saving Results" begin
            @test_skip "No Tests Written"
        end
        @testset "Test Iteration" begin
            include("testiteration.jl")
        end

        include("testutil.jl")
    end
    # @testset "System Tests" begin
    #     include("test3bus.jl")
    # end
end

global_logger(original_logger)

# Garbage collect any random things that might be locking a resource
GC.gc()
rm(joinpath(@__DIR__, "out"), force=true, recursive=true)
