@testset "Test Sector Representation" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    sector_config_file = joinpath(@__DIR__, "config/config_3bus_sector.yml")

    config = read_config(config_file, sector_config_file)

    data = read_data(config)

    model = setup_model(config, data)

    optimize!(model)

    parse_results!(config, data, model)
    process_results!(config, data)

    @test haskey(data, :nonelec)
  
    baseline = compute_result(data, :nonelec, :baseline_emis_total)
    resid = compute_result(data, :nonelec, :resid_emis_total)
    abate = compute_result(data, :nonelec, :abate_emis_total, :)
    electrify = compute_result(data, :nonelec, :elec_response_total)

    
    # test that there is some abatement
    @test abate > 0
    # test that abatement plus residual emissions is equal to the baseline emissions
    @test abate + resid ≈ baseline
    # test that there is some associated electrification response
    @test electrify > 0

    # Allowance price with the Sector mod active.
    cap_cons_name = :cons_example_emiscap_max
    @test haskey(data[:results][:raw], cap_cons_name)

    nyr = get_num_years(data)
    alw_prc_with_sector = [-get_shadow_price_as_ByYear(data, cap_cons_name)[yr_idx] for yr_idx in 1:nyr]

    # check that cap is binding
    @test any(>(0), alw_prc_with_sector)

    @test isfile(get_out_path(config, "nonelec.csv"))

    @testset "Test Economy-Wide Impact on Allowance Price" begin
        # Re-solve with the sector removed and an unchanged cap target
        config_ns = read_config(config_file, sector_config_file)
        delete!(config_ns[:mods], :transportation_sector)

        data_ns = read_data(config_ns)
        model_ns = setup_model(config_ns, data_ns)
        optimize!(model_ns)
        parse_results!(config_ns, data_ns, model_ns)
        process_results!(config_ns, data_ns)

        # no Sector mod means no :nonelec table at all
        @test !haskey(data_ns, :nonelec)

        alw_prc_no_sector = [-get_shadow_price_as_ByYear(data_ns, cap_cons_name)[yr_idx] for yr_idx in 1:nyr]

        # test that removing covered emissions loosens the cap
        @test all(alw_prc_with_sector .>= alw_prc_no_sector .- 1e-6)
    end
    
end