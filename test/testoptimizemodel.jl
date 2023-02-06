
@testset "Test Optimizing Model" begin

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)

    optimize!(model)
    # solution_summary(model)

    @test check(model)

    @testset "Test no curtailment" begin
        bus = get_table(data, :bus)
        years = get_years(data)
        rep_hours = get_table(data, :hours)
        total_pserv = sum(rep_hours.hours[hour_idx].*value.(model[:pserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
        total_dl = sum(rep_hours.hours[hour_idx].*get_bus_value(data, :pdem, bus_idx, year_idx, hour_idx) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
        @test total_pserv ≈ total_dl
        @test all(p->abs(p)<1e-6, value.(model[:pcurt_bus]))
    end

    # make sure energy generated is non_zero
    gen = get_table(data, :gen)

    for gen_idx in 1:nrow(gen)
        @test value.(get_egen_gen(data, model, gen_idx)) >= 0
    end

    @testset "Test Accessor methods" begin
        @test get_model_val_by_gen(data, model, :egen_gen, :genfuel=>"ng", "y2040", 1:3) ≈ 
            get_model_val_by_gen(data, model, :egen_gen, :genfuel=>"ng", 3, [1,2,3])

        @test get_model_val_by_gen(data, model, :egen_gen, 1:2, ["y2035","y2040"], 1:3) ≈ 
            get_model_val_by_gen(data, model, :egen_gen, 1, 2:3, [1,2,3]) + 
            get_model_val_by_gen(data, model, :egen_gen, 2, 2:3, 1) +
            get_model_val_by_gen(data, model, :egen_gen, 2, 2:3, 2) +
            get_model_val_by_gen(data, model, :egen_gen, 2, 2:3, 3)

        @test get_model_val_by_gen(data, model, :egen_gen) ≈ get_model_val_by_gen(data, model, :egen_gen, :)
        @test get_model_val_by_gen(data, model, :egen_gen, :genfuel=>"ng") ≈
            get_model_val_by_gen(data, model, :egen_gen, (:genfuel=>"ng", :country=>"narnia")) + 
            get_model_val_by_gen(data, model, :egen_gen, (:genfuel=>"ng", :country=>"archenland"))
        
    end
end