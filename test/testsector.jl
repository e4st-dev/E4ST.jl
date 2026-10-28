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

    # Test that the data validation step works. Each case below feeds it a deliberately 
    # broken copy to exercise the error paths.
    @testset "Input validation" begin
        sec   = config[:mods][:transportation_sector]
        nm    = sec.name
        mac   = get_table(data, Symbol("sector_$(nm)_mac_steps"))
        emis  = get_table(data, Symbol("sector_$(nm)_emis_baseline"))
        elec  = get_table(data, Symbol("sector_$(nm)_elec_baseline"))
        lp    = get_table(data, Symbol("sector_$(nm)_load_profile"))
        elast = get_table(data, Symbol("sector_$(nm)_elasticity"))

        validate(; mac=mac, emis=emis, elec=elec, lp=lp, elast=elast) =
            E4ST._validate_sector_inputs(sec, data, mac, emis, elec, lp, elast)

        # the unmodified tables pass
        @test validate() === nothing

        # `area` must name a column of the bus table
        bad_area = copy(emis); bad_area.area .= "not_a_bus_column"
        @test_throws "not a column of the bus table" validate(emis = bad_area)

        # both baselines need a column per simulation year
        yr1 = Symbol(first(get_years(data)))
        @test_throws "emis_baseline has no column for simulation year" validate(emis = select(emis, Not(yr1)))
        @test_throws "elec_baseline has no column for simulation year" validate(elec = select(elec, Not(yr1)))

        # load shapes: no negatives, not all zero
        neg = copy(lp); neg[1, :h1] = -1.0
        @test_throws "has a negative value in h1" validate(lp = neg)
        zeroed = copy(lp)
        for hr_idx in 1:get_num_hours(data); zeroed[1, Symbol("h$hr_idx")] = 0.0; end
        @test_throws "all-zero load shape" validate(lp = zeroed)

        # duplicate rows in each of the four tables keyed one-per-region-subsector
        @test_throws "emis_baseline has 2 rows" validate(emis  = vcat(emis,  emis[1:1, :]))
        @test_throws "elec_baseline has 2 rows" validate(elec  = vcat(elec,  elec[1:1, :]))
        @test_throws "elasticity has 2 rows"    validate(elast = vcat(elast, elast[1:1, :]))
        @test_throws "load_profile has 2 rows"  validate(lp    = vcat(lp,    lp[1:1, :]))

        # every region-subsector needs an elasticity row, an electricity row,
        # MAC steps, a load profile, and at least one matching bus
        @test_throws "no matching elasticity row"   validate(elast = elast[2:end, :])
        @test_throws "no matching elec_baseline row" validate(elec = elec[2:end, :])
        @test_throws "has no MAC steps"              validate(mac = mac[0:-1, :])
        @test_throws "no usable load profile row"    validate(lp = lp[0:-1, :])

        no_bus = copy(emis); no_bus.subarea .= "nowhere"
        @test_throws "matches no rows in the bus table" validate(emis = no_bus)

        # a zero denominator leaves elec_per_emis undefined
        zero_elast = copy(elast); zero_elast.own_elast .= 0.0
        @test_throws "own_elast = 0" validate(elast = zero_elast)
        zero_emis = copy(emis); zero_emis[!, yr1] .= 0.0
        @test_throws "zero baseline emissions" validate(emis = zero_emis)
    end

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