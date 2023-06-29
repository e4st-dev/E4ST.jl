@testset "Test Optimizing Model" begin

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = read_config(config_file, log_model_summary=true)

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
        total_elserv = compute_result(data, :bus, :elserv_total)
        total_elnom = compute_result(data, :bus, :elnom_total)
        # total_plserv = sum(rep_hours.hours[hour_idx].*value.(model[:plserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
        total_elcurt = compute_result(data, :bus, :elcurt_total)
        @test total_elserv ≈ total_elnom
        @test all(p->abs(p)<1e-6, total_elcurt)
    end

    @testset "Test bus results match gen results" begin
        # Test that revenue of electricity for generators equals the cost for users
        line_loss_rate = config[:line_loss_rate]
        @test compute_result(data, :bus, :elserv_total) ≈ (compute_result(data, :gen, :egen_total)) * (1 - line_loss_rate)
        @test compute_result(data, :bus, :electricity_cost) ≈ compute_result(data, :gen, :electricity_revenue)
    end

    @testset "Test misc. results computations" begin
        @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
        @test compute_result(data, :bus, :merchandising_surplus_total) >= 0.0
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
        @test compute_result(data, :gen, :egen_total, gen_idx) >= 0
    end

    @testset "Test retirement" begin
        @test count(==("retired_exog"), gen.build_status) == 1
        @test count(==("retired_endog"), gen.build_status) > 0
        @test compute_result(data, :gen, :pcap_retired_total, [:build_type=>"endog"]) < 0.001 # Shouldn't be retiring endogenously built capacity.

        updated_gen_table = read_table(get_out_path(config, "gen.csv"))

        @test ~any(row->(row.pcap_inv <= 0), eachrow(updated_gen_table))


        for row in eachrow(gen)
            if contains(row.build_status, "retired")
                @test row.year_off in get_years(data)
            else
                @test row.year_off == "y9999"
            end
        end
    end

    @testset "Test site constraints" begin
        build_gen = get_table(data, :build_gen)
        bus = get_table(data, :bus)
        nyr = get_num_years(data)
        @test all(
            compute_result(data, :gen, :pcap_total, [:build_id=>row.build_id, :bus_idx=>bus_idx], yr_idx) <= row.pcap_max + 1e-9
            for row in eachrow(build_gen), bus_idx in 1:nrow(bus), yr_idx in 1:nyr
        )
        res_raw = get_raw_results(data)
        @test haskey(res_raw, Symbol("cons_pcap_gen_match_max_build"))
        @test haskey(res_raw, Symbol("cons_pcap_gen_match_min_build"))
    end

    @testset "Test Accessor methods" begin
        @test compute_result(data, :gen, :egen_total, :genfuel=>"ng", "y2040", 1:3) ≈ 
            compute_result(data, :gen, :egen_total, :genfuel=>"ng", 3, [1,2,3])

        @test compute_result(data, :gen, :egen_total, 1:2, ["y2035","y2040"], 1:3) ≈ 
            compute_result(data, :gen, :egen_total, 1, 2:3, [1,2,3]) + 
            compute_result(data, :gen, :egen_total, 2, 2:3, 1) +
            compute_result(data, :gen, :egen_total, 2, 2:3, 2) +
            compute_result(data, :gen, :egen_total, 2, 2:3, 3)

        @test compute_result(data, :gen, :egen_total) ≈ compute_result(data, :gen, :egen_total, :)
        @test compute_result(data, :gen, :egen_total, :genfuel=>"ng") ≈
            compute_result(data, :gen, :egen_total, (:genfuel=>"ng", :nation=>"narnia")) + 
            compute_result(data, :gen, :egen_total, (:genfuel=>"ng", :nation=>"archenland"))
        
    end

    @testset "Test line losses on plserv" begin
        egen = compute_result(data, :gen, :egen_total)
        elserv = compute_result(data, :bus, :elserv_total)
        @test egen ≈ elserv / (1-config[:line_loss_rate]) 
    end
    
    @testset "Test line losses with pflow" begin
        config = read_config(config_file, line_loss_type="pflow")
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)

        egen = compute_result(data, :gen, :egen_total)
        elserv = compute_result(data, :bus, :elserv_total)
        eflow_in = compute_result(data, :bus, :eflow_in_total)
        @test egen ≈ (config[:line_loss_rate] * eflow_in) + elserv
    end

    @testset "Test FuelPrice Modification" begin
        config_fuel_price_file = joinpath(@__DIR__, "config/config_fuel_price.yml")
        config = read_config(config_file, config_fuel_price_file)

        data = read_data(config)
        model = setup_model(config, data)
        gen = get_table(data, :gen)
        nyr = get_num_years(data)
        nhr = get_num_hours(data)

        @test haskey(model, :fuel_used)
        @test haskey(model, :fuel_sold)

        optimize!(model)

        parse_results!(config, data, model)
        process_results!(config, data)

        fuel_sold = get_raw_result(data, :fuel_sold)
        fuel_used = get_raw_result(data, :fuel_used)

        @test sum(fuel_sold) ≈ sum(fuel_used)
        @test compute_result(data, :gen, :fuel_burned, :genfuel=>["ng", "coal"]) ≈ sum(fuel_sold)

        # Test NG specifically
        @test compute_result(data, :gen, :fuel_burned, (:genfuel=>"ng")) > 1e3 # If this is failing, probably need to redesign test or make fuel cheaper.

        for yr_idx in 1:nyr
            ng_used = compute_result(data, :gen, :fuel_burned, (:genfuel=>"ng", :nation=>"archenland"), yr_idx)
            ng_used == 0 && continue
            ng_price = compute_result(data, :fuel_markets, :fuel_clearing_price_per_mmbtu, (:genfuel=>"ng", :subarea=>"archenland"), yr_idx)
            ng_idxs = get_table_row_idxs(data, :gen, (:genfuel=>"ng", :nation=>"archenland"))
            for ng_idx in ng_idxs
                for hr_idx in 1:nhr
                    fuel_price = gen.fuel_price[ng_idx][yr_idx, hr_idx]
                    @test fuel_price ≈ ng_price
                    tol = 1e-6
                    if ng_used <= 50000 - tol
                        @test fuel_price ≈ 0.1
                    elseif abs(ng_used - 50000) < tol
                        @test 0.1 <= fuel_price <= 0.2
                    elseif 50000 < ng_used < 100000 - tol
                        @test fuel_price ≈ 0.2
                    elseif abs(ng_used - 100000) < tol
                        @test 0.2 <= fuel_price <= 0.3
                    elseif 100000 < ng_used <= 150000 - tol
                        @test fuel_price ≈ 0.3
                    elseif abs(ng_used - 150000) < tol
                        @test 0.3 <= fuel_price <= 0.4
                    else
                        @test fuel_price ≈ 0.4
                    end
                end
            end
        end

    end

        
    @testset "Test InterfaceLimit" begin
        # Test that without InterfaceLimit, branch flow is sometimes less than 0.2
        @test compute_result(data, :branch, :pflow_hourly_min, (:f_bus_idx=>1, :t_bus_idx=>2)) < 0.2 - 1e-9
        
        # Now run with interface limits and test that it is always >= 0.2
        config_file_if = joinpath(@__DIR__, "config", "config_3bus_if.yml")
        config = read_config(config_file, config_file_if)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        @test check(model)
        parse_results!(config, data, model)

        # Test that pflow limits were observed
        @test compute_result(data, :branch, :pflow_hourly_min, (:f_bus_idx=>1, :t_bus_idx=>2)) >= 0.2 - 1e-9

        # Test that there was no curtailment
        @test compute_result(data, :bus, :elcurt_total) < 1e-6

        # Test that eflow_yearly limits were observed.
        @test compute_result(data, :branch, :eflow_total, (:f_bus_idx=>1, :t_bus_idx=>2)) >= 2000
    end

end