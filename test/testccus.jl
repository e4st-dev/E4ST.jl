@testset "Test CCUS" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    ccus_config_file = joinpath(@__DIR__, "config/config_ccus.yml")
    config = load_config(config_file, ccus_config_file)
    out_path, _ = run_e4st(config)
    @test out_path isa String
end