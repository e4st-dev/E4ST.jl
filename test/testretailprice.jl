@testset "Test Retail Price" begin
    @testset "Retail Price Set Up" begin
        config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
        config_file = joinpath(@__DIR__, "config", "config_3bus_reserve_req.yml")
        config = read_config(config_file_ref, config_file, log_model_summary=true)
        config[:past_invest_file] = "data/3bus/past_invest_costs.csv"

        data = read_data(config)
        model = setup_model(config, data)

        optimize!(model)
        # solution_summary(model)

        @test check(config, data, model)

        parse_results!(config, data, model)
        process_results!(config, data)

        setup_retail_price!(config, data)

        @test haskey(data, :retail_price)

        @testset "Check Retail Price Terms" begin
            retail_price = data[:retail_price][:avg_elec_rate]

            #check retail price terms
            @test all(k -> haskey(retail_price, k), [:bus, :gen, :storage, :past_invest])
            bus_terms =  retail_price[:bus]
            @test all(k -> haskey(bus_terms, k), [:electricity_cost, :distribution_cost_total, :merchandising_surplus_comp_total, :gs_payment, :state_reserve_cost])
            gen_terms =  retail_price[:gen]
            @test haskey(gen_terms, :cost_of_service_rebate)
            storage_terms =  retail_price[:storage]
            @test haskey(storage_terms, :cost_of_service_rebate)
            past_invest_terms =  retail_price[:past_invest]
            @test haskey(past_invest_terms, :cost_of_service_past_costs)
        end

        @testset "Without Past Invest" begin
            delete!(config, :past_invest_file)

            setup_retail_price!(config, data)
            retail_price = data[:retail_price][:avg_elec_rate]
            @test !haskey(retail_price, :past_invest)

        end

        @testset "Without Reserve Requirements" begin
            delete!(config[:mods], :state_reserve)

            setup_retail_price!(config, data)

            retail_price = data[:retail_price][:avg_elec_rate]

            bus_terms =  retail_price[:bus]
            @test !haskey(bus_terms, :state_reserve_cost)
        end

    end


    @testset "Test RetailPrice Mod" begin

        @testset "Without calibration" begin
            config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
            storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
            config = read_config(config_file, storage_config_file)
            config[:past_invest_file] = "data/3bus/past_invest_costs.csv"
            data = read_data(config)
            model = setup_model(config, data)
            optimize!(model)
            parse_results!(config, data, model)
            # Make new mod
            rtlprc_file = joinpath(@__DIR__, "data/3bus/results_retail_price.csv")
            name = :retail_price
            mod = RetailPrice(;file=rtlprc_file, name)

            mods = get_mods(config)
            mods[name] = mod
            
            process_results!(config, data)
           
            results = get_results(data)
            @test haskey(results, name)
            table = get_result(data, name)
            @test table[end, :filter1] |> contains("=>")

            @test table.value[1] == compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 3,:)

            # test when filters that arent in all tables are provided
            ref_price_file = joinpath(@__DIR__, "data/3bus/ref_retail_price.csv")
            rtlprc = read_table(rtlprc_file)
            rtlprc.filter2 .= "genfuel"
            CSV.write(get_out_path(config, "results_retail_price.csv"), rtlprc)

            rtlprc_file = get_out_path(config, "results_retail_price.csv")
            mod = RetailPrice(;file=rtlprc_file, name)
            
            mods = get_mods(config)
            mods[name] = mod

            @test_throws Exception process_results!(config, data)


        end
           
        @testset "With yearly reference price" begin
            config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
            storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
            config = read_config(config_file, storage_config_file)
            data = read_data(config)
            model = setup_model(config, data)
            optimize!(model)
            parse_results!(config, data, model)

            # Make new mod
            rtlprc_file = joinpath(@__DIR__, "data/3bus/results_retail_price.csv")
            ref_price_file = joinpath(@__DIR__, "data/3bus/ref_retail_price_yearly.csv")
            name = :retail_price
            mod = RetailPrice(;file=rtlprc_file, name, ref_price_file=ref_price_file, cal_mode = "get_cal_values")

            mods = get_mods(config)
            mods[name] = mod

            process_results!(config, data)
        
            results = get_results(data)
            table = get_result(data, name)

            @test isfile(get_out_path(config, "$(name)_cals.csv"))

            @test table.value[2] == compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 2,:)[1]

            cal_table = get_result(data, :calibrator_values)
            ref_price = read_table(ref_price_file)
            @test filter(row->row.subarea==3 && row.year=="y2035", ref_price)[1,"ref_price"] - compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 2,:)[1] == filter(row->row.subarea=="3" && row.year=="y2035", cal_table)[1,"cal_value"]

             # test for error when multiple filters are provided
            ref_price = read_table(ref_price_file)
            insertcols!(ref_price, 3, :filter1 => "genfuel"=>"ng")
            CSV.write(get_out_path(config, "ref_retail_price_yearly.csv"), ref_price)

            ref_price_file = get_out_path(config, "ref_retail_price_yearly.csv")
            mod = RetailPrice(;file=rtlprc_file, name, ref_price_file=ref_price_file, cal_mode = "get_cal_values")
            
            # test for error when multiple filters are provided
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, [:bus_idx=>3, :nation=>"narnia"], 1,:)

        end

        @testset "With single reference price" begin
            config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
            storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
            config = read_config(config_file, storage_config_file)
            data = read_data(config)
            model = setup_model(config, data)
            optimize!(model)
            parse_results!(config, data, model)

            # Make new mod
            rtlprc_file = joinpath(@__DIR__, "data/3bus/results_retail_price.csv")
            ref_price_file = joinpath(@__DIR__, "data/3bus/ref_retail_price.csv")
            name = :retail_price
            mod = RetailPrice(;file=rtlprc_file, name, ref_price_file=ref_price_file, cal_mode = "get_cal_values")

            mods = get_mods(config)
            mods[name] = mod

            process_results!(config, data)
        
            results = get_results(data)
            table = get_result(data, name)

            @test isfile(get_out_path(config, "$(name)_cals.csv"))
            @test table.value[3] == compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 1,:)[1]
            
            cal_table = get_result(data, :calibrator_values)
            ref_price = read_table(ref_price_file)
   
            @test filter(row->row.subarea=="3", ref_price)[1,"ref_price"] - compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 1,:)[1] == filter(row->row.subarea=="3", cal_table)[1,"cal_value"]

            # test for error when multiple grid-wide prices are provided
            ref_price = read_table(ref_price_file)
            push!(ref_price, ["","",95])
            CSV.write(get_out_path(config, "ref_retail_price.csv"), ref_price)

            ref_price_file = get_out_path(config, "ref_retail_price.csv")
            mod = RetailPrice(;file=rtlprc_file, name, ref_price_file=ref_price_file, cal_mode = "get_cal_values")
            
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 1,:)

            # test for error when multiple prices are provided for a regoin
            ref_price_file = joinpath(@__DIR__, "data/3bus/ref_retail_price.csv")
            ref_price = read_table(ref_price_file)
            push!(ref_price, ["bus_idx","3",89])
            CSV.write(get_out_path(config, "ref_retail_price.csv"), ref_price)

            ref_price_file = get_out_path(config, "ref_retail_price.csv")
            mod = RetailPrice(;file=rtlprc_file, name, ref_price_file=ref_price_file, cal_mode = "get_cal_values")
            
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 1,:)

            # test for error when multiple filters are provided
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, [:bus_idx=>3, :nation=>"narnia"], 1,:)

        end

        @testset "With yearly calibrator values" begin
            config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
            storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
            config = read_config(config_file, storage_config_file)
            data = read_data(config)
            model = setup_model(config, data)
            optimize!(model)
            parse_results!(config, data, model)

            # Make new mod
            rtlprc_file = joinpath(@__DIR__, "data/3bus/results_retail_price.csv")
            cal_file = joinpath(@__DIR__, "data/3bus/retail_price_calibrator_yearly.csv")
            name = :retail_price
            mod = RetailPrice(;file=rtlprc_file, name, calibrator_file=cal_file, cal_mode = "calibrate")

            mods = get_mods(config)
            mods[name] = mod

            process_results!(config, data)
        
            results = get_results(data)
            table = get_result(data, name)

            cal_table = read_table(cal_file)
            @test table.value[1] == compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 3,:)[1] 
           
            # check that calibrator values were added
            mod_no_calibrate =  RetailPrice(;file=rtlprc_file, name)
            @test table.value[1] == compute_retail_price(mod_no_calibrate, data, :avg_elec_rate, :bus_idx=>3, 3,:)[1] + filter(row->row.subarea==3 && row.year=="y2040", cal_table)[1,:"cal_value"]
            @test table.value[2] == compute_retail_price(mod_no_calibrate, data, :avg_elec_rate, :bus_idx=>3, 2,:)[1] + filter(row->row.subarea==3 && row.year=="y2035", cal_table)[1,:"cal_value"]

            # test for error when multiple filters are provided
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, [:bus_idx=>3, :nation=>"narnia"], 1,:)
        end


        @testset "With single calibrator value" begin
            config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
            storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
            config = read_config(config_file, storage_config_file)
            data = read_data(config)
            model = setup_model(config, data)
            optimize!(model)
            parse_results!(config, data, model)

            # Make new mod
            rtlprc_file = joinpath(@__DIR__, "data/3bus/results_retail_price.csv")
            cal_file = joinpath(@__DIR__, "data/3bus/retail_price_calibrator.csv")
            name = :retail_price
            mod = RetailPrice(;file=rtlprc_file, name, calibrator_file=cal_file, cal_mode = "calibrate")

            mods = get_mods(config)
            mods[name] = mod

            process_results!(config, data)
        
            results = get_results(data)
            table = get_result(data, name)

            cal_table = read_table(cal_file)
            @test table.value[1] == compute_retail_price(mod, data, :avg_elec_rate, :bus_idx=>3, 3,:)[1] #+ filter(row->row.subarea==3, cal_table)[1,:"cal_value"]
           
            # check that calibrator values were added
            mod_no_calibrate =  RetailPrice(;file=rtlprc_file, name)
            @test table.value[1] == compute_retail_price(mod_no_calibrate, data, :avg_elec_rate, :bus_idx=>3, 3,:)[1] + filter(row->row.subarea==3, cal_table)[1,:"cal_value"]
            @test table.value[2] == compute_retail_price(mod_no_calibrate, data, :avg_elec_rate, :bus_idx=>3, 2,:)[1] + filter(row->row.subarea==3, cal_table)[1,:"cal_value"]

            # test for error when multiple filters are provided
            @test_throws Exception compute_retail_price(mod, data, :avg_elec_rate, [:bus_idx=>3, :nation=>"narnia"], 1,:)
        end
    end
end

# results_template_rtl_price:
#     type: RetailPrice
#     file: "../res_templates/results_template_tests_rtl_prc.csv"
#     cal_mode: calibrate
#     # ref_price_file: "../../Data/config/mods/retail_price_calibrator/retail_price_ref_values.csv"
#     calibrator_file: "L:/Project-Gurobi/Workspace3/E4ST_Output/haiku_merge/pipeflow_runs/rr_cal_251028/results_template_rtl_price_cals.csv"
