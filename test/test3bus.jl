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
    solution_summary(model)

    @test check(model)

    # No curtailment (just for this test)
    bus = get_bus_table(data)
    years = get_years(data)
    rep_hours = get_hours_table(data)
    total_pl = sum(rep_hours.hours[hour_idx].*value.(model[:pl][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    total_dl = sum(rep_hours.hours[hour_idx].*get_bus_value(data, :pd, bus_idx, year_idx, hour_idx) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    @test total_pl == total_dl
    @test all(p->abs(p)<1e-6, value.(model[:pcurt]))

    # make sure energy generated is non_zero
    gen = get_gen_table(data)

    for gen_idx in 1:nrow(gen)
        @test value.(get_eg_gen(data, model, gen_idx)) >= 0
    end
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
        initialize_data!(config, data)
        @test data == data_0
    end

    @testset "Test Initializing the Data with a mod" begin
        struct DoubleVOM <: Modification end
        function E4ST.initialize!(::DoubleVOM, config, data)
            data[:gen][!, :vom] .*= 2
        end
        config = load_config(config_file)
        push!(config[:mods], :testmod=>DoubleVOM())
        @test ~isempty(config[:mods])
        data = load_data(config)
        data_0 = deepcopy(data)
        initialize_data!(config, data)
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
        @test all(get_pd(data, 1, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
        @test all(get_pd(data, 2, yr_idx, hr_idx) ≈ 1.6 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
        @test all(get_pd(data, 3, yr_idx, hr_idx) ≈ 0.2 for yr_idx in 1:get_num_years(data), hr_idx in 1:get_num_hours(data))
    end

    @testset "Test load_demand_table! with shaping" begin
        config = load_config(config_file)
        @test_broken false
    end

    @testset "Test load_demand_table! with shaping and matching" begin
        config = load_config(config_file)
        @test_broken false
    end

    @testset "Test load_demand_table! with shaping, matching and adding" begin
        config = load_config(config_file)
        @test_broken false
    end
end

@testset "Test Setting up the model" begin
    config = load_config(config_file)
    test_dcopf(config)
end