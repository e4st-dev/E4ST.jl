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
    include("testloadconfig.jl")
    include("testsaveconfig.jl")
    include("testloaddata.jl")
    include("testinitializedata.jl")
    include("testsetupmodel.jl")
    include("testpoltypes.jl")
    include("testoptimizemodel.jl")
    include("testresultprocessing.jl")
    include("testiteration.jl")
    include("testutil.jl")
end

global_logger(original_logger)

# Garbage collect any random things that might be locking a resource
GC.gc()
rm(joinpath(@__DIR__, "out"), force=true, recursive=true)
