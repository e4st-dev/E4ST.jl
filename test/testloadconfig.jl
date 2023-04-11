@testset "Test Loading Config" begin

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

    @test read_config(filename) isa AbstractDict
    config = read_config(filename)

    @test isabspath(config[:out_path])
    @test isabspath(config[:gen_file])
    @test isabspath(config[:bus_file])
    @test isabspath(config[:branch_file])

    @test config[:mods] isa OrderedDict{Symbol, <:Modification}
    @test config[:mods][:example_policy].name == :example_policy

    @testset "Test Loading Optimizer from Config" begin
        attrib = E4ST.optimizer_attributes(config)
        @test attrib isa NamedTuple
        for (k,v) in config[:optimizer]
            k == :type && continue
            @test haskey(attrib,k)
        end

        @test Model(E4ST.getoptimizer(config)) isa JuMP.Model
    end

    @testset "Test Logging" begin
        log_file = get_out_path(config, "E4ST.log")
        
        isfile(log_file) && rm(log_file, force=true)

        @test ~isfile(log_file)


        ## Normal Mode
        # See if logging sets up the log file
        start_logging!(config)
        @info "info!!!"
        @debug "debug!!!" # SHOULD NOT LOG BY DEFAULT
        @warn "warning!!!"
        @test isfile(log_file)
        stop_logging!(config)
        l1 = length(readlines(log_file))

        ## Debug Mode
        config[:logging] = "debug"
        start_logging!(config)
        @info "info!!!"
        @debug "debug!!!" # SHOULD LOG
        @warn "warning!!!"
        @test isfile(log_file)
        
        stop_logging!(config)
        l2 = length(readlines(log_file))

        # Test that the debug line created an extra 2 lines
        @test l2 == l1 + 2

        # Logging off
        rm(log_file, force=true)
        config[:logging] = false
        start_logging!(config)
        @info "info!!!"
        @debug "debug!!!"
        @warn "warning!!!"
        stop_logging!(config)
        @test ~isfile(log_file)

        # Log the info
        config[:logging] = true
        start_logging!(config)
        log_start(config)
        stop_logging!(config)
        @test length(readlines(log_file)) > 6

    end

    @testset "Test mod sorting by rank" begin
        config_file_base = joinpath(@__DIR__, "config", "config_3bus.yml")
        config_RPS = joinpath(@__DIR__, "config", "config_3bus_rps.yml")
        config_PTC = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")

        config = load_config(config_file_base, config_RPS, config_PTC)

        ranks = list_mod_ranks(config)
        @test ranks[:example_ptc] < ranks[:example_rps]

    end
end