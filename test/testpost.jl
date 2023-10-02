@testset "Test e4st_post" begin
    # First make a few runs
    nsims = 3
    sim_paths = map(1:nsims) do i
        run_e4st(
            joinpath(@__DIR__, "config/config_3bus.yml")
        )
    end

    out_path = joinpath(@__DIR__, "out/post")
    
    rm(out_path, force=true, recursive=true)
    @test ~isdir(out_path)

    post_config = read_post_config(
        joinpath(@__DIR__, "config/post_config.yml");
        sim_paths,
        sim_names = ["sim$i" for i in 1:nsims],
        out_path,
    )

    @test isdir(out_path)

    e4st_post(post_config)

    @test isfile(get_out_path(post_config, "agg_res_combined.csv"))

    rm(out_path, force=true, recursive=true)
end