@testset "Test Storage Representation" begin
    config_file = joinpath(@__DIR__, "config/config_3bus.yml")
    storage_config_file = joinpath(@__DIR__, "config/config_stor.yml")

    config = read_config(config_file, storage_config_file; build_gen_file = nothing) # Run without endogenous generation

    data = read_data(config)

    model = setup_model(config, data)

    optimize!(model)

    parse_results!(config, data, model)
    process_results!(config, data)

    pcap_stor = aggregate_result(total, data, :storage, :pcap)
    echarge = aggregate_result(total, data, :storage, :echarge)
    edischarge = aggregate_result(total, data, :storage, :edischarge)
    obj = get_raw_result(data, :obj)
    cons_stor_charge_bal = get_raw_result(data, :cons_stor_charge_bal)
    e0_stor = get_raw_result(data, :e0_stor)
    pcharge_stor = get_raw_result(data, :pcharge_stor)
    pdischarge_stor = get_raw_result(data, :pdischarge_stor)    

    @test pcap_stor > 0.05

    # Test that there is some endogenous storage being built
    @test aggregate_result(total, data, :storage, :pcap, :build_type=>"endog") > 1e-6

    # Test that there is more charging than discharging due to loss
    @test echarge > edischarge
    @test aggregate_result(total, data, :bus, :elcurt) < 1e-6


    # Test that we are either charging or discharging in every hour, not both
    thresh = 1e-6
    @test all(i->(pcharge_stor[i] < thresh || pdischarge_stor[i] < thresh), eachindex(pcharge_stor))

    # Test that we have positive loss
    @test aggregate_result(total, data, :storage, :eloss) > 1e-6
    @test aggregate_result(total, data, :storage, :eloss) ≈ aggregate_result(total, data, :storage, :echarge) - aggregate_result(total, data, :storage, :edischarge)

    @test isfile(get_out_path(config, "storage.csv"))
end