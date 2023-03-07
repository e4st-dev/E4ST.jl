#Test setting up the model, including the dcopf



@testset "Test variables added to objective" begin

    config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    config = load_config(config_file)

    data = load_data(config)
    model = setup_model(config, data)
    @test model isa JuMP.Model

    @test haskey(data[:obj_vars], :fom)
    @test haskey(data[:obj_vars], :fuel_cost)
    @test haskey(data[:obj_vars], :vom)
    @test haskey(data[:obj_vars], :capex_obj)
    @test haskey(data[:obj_vars], :curtailment_cost)
    @test model[:obj] == sum(model[:curtailment_cost]) + sum(model[:fom]) + sum(model[:fuel_cost]) + sum(model[:vom]) + sum(model[:capex_obj]) #this won't be a good system level test
end

@testset "Test adding a Mod with constraint" begin
    """

    """
    struct TestGenerationCap <: Policy
        name::Symbol
        column::Symbol
        targets::OrderedDict{String, Float64}
        function TestGenerationCap(;name, column, targets)
            new_targets = OrderedDict(String(k)=>v for (k,v) in targets)
            return new(Symbol(name), Symbol(column), new_targets)
        end
    end
    function E4ST.modify_model!(pol::TestGenerationCap, config, data, model)
        gen = get_table(data, :gen)
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
    
    config_file = joinpath(@__DIR__, "config", "config_3bus_t_gen_cap.yml")
    config = load_config(config_file)
    data = load_data(config)
    model = setup_model(config, data)

    @test haskey(model, :cons_co2_cap)

    optimize!(model)
    res_raw = parse_results(config, data, model)
    res_user = process_results(config, data, res_raw)

    cap_prices = shadow_price.(model[:cons_co2_cap])
    @test abs(cap_prices["y2030"]) < 1
    @test abs(cap_prices["y2035"]) > 1
    @test abs(cap_prices["y2040"]) > 1

    @test aggregate_result(total, data, res_raw, :gen, :emis_co2, :, "y2030") <= config[:mods][:co2_cap].targets["y2030"] + 1e-6
    @test aggregate_result(total, data, res_raw, :gen, :emis_co2, :, "y2035") <= config[:mods][:co2_cap].targets["y2035"] + 1e-6
    @test aggregate_result(total, data, res_raw, :gen, :emis_co2, :, "y2040") <= config[:mods][:co2_cap].targets["y2040"] + 1e-6

end