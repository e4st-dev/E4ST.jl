@testset "Test Optimizing Model" begin

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = read_config(config_file)

    data = read_data(config)
    model = setup_model(config, data)

    optimize!(model)
    # solution_summary(model)

    @test check(model)

    parse_results!(config, data, model)

    @testset "Test no curtailment" begin
        bus = get_table(data, :bus)
        years = get_years(data)
        rep_hours = get_table(data, :hours)
        total_elserv = aggregate_result(total, data, :bus, :elserv)
        total_elnom = aggregate_result(total, data, :bus, :elnom)
        # total_plserv = sum(rep_hours.hours[hour_idx].*value.(model[:plserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
        total_elcurt = aggregate_result(total, data, :bus, :elcurt)
        @test total_elserv ≈ total_elnom
        @test all(p->abs(p)<1e-6, total_elcurt)
    end

    @testset "Test DC lines" begin
        res_raw = get_raw_results(data)
        @test haskey(data, :dc_line)
        @test haskey(res_raw, :pflow_dc)
        @test 0 < maximum(abs, res_raw[:pflow_dc]) <= maximum(get_table(data, :dc_line).pflow_max)
    end

    # make sure energy generated is non_zero
    gen = get_table(data, :gen)

    for gen_idx in 1:nrow(gen)
        @test aggregate_result(total, data, :gen, :egen, gen_idx) >= 0
    end

    @testset "Test exogenous retirement" begin
        @test count(==("retired_exog"), gen.build_status) == 1
        @test count(==("retired_endog"), gen.build_status) > 1
    end

    @testset "Test site constraints" begin
        build_gen = get_table(data, :build_gen)
        bus = get_table(data, :bus)
        nyr = get_num_years(data)
        @test all(
            aggregate_result(total, data, :gen, :pcap, [:build_id=>row.build_id, :bus_idx=>bus_idx], yr_idx) <= row.pcap_max
            for row in eachrow(build_gen), bus_idx in 1:nrow(bus), yr_idx in 1:nyr
        )
        res_raw = get_raw_results(data)
        @test haskey(res_raw, Symbol("cons_pcap_gen_match_max_build"))
        @test haskey(res_raw, Symbol("cons_pcap_gen_match_min_build"))
    end

    @testset "Test Accessor methods" begin
        @test aggregate_result(total, data, :gen, :egen, :genfuel=>"ng", "y2040", 1:3) ≈ 
            aggregate_result(total, data, :gen, :egen, :genfuel=>"ng", 3, [1,2,3])

        @test aggregate_result(total, data, :gen, :egen, 1:2, ["y2035","y2040"], 1:3) ≈ 
            aggregate_result(total, data, :gen, :egen, 1, 2:3, [1,2,3]) + 
            aggregate_result(total, data, :gen, :egen, 2, 2:3, 1) +
            aggregate_result(total, data, :gen, :egen, 2, 2:3, 2) +
            aggregate_result(total, data, :gen, :egen, 2, 2:3, 3)

        @test aggregate_result(total, data, :gen, :egen) ≈ aggregate_result(total, data, :gen, :egen, :)
        @test aggregate_result(total, data, :gen, :egen, :genfuel=>"ng") ≈
            aggregate_result(total, data, :gen, :egen, (:genfuel=>"ng", :country=>"narnia")) + 
            aggregate_result(total, data, :gen, :egen, (:genfuel=>"ng", :country=>"archenland"))
        
    end

    @testset "Test line losses on plserv" begin
        egen = aggregate_result(total, data, :gen, :egen)
        elserv = aggregate_result(total, data, :bus, :elserv)
        @test egen ≈ elserv / (1-config[:line_loss_rate]) 
    end
    
    @testset "Test line losses with pflow" begin
        config = read_config(config_file, line_loss_type="pflow")
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)

        egen = aggregate_result(total, data, :gen, :egen)
        elserv = aggregate_result(total, data, :bus, :elserv)
        eflow_in = aggregate_result(total, data, :bus, :eflow_in)
        @test egen ≈ (config[:line_loss_rate] * eflow_in) + elserv
    end

    @testset "Test InterfaceLimit" begin
        # Test that without InterfaceLimit, branch flow is sometimes less than 0.2
        @test aggregate_result(minimum, data, :branch, :pflow, (:f_bus_idx=>1, :t_bus_idx=>2)) < 0.2 - 1e-9
        
        # Now run with interface limits and test that it is always >= 0.2
        config_file_if = joinpath(@__DIR__, "config", "config_3bus_if.yml")
        config = read_config(config_file, config_file_if)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        @test check(model)
        parse_results!(config, data, model)

        # Test that pflow limits were observed
        @test aggregate_result(minimum, data, :branch, :pflow, (:f_bus_idx=>1, :t_bus_idx=>2)) >= 0.2 - 1e-9

        # Test that there was no curtailment
        @test aggregate_result(total, data, :bus, :elcurt) < 1e-6

        # Test that eflow_yearly limits were observed.
        @test aggregate_result(total, data, :branch, :eflow, (:f_bus_idx=>1, :t_bus_idx=>2)) >= 2000
    end

end