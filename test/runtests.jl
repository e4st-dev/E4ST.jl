using Test
using E4ST
import OrderedCollections: OrderedDict

@testset "Test E4ST" begin
    @testset "Unit Tests" begin
        @testset "Test Loading Config" begin
            #include("testloadconfig.jl")
            @test_skip "Not working currently"
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
        @test_skip "No Tests Written"
    end
end