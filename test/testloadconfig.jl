Base.@kwdef struct ExamplePolicyType <: Policy
    name::Symbol
    value::Float64 = 1.0    # defaults to 1.0
    some_parameter::Vector  # no default, so it must be specified, can be a Vector of any kind
    other_parameter         # no default, and no type specification
end

Base.@kwdef struct OtherModificationType <: Modification
    value::Float64 = 1.0    # defaults to 1.0
    custom_parameter        # no default, and no type specification
end

filename = joinpath(@__DIR__, "config/config_3bus_examplepol.yml")

@test load_config(filename) isa AbstractDict
config = load_config(filename)

@test isabspath(config[:out_path])
@test isabspath(config[:gen_file])
@test isabspath(config[:bus_file])
@test isabspath(config[:branch_file])

@test config[:mods] isa OrderedDict{Symbol, <:Modification}
@test config[:mods][:example_policy].name == :example_policy

@testset "Test Loading Optimizer from Config" begin
    attrib = E4ST.optimizer_attributes(config)
    @test attrib isa NamedTuple
    @test attrib.dual_feasibility_tolerance   == 1e-5 # From config file, not the default
    @test attrib.primal_feasibility_tolerance == 1e-7 # From default, not in the config file
    @test Model(E4ST.getoptimizer(config)) isa JuMP.Model
end

@testset "Test Logging" begin
    log_file = abspath(config[:out_path], "E4ST.log")
    rm(log_file, force=true)

    @test (global_logger() isa ConsoleLogger)
    @test ~isfile(log_file)


    ## Normal Mode
    # See if logging sets up the log file
    start_logging!(config)
    @info "info!!!"
    @debug "debug!!!" # SHOULD NOT LOG BY DEFAULT
    @warn "warning!!!"
    @test ~(global_logger() isa ConsoleLogger)
    @test isfile(log_file)
    
    stop_logging!(config)
    @test (global_logger() isa ConsoleLogger)
    @test length(readlines(log_file)) == 4

    ## Debug Mode
    config[:logging] = "debug"
    start_logging!(config)
    @info "info!!!"
    @debug "debug!!!" # SHOULD LOG
    @warn "warning!!!"
    @test ~(global_logger() isa ConsoleLogger)
    @test isfile(log_file)
    
    stop_logging!(config)
    @test (global_logger() isa ConsoleLogger)
    @test length(readlines(log_file)) == 6




end
