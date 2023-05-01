@testset "Test Retrofits" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    config = read_config(config_file)
    mods = get_mods(config)
    mods[:coal_ccs_retro] = CoalCCSRetrofit()

    data = read_data(config)
    
    # Test that data has 3 retrofits - one for each year
    @test length(get_table_row_idxs(data, :gen, :gentype=>"coal_ccus_retrofit")) == 3
end