config_file = joinpath(@__DIR__, "config", "config_3bus.yml")

function test_dcopf(config)
    data = load_data(config)
    model = setup_model(config, data)
    @test model isa JuMP.Model


    # variables have been added to the objective 
    @test haskey(data[:obj_vars], :fom)
    @test haskey(data[:obj_vars], :fuel_cost)
    @test haskey(data[:obj_vars], :vom)
    @test haskey(data[:obj_vars], :capex_obj)
    @test haskey(data[:obj_vars], :curtailment_cost)
    @test model[:obj] == sum(model[:curtailment_cost]) + sum(model[:fom]) + sum(model[:fuel_cost]) + sum(model[:vom]) + sum(model[:capex_obj]) #this won't be a good system level test



    optimize!(model)
    # solution_summary(model)

    @test check(model)

    # No curtailment 
    bus = get_bus_table(data)
    years = get_years(data)
    rep_hours = get_hours_table(data)
    total_pserv = sum(rep_hours.hours[hour_idx].*value.(model[:pserv_bus][bus_idx, year_idx, hour_idx]) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    total_dl = sum(rep_hours.hours[hour_idx].*get_bus_value(data, :pdem, bus_idx, year_idx, hour_idx) for bus_idx in 1:nrow(bus), year_idx in 1:length(years), hour_idx in 1:nrow(rep_hours))
    @test total_pserv ≈ total_dl
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
    @test get_build_gen_table(data) isa DataFrame
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
            return
        end
        function E4ST.modify_setup_data!(::DoubleVOM, config, data)
            data[:gen][!, :vom] .*= 2
        end
        config = load_config(config_file)
        data_0 = load_data(config)
        push!(config[:mods], :testmod=>DoubleVOM())
        @test ~isempty(config[:mods])
        data = load_data(config)
        @test data != data_0
        @test sum(data[:gen].vom) == 2*sum(data_0[:gen].vom)

        #TODO: Create test Mod that applied in modify_raw_data!

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

    @testset "Test Adding New Gens" begin
        config = load_config(config_file)
        data = load_data(config)
        gen = get_gen_table(data)
        build_gen = get_build_gen_table(data)

        @test "endog" in gen.build_type
        @test "unbuilt" in gen.build_status
        for gen_row in eachrow(gen)
            gen_row.build_status == "unbuilt" && @test gen_row.pcap0 == 0
        end

        "new" in build_gen.build_status && @test "new" in gen.build_status

        #check that all gentypes in build_gen are in gen as well
        @test nothing ∉ indexin(unique(build_gen.gentype), unique(gen.gentype))
        


    end
end



@testset "Test Setting up the model" begin
    config = load_config(config_file)
    test_dcopf(config)
end

@testset "Test adding a Mod with constraint" begin
    """

    """
    struct GenerationCap <: Policy
        name::Symbol
        column::Symbol
        targets::OrderedDict{String, Float64}
        function GenerationCap(;name, column, targets)
            new_targets = OrderedDict(String(k)=>v for (k,v) in targets)
            return new(Symbol(name), Symbol(column), new_targets)
        end
    end
    function E4ST.modify_model!(pol::GenerationCap, config, data, model)
        gen = get_gen_table(data)
        gen_idxs = 1:nrow(gen)

        years = get_years(data)
        pol_years = collect(keys(pol.targets))
        filter!(in(years), pol_years)
        caps = collect(values(pol.targets))
        col = pol.column
        cons_name = "cons_$(pol.name)"
        model[Symbol(cons_name)] = @constraint(model, 
            [y=pol_years], 
            sum(get_egen_gen(data, model, gen_idx, findfirst(==(y), years))*gen[gen_idx, col] for gen_idx in gen_idxs) <= pol.targets[y]
        )
    end
    
    config_file = joinpath(@__DIR__, "config", "config_3bus_emis_cap.yml")
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    
    @test haskey(model, :cons_co2_cap)

    optimize!(model)

    cap_prices = shadow_price.(model[:cons_co2_cap])
    @test abs(cap_prices["y2030"]) < 1
    @test abs(cap_prices["y2035"]) > 1
    @test abs(cap_prices["y2040"]) > 1

    @test get_gen_result(data, model, PerMWhGen(), :emis_co2, :, "y2030") <= config[:mods][:co2_cap].targets["y2030"] + 1e-6
    @test get_gen_result(data, model, PerMWhGen(), :emis_co2, :, "y2035") <= config[:mods][:co2_cap].targets["y2035"] + 1e-6
    @test get_gen_result(data, model, PerMWhGen(), :emis_co2, :, "y2040") <= config[:mods][:co2_cap].targets["y2040"] + 1e-6

end

# get_gen_result(data, model, PerMWhGen(), :emis_co2, gen_idx, yr_idx, hr_idx)


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

@testset "Test loading/saving data from .jls file" begin
    config = load_config(config_file)
    config[:out_path] = "out/3bus1"
    E4ST.make_out_path!(config)
    data1 = load_data(config)

    # Check that it is trying to load in the data file
    config[:data_file] = "out/3bus1/blah.jls"
    @test_throws Exception load_data(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:data_file] = "out/3bus1/data.jls"
    config[:demand_file] = "blah.csv"
    data2 = load_data(config)
    @test data1 == data2
end

@testset "Test loading/saving model from .jls file" begin
    config = load_config(config_file)
    config[:out_path] = "out/3bus1"
    E4ST.make_paths_absolute!(config, config_file)
    E4ST.make_out_path!(config)
    data = load_data(config)
    model1 = setup_model(config, data)

    # Check that it is trying to load in the model file
    config[:model_presolve_file] = "bad/path/to/blah.jls"
    @test_throws Exception setup_model(config)

    # Check that data file is loaded in and identical.  Also check that other files aren't touched
    config[:model_presolve_file] = "out/3bus1/model_presolve.jls"
    E4ST.make_paths_absolute!(config, config_file)
    model2 = setup_model(config, data)
    optimize!(model1)
    optimize!(model2)
    @test value.(model1[:θ_bus]) ≈ value.(model2[:θ_bus])
end

@testset "Test get_gen_result access" begin
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    
    @testset "Test gen_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        
        # Provide a function for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :emis_co2 => <=(0.1)) + get_gen_result(data, model, PerMWhGen(), :emis_co2 => >(0.1))

        # Provide a region for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :country => "narnia") + get_gen_result(data, model, PerMWhGen(), :country => !=("narnia"))

        # Provide a tuple for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :vom => (0,1.1) ) + get_gen_result(data, model, PerMWhGen(), :vom => (1.1,Inf))

        # Provide a set for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), :genfuel => in(["ng", "coal"]) ) + get_gen_result(data, model, PerMWhGen(), :genfuel => !in(["ng", "coal"]))
        
        # Provide an index(es) for filtering
        @test tot == get_gen_result(data, model, PerMWhGen(), 1 ) + get_gen_result(data, model, PerMWhGen(), 2:nrow(data[:gen]))
    end

    @testset "Test year_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        nyr = get_num_years(data)

        # Year index
        @test tot == get_gen_result(data, model, PerMWhGen(), :, 1) + get_gen_result(data, model, PerMWhGen(), :, 2:nyr)

        # Year string
        @test tot == get_gen_result(data, model, PerMWhGen(), :, "y2030") + get_gen_result(data, model, PerMWhGen(), :, ["y2035", "y2040"])
        
        # Range of years
        @test tot == get_gen_result(data, model, PerMWhGen(), :, ("y2020", "y2031")) + get_gen_result(data, model, PerMWhGen(), :, ("y2032","y2045"))

        # Test function of years
        @test tot == get_gen_result(data, model, PerMWhGen(), :, <=("y2031")) + get_gen_result(data, model, PerMWhGen(), :, >("y2031"))
    end

    @testset "Test hour_idx filters" begin
        tot = get_gen_result(data, model, PerMWhGen())
        nhr = get_num_hours(data)

        # Hour index
        @test tot == get_gen_result(data, model, PerMWhGen(), :, :, 1) + get_gen_result(data, model, PerMWhGen(), :, :, 2:nhr)

        # Hour table label
        @test tot == get_gen_result(data, model, PerMWhGen(), :, :, (:time_of_day=>"morning", :season=>"summer")) + 
            get_gen_result(data, model, PerMWhGen(), :, :, (:time_of_day=>"morning", :season=>!=("summer"))) +
            get_gen_result(data, model, PerMWhGen(), :, :, :time_of_day=>!=("morning"))
            
    end

end