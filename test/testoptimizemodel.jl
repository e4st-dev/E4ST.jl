
@testset "Test Optimizing Model" begin

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)

    optimize!(model)
    # solution_summary(model)

    @test check(model)

    res_raw = parse_results(config, data, model)
    res_user = process_results(config, data, res_raw)

    @testset "Test no curtailment" begin
        bus = get_table(data, :bus)
        years = get_years(data)
        rep_hours = get_table(data, :hours)
        total_eserv = aggregate_result(total, data, res_raw, :bus, :eserv)
        total_edem = aggregate_result(total, data, res_raw, :bus, :edem)
        # total_pserv = sum(rep_hours.hours[hour_idx].*value.(model[:pserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
        total_ecurt = aggregate_result(total, data, res_raw, :bus, :ecurt)
        @test total_eserv ≈ total_edem
        @test all(p->abs(p)<1e-6, total_ecurt)
    end

    @testset "Test DC lines" begin
        @test haskey(data, :dc_line)
        @test haskey(res_raw, :pflow_dc)
        @test 0 < maximum(abs, res_raw[:pflow_dc]) <= maximum(get_table(data, :dc_line).pflow_max)
    end

    # make sure energy generated is non_zero
    gen = get_table(data, :gen)

    for gen_idx in 1:nrow(gen)
        @test aggregate_result(total, data, res_raw, :gen, :egen, gen_idx) >= 0
    end

    @testset "Test Accessor methods" begin
        @test aggregate_result(total, data, model, :gen, :egen, :genfuel=>"ng", "y2040", 1:3) ≈ 
            aggregate_result(total, data, model, :gen, :egen, :genfuel=>"ng", 3, [1,2,3])

        @test aggregate_result(total, data, model, :gen, :egen, 1:2, ["y2035","y2040"], 1:3) ≈ 
            aggregate_result(total, data, model, :gen, :egen, 1, 2:3, [1,2,3]) + 
            aggregate_result(total, data, model, :gen, :egen, 2, 2:3, 1) +
            aggregate_result(total, data, model, :gen, :egen, 2, 2:3, 2) +
            aggregate_result(total, data, model, :gen, :egen, 2, 2:3, 3)

        @test aggregate_result(total, data, model, :gen, :egen) ≈ aggregate_result(total, data, model, :gen, :egen, :)
        @test aggregate_result(total, data, model, :gen, :egen, :genfuel=>"ng") ≈
            aggregate_result(total, data, model, :gen, :egen, (:genfuel=>"ng", :country=>"narnia")) + 
            aggregate_result(total, data, model, :gen, :egen, (:genfuel=>"ng", :country=>"archenland"))
        
    end
end