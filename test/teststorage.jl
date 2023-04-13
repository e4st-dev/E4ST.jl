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
    @show pcharge_stor = get_raw_result(data, :pcharge_stor)
    @show pdischarge_stor = get_raw_result(data, :pdischarge_stor)

    @show pcap_stor
    @show echarge
    @show edischarge
    @show obj
    # @show cons_stor_charge_bal
    @show e0_stor
    

    @test pcap_stor > 0.001
    @test echarge > edischarge

    # Test that we are either charging or discharging in every hour, not both
    thresh = 1e-6
    @test all(i->(pcharge_stor[i] < thresh || pdischarge_stor[i] < thresh), eachindex(pcharge_stor))


end