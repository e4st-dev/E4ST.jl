config_file = joinpath(@__DIR__, "config", "config_3bus.yml")

function test_dcopf(config)
    data = load_data(config)
    model = setup_model(config, data)
    @test model isa JuMP.Model


    # variables have been added to the objective 
    @test haskey(data[:obj_vars], :fom)
    @test haskey(data[:obj_vars], :fuel_cost)
    @test haskey(data[:obj_vars], :vom)
    @test haskey(data[:obj_vars], :capex)
    @test haskey(data[:obj_vars], :curtailment_cost)
    @test model[:obj] == sum(model[:curtailment_cost]) + sum(model[:fom]) + sum(model[:fuel_cost]) + sum(model[:vom]) + sum(model[:capex])

    # the number of constraints matches expected
    num_cons = 3*nrow(get_bus_table(data))*length(get_years(data))*nrow(get_hours_table(data))
    num_cons += length(get_ref_bus_idxs(data))
    num_cons += 2*nrow(get_gen_table(data))*length(get_years(data))*nrow(get_hours_table(data))
    num_cons += 2*nrow(get_gen_table(data))*length(get_years(data))
    num_cons += 2*nrow(get_branch_table(data))*length(get_years(data))*nrow(get_hours_table(data))
    
    @test num_constraints(model, count_variable_in_set_constraints = false) == num_cons

    optimize!(model)
    # solution_summary(model)

    @test check(model)

    # No curtailment (just for this test)
    bus = get_bus_table(data)
    years = get_years(data)
    rep_hours = get_hours_table(data)
    total_pserv = sum(rep_hours.hours[hour_idx].*value.(model[:pserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    total_dl = sum(rep_hours.hours[hour_idx].*get_bus_value(data, :pdem, bus_idx, year_idx, hour_idx) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    @test total_pserv == total_dl
    @test all(p->abs(p)<1e-6, value.(model[:pcurt_bus]))

    # make sure energy generated is non_zero
    gen = get_gen_table(data)

    for gen_idx in 1:nrow(gen)
        @test value.(get_egen_gen(data, model, gen_idx)) >= 0
    end

    # Test the accessor methods
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


@testset "Test Loading the Config File" begin
    @test load_config(config_file) isa AbstractDict    
end

config = load_config(config_file)

@testset "Test Loading the Data" begin    
    data = load_data(config)
    @test get_gen_table(data) isa DataFrame
    @test get_bus_table(data) isa DataFrame
    @test get_branch_table(data) isa DataFrame
    @test get_hours_table(data) isa DataFrame
    @test get_num_hours(data) isa Int
    @test get_hour_weights(data) isa Vector
    @test get_num_years(data) isa Int
end

data = load_data(config)
import E4ST.Container
Base.:(==)(c1::Container, c2::Container) = c1.v==c2.v
@testset "Test Initializing the Data" begin
    @testset "Test Initializing the Data with no mods" begin
        config = load_config(config_file)
        @test isempty(config[:mods])
        data = load_data(config)
        data_0 = deepcopy(data)
        modify_raw_data!(config, data)
        @test data == data_0
    end

    @testset "Test Initializing the Data with a mod" begin
        struct DoubleVOM <: Modification end
        function E4ST.modify_raw_data!(::DoubleVOM, config, data)
            data[:gen][!, :vom] .*= 2
        end
        function E4ST.modify_setup_data!(::DoubleVOM, config, data)
            return
        end
        config = load_config(config_file)
        data_0 = load_data(config)
        push!(config[:mods], :testmod=>DoubleVOM())
        @test ~isempty(config[:mods])
        data = load_data(config)
        @test data != data_0
        @test sum(data[:gen].vom) == 2*sum(data_0[:gen].vom)
    end

    @testset "Test load_af_table!" begin
        config = load_config(config_file)
        data = load_data(config)

        # generator 1 is a natural gas plant, defaults to 1.0

        # AF not specified for ng, should be default of 1.0
        @test all(get_af(data, 1, yr_idx, hr_idx) == 1.0 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))

        # AF not specified for solar in narnia in 2030 or 2035, should be default of 1.0
        @test get_af(data, 2, 1, 1) == 1.0
        @test get_af(data, 2, 1, 2) == 1.0
        @test get_af(data, 2, 1, 3) == 1.0
        @test get_af(data, 2, 1, 4) == 1.0
        @test get_af(data, 2, 2, 1) == 1.0
        @test get_af(data, 2, 2, 2) == 1.0
        @test get_af(data, 2, 2, 3) == 1.0
        @test get_af(data, 2, 2, 4) == 1.0

        # Generator 2 is a solar generator in narnia, should be equal to 0.5 in hours 1 and 4, 0.6 in hours 2 and 3 for 2040.
        @test get_af(data, 2, 3, 1) == 0.5
        @test get_af(data, 2, 3, 2) == 0.6
        @test get_af(data, 2, 3, 3) == 0.6
        @test get_af(data, 2, 3, 4) == 0.5
    end

    @testset "Test load_demand_table!" begin
        config = load_config(config_file)
        data = load_data(config)

        # generator 1 is a natural gas plant, defaults to 1.0

        # AF not specified for ng, should be default of 1.0
        @test all(get_pdem(data, 1, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
        @test all(get_pdem(data, 2, yr_idx, hr_idx) ≈ 1.6 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
        @test all(get_pdem(data, 3, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
    end

    @testset "Test load_demand_table! with shaping" begin
        config = load_config(config_file)
        config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        data = load_data(config)
        archenland_buses = findall(==("archenland"), data[:bus].country)
        narnia_buses = findall(==("narnia"), data[:bus].country)
        all_buses = 1:nrow(data[:bus])


        # Check that narnian demanded power is different across years (look at the demand_shape.csv)
        @testset "Test that bus $bus_idx demand is different across years $yr_idx and $(yr_idx+1)" for bus_idx in narnia_buses, yr_idx in 1:get_num_years(data)-1
            @test ~all(get_pdem(data, 1, yr_idx, hr_idx) ≈ get_pdem(data, 1, yr_idx+1, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
        
        @testset "Test that bus $bus_idx demand is the same across years $yr_idx and $(yr_idx+1)" for bus_idx in archenland_buses, yr_idx in 1:get_num_years(data)-1
            @test all(get_pdem(data, bus_idx, yr_idx, hr_idx) ≈ get_pdem(data, bus_idx, yr_idx+1, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
        
        # Check that each bus changes demand across hours
        @testset "Test that bus $bus_idx demand is different across hours" for bus_idx in all_buses, yr_idx in 1:get_num_years(data)
            @test any(get_pdem(data, bus_idx, yr_idx, 1) != get_pdem(data, bus_idx, yr_idx, hr_idx) for hr_idx in 1:get_num_hours(data))
        end
    end

    @testset "Test load_demand_table! with shaping and matching" begin
        config = load_config(config_file)
        config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        config[:demand_match_file] = abspath(@__DIR__, "data", "3bus","demand_match.csv")
        data = load_data(config)
        archenland_buses = findall(==("archenland"), data[:bus].country)
        narnia_buses = findall(==("narnia"), data[:bus].country)
        all_buses = 1:nrow(data[:bus])

        # The last row, the all-area match is enabled for 2030 and 2035
        @test get_edem_demand(data, :, "y2030", :) ≈ 2.2
        @test get_edem_demand(data, :, "y2035", :) ≈ 2.3

        # In 2040, it should be equal to the naria (2.2) + the archenland match (0.22)
        @test get_edem_demand(data, :, "y2040", :) ≈ 2.53

        @testset for y in get_years(data)
            @test get_edem_demand(data, :country=>"narnia", y, :)*10 ≈ get_edem_demand(data, :country=>"archenland", y, :)
        end
    end

    @testset "Test load_demand_table! with shaping, matching and adding" begin
        config = load_config(config_file)
        config[:demand_shape_file] = abspath(@__DIR__, "data", "3bus","demand_shape.csv")
        config[:demand_match_file] = abspath(@__DIR__, "data", "3bus","demand_match.csv")
        config[:demand_add_file]   = abspath(@__DIR__, "data", "3bus","demand_add.csv")
        data = load_data(config)


        @test get_edem_demand(data, :, "y2030", :) ≈ 2.2
        @test get_edem_demand(data, :, "y2035", :) ≈ 2.3
        @test get_edem_demand(data, :, "y2040", :) ≈ 2.53 + 0.01*8760
    end
end

@testset "Test Setting up the model" begin
    config = load_config(config_file)
    test_dcopf(config)
end

@testset "Test Iteration" begin
    @testset "Test Default Iteration" begin
        results = run_e4st(config_file)
        @test results isa AbstractVector
        @test length(results) == 1
    end
    @testset "Test Custom Iteration" begin
        Base.@kwdef struct TargetAvgAnnualNGGen <: E4ST.Iterable
            target::Float64
            tol::Float64
            avg_ng_prices::Vector{Float64}=Float64[]
            avg_ng_egen::Vector{Float64}=Float64[]
        end
        E4ST.fieldnames_for_yaml(::Type{TargetAvgAnnualNGGen}) = (:target, :tol)
        function E4ST.should_iterate(iter::TargetAvgAnnualNGGen, config, data, model, results)
            tgt = iter.target
            tol = iter.tol
            ng_gen_total = get_model_val_by_gen(data, model, :egen_gen, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            return abs(ng_gen_ann-tgt) > tol            
        end
        function E4ST.iterate!(iter::TargetAvgAnnualNGGen, config, data, model, results)
            tgt = iter.target
            ng_gen_total = get_model_val_by_gen(data, model, :egen_gen, :genfuel=>"ng")
            ng_gen_ann = ng_gen_total/get_num_years(data)
            
            diff = ng_gen_ann - tgt
            gen = get_gen_table(data, :genfuel=>"ng")
            ng_price_avg = sum(gen.fuel_cost)/length(gen.fuel_cost)
            if any(≈(ng_gen_ann), iter.avg_ng_egen)
                idx = findfirst(≈(ng_gen_ann), iter.avg_ng_egen)
                iter.avg_ng_prices[idx] = ng_price_avg
            else
                push!(iter.avg_ng_prices, ng_price_avg)
                push!(iter.avg_ng_egen, ng_gen_ann)
            end

            sort!(iter.avg_ng_prices, rev=true)
            sort!(iter.avg_ng_egen)

            # Find the price difference
            if length(iter.avg_ng_prices) < 2
                ng_price_new = ng_price_avg + sign(diff) * 10.0
            else
                interp = LinearInterpolator(iter.avg_ng_egen, iter.avg_ng_prices, NoBoundaries())
                ng_price_new = interp(tgt)
            end
            ng_price_diff = ng_price_new - ng_price_avg
            gen.fuel_cost .+= ng_price_diff
            return nothing            
        end
        E4ST.should_reload_data(::TargetAvgAnnualNGGen) = false
        
        config_file = joinpath(@__DIR__, "config", "config_3bus_iter.yml")
        config = load_config(config_file)
        
        @test config[:iter] isa TargetAvgAnnualNGGen

        # TODO: test saving and loading with iter
        all_results = run_e4st(config)
        @test length(all_results) > 1
    end
end