@testset "Test Basic Policy Types" begin
    tol = 1e-6
    # Test basic poltypes 
    # Includes PTC, ITC, ...

    # Setup reference case 
    ####################################################################
    config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
    config_file_res = joinpath(@__DIR__, "config", "config_res.yml")
    #config_ref = read_config(config_file_ref, config_file_res)
    config_ref = read_config(config_file_ref)

    data_ref = read_data(config_ref)
    model_ref = setup_model(config_ref, data_ref)

    optimize!(model_ref)

    parse_results!(config_ref, data_ref, model_ref)
    process_results!(config_ref, data_ref)


    # Policy tests
    #####################################################################

    @testset "Test PTC" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        model = setup_model(config, data)

        gen = get_table(data, :gen)

        @testset "Adding PTC to gen table" begin
            @test hasproperty(gen, :example_ptc)

            @test hasproperty(gen, :example_ptc_capex_adj)

            #test that there are byYear containers 
            @test gen.example_ptc isa Vector{<:Container}

            @test any(ptc -> typeof(ptc) == E4ST.ByYear, gen.example_ptc)

            # test that ByYear containers have non zero values
            @test sum(ptc -> sum(ptc.v), gen.example_ptc) > 0

            #TODO: test that only has byYear for qualifying gens 
        end

        @testset "Adding PTC to model" begin
            #test that PTC is added to the obj 
            @test haskey(data[:obj_vars], :example_ptc)
            @test haskey(model, :example_ptc)

            #test that PTC capex adj has been added to the model
            @test haskey(data[:obj_vars], :example_ptc_capex_adj)
            @test haskey(model, :example_ptc_capex_adj)

            # Test that all the capex adjustments are positive and are added to the objective as a cost
            @test ~anyany(<(0), gen.example_ptc_capex_adj)
            @test data[:obj_vars][:example_ptc_capex_adj][:term_sign] == (+)
            @test ~anyany(<(0), gen.example_ptc)
            @test data[:obj_vars][:example_ptc][:term_sign] == (-)

            #check that no capex_adj gets added when no age filter provided
            @test !haskey(data[:obj_vars], :example_ptc_no_age_filter_capex_adj)
            @test !haskey(model, :example_ptc_no_age_filter_capex_adj)

            #make sure model still optimizes 
            optimize!(model)
            @test check(config, data, model)
            parse_results!(config, data, model)
            process_results!(config, data)

            #make sure obj was lowered
            @test sum(get_raw_result(data, :obj)) < sum(get_raw_result(data_ref, :obj)) #if this isn't working, check that it isn't due to differences between the config files
        
            #test that results are getting calculated
            @test compute_result(data, :gen, :example_ptc_cost) > 0.0

            #test getting cf_hist for missing gentype 
            @test get_gentype_cf_hist("other") == 0.67

        end

    end

    @testset "Test PTC with no cf_hist" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus_ptc.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        gen = get_table(data, :gen)

        #remove cf_hist
        select!(gen, Not(:cf_hist))
        deleteat!(data[:gen_table_original_cols], findall(x->x==:cf_hist, data[:gen_table_original_cols]))

        model = setup_model(config, data)

        #test that PTC is added to the obj 
        @test haskey(data[:obj_vars], :example_ptc)
        @test haskey(model, :example_ptc)

        #test that PTC capex adj has been added to the model
        @test haskey(data[:obj_vars], :example_ptc_capex_adj)
        @test haskey(model, :example_ptc_capex_adj)

        #check that no capex_adj gets added when no age filter provided
        @test !haskey(data[:obj_vars], :example_ptc_no_age_filter_capex_adj)
        @test !haskey(model, :example_ptc_no_age_filter_capex_adj)

        #make sure model still optimizes 
        optimize!(model)
        @test check(config, data, model)
        parse_results!(config, data, model)
        process_results!(config, data)

        #make sure obj was lowered
        @test sum(get_raw_result(data, :obj)) < sum(get_raw_result(data_ref, :obj)) #if this isn't working, check that it isn't due to differences between the config files
        
        #test that results are getting calculated
        @test compute_result(data, :gen, :example_ptc_cost) > 0.0


    end


    @testset "Test ITC" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus_itc.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        model = setup_model(config, data)

        gen = get_table(data, :gen)

        @testset "Adding ITC to gen table" begin
            @test hasproperty(gen, :example_itc)

            # Test that there are byYear containers 
            @test gen.example_itc isa Vector{<:Container}

            # Check that there are ByYear containers
            @test any(itc -> typeof(itc) == E4ST.ByYear, gen.example_itc)

            # test that ByYear containers have non zero values
            @test sum(itc -> sum(itc.v), gen.example_itc) > 0
        end

        @testset "Adding ITC to the model" begin
            #test that ITC is added to the obj 
            @test haskey(data[:obj_vars], :example_itc)
            @test haskey(model, :example_itc)

            #make sure model still optimizes 
            optimize!(model)
            @test check(config, data, model)
            parse_results!(config, data, model)
            process_results!(config, data)

            #make sure obj was lowered
            @test sum(get_raw_result(data, :obj)) < sum(get_raw_result(data_ref, :obj)) #if this isn't working, check that it isn't due to differences between the config files

            #test _cost_obj result is calculated
            cost_obj = compute_result(data, :gen, :example_itc_cost_obj)
            @test cost_obj > 0.0
        end
    end


    @testset "Test EmissionCap" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus_emiscap.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        model = setup_model(config, data)

        gen = get_table(data, :gen)

        @testset "Saving correctly to the config" begin
            # read back into config yaml without the gen_cons
            save_config(config)

            outfile = get_out_path(config, "config.yml")
            savedconfig = YAML.load_file(outfile, dicttype=OrderedDict{Symbol,Any})
            savedmods = savedconfig[:mods]

            @test haskey(savedmods, :example_emiscap)

            emiscap = savedmods[:example_emiscap]
            @test ~haskey(emiscap, :gen_cons)
        end

        @testset "Add constraint to model" begin
            # Creates GenerationConstraint
            @test typeof(config[:mods][:example_emiscap][:gen_cons]) == E4ST.GenerationConstraint


            # Added to the gen table 
            @test hasproperty(gen, :example_emiscap)
            for i in 1:nrow(gen)
                @test all(==(true), gen[i, :example_emiscap])
            end


            # Constraint added to the model
            @test haskey(model, :cons_example_emiscap_max)

        end

        @testset "Model optimizes correctly" begin
            ## make sure model still optimizes 
            optimize!(model)
            @test check(config, data, model)


            parse_results!(config, data, model)
            process_results!(config, data)

            ## Check that policy impacts results 
            gen = get_table(data, :gen)
            years = get_years(data)
            emis_co2_total = compute_result(data, :gen, :emis_co2_total, :, [2, 3])


            gen_ref = get_table(data_ref, :gen)
            emis_co2_total_ref = compute_result(data_ref, :gen, :emis_co2_total, :, [2, 3])

            # check that emissions are reduced
            @test emis_co2_total < emis_co2_total_ref

            # check that yearly cap values are actually followed
            idx_2035 = get_year_idxs(data, "y2035")
            emis_co2_total_2035 = compute_result(data, :gen, :emis_co2_total, :, idx_2035)

            @test emis_co2_total_2035 <= config[:mods][:example_emiscap][:targets][:y2035] + 0.001


            idx_2040 = get_year_idxs(data, "y2040")
            emis_co2_total_2040 = compute_result(data, :gen, :emis_co2_total, :, idx_2040)

            @test emis_co2_total_2040 <= config[:mods][:example_emiscap][:targets][:y2040] + 0.001

            #check that policy is binding 
            cap_prices = get_raw_result(data, :cons_example_emiscap_max)

            @test abs(cap_prices[2]) + abs(cap_prices[3]) > tol # At least one will be binding, but potentially not both bc of perfect foresight

            #check that results are calculated
            @test hasproperty(gen, :example_emiscap_prc)
            @test sum(prc -> sum(prc.v), gen.example_emiscap_prc) > 0
            @test compute_result(data, :gen, :example_emiscap_cost) > 0

            @test compute_result(data, :gen, :emis_co2_total, :, 1, :season=>"summer") ≈ 1000
        end
    end

    @testset "Test Emission Price" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus_emisprc.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        model = setup_model(config, data)

        gen = get_table(data, :gen)

        @testset "Adding Emis Prc to gen table" begin
            @test hasproperty(gen, :example_emisprc)

            # Test that there are byYear containers 
            @test typeof(gen.example_emisprc) == Vector{Container}

            # Check that there are ByYear containers
            @test any(emisprc -> typeof(emisprc) == E4ST.ByYear, gen.example_emisprc)

            # test that ByYear containers have non zero values
            @test sum(emisprc -> sum(emisprc.v), gen.example_emisprc) > 0
        end

        @testset "Adding Emis Prc to the model" begin
            #test that emis prc is added to the obj 
            @test haskey(data[:obj_vars], :example_emisprc)
            @test haskey(model, :example_emisprc)

            #make sure model still optimizes 
            optimize!(model)
            @test check(config, data, model)

            # process results
            parse_results!(config, data, model)
            process_results!(config, data)

            ## Check that policy impacts results 
            gen = get_table(data, :gen)
            years = get_years(data)
            emis_prc_mod = config[:mods][:example_emisprc]
            emis_co2_total = compute_result(data, :gen, :emis_co2_total, parse_comparisons(emis_prc_mod.gen_filters))

            gen_ref = get_table(data_ref, :gen)
            emis_co2_total_ref = compute_result(data_ref, :gen, :emis_co2_total, parse_comparisons(emis_prc_mod.gen_filters))

            # check that emissions are reduced for qualifying gens
            @test emis_co2_total < emis_co2_total_ref


            # Test that all the capex adjustments are positive and are subtracted from the objective as a cost
            @test ~anyany(<(0), gen.example_emisprc_capex_adj)
            @test data[:obj_vars][:example_emisprc_capex_adj][:term_sign] == (-)
            @test ~anyany(<(0), gen.example_emisprc)
            @test data[:obj_vars][:example_emisprc][:term_sign] == (+)

            #test that cost restult is calculated
            pol = config[:mods][:example_emisprc]
            gen_idxs = get_row_idxs(gen, parse_comparisons(pol.gen_filters))

            #@show compute_result(data, :gen, :egen_total, gen_idxs, [2, 3])
            @test emis_co2_total > 0
            @test compute_result(data, :gen, :example_emisprc_cost) > 0.0


            summer_co2_cost = compute_result(data, :gen, :summer_co2_price_cost, :, :, :season=>"summer")
            total_co2_cost = compute_result(data, :gen, :summer_co2_price_cost)

            @test summer_co2_cost > 0
            @test total_co2_cost ≈ summer_co2_cost
        end
    end


    @testset "Test Generation Standards" begin

        @testset "Test RPS" begin

            config_file = joinpath(@__DIR__, "config", "config_3bus_rps.yml")
            config = read_config(config_file_ref, config_file)

            data = read_data(config)
            model = setup_model(config, data)
            gen = get_table(data, :gen)

            #test that sorting happened correctly 
            ranks = list_mod_ranks(config)
            @test ranks[:example_rps] > 0.0

            @testset "Test Crediting RPS" begin
                # columns added to the gen table
                @test hasproperty(gen, :example_rps)
                @test hasproperty(gen, :example_rps_gentype)

                # check that some crediting was applied
                @test any(credit -> any(>(0.0),credit), gen[!, :example_rps])
                @test any(credit -> any(>(0.0),credit), gen[!, :example_rps_gentype])

                @test ~any(credit -> any(x -> x > (1.0) || x < (0.0), credit), gen[!, :example_rps])
                @test ~any(credit -> any(x -> x > (1.0) || x < (0.0), credit), gen[!, :example_rps_gentype])
            end

            @testset "Adding RPS to model" begin

                #make sure model still optimizes 
                optimize!(model)
                @test check(config, data, model)

                @test haskey(model, :pl_gs_bus)
                @test haskey(model, :cons_example_rps)
                @test haskey(model, :cons_example_rps_gentype)

                # process results
                parse_results!(config, data, model)
                process_results!(config, data)

                ## Check that policy is binding
                rps_prices = get_raw_result(data, :cons_example_rps)
                rps_gentype_prices = get_raw_result(data, :cons_example_rps_gentype)


                @test abs(rps_prices[2]) + abs(rps_prices[3]) > tol
                # @test abs(rps_gentype_prices[:y2035]) + abs(rps_gentype_prices[:y2040]) > tol

                ## Check that policy impacts results for example_rps (other rps isn't binding)
                rps_mod = config[:mods][:example_rps]

                gen = get_table(data, :gen)

                gen_total_qual = compute_result(data, :gen, :egen_total, [:emis_co2 => 0, :bus_nation => "archenland"])
                elserv_total_qual = compute_result(data, :bus, :elserv_total, :state => "stormness")

                gen_total_qual_2035 = compute_result(data, :gen, :egen_total, [:emis_co2 => 0, :bus_nation => "archenland"], 2)
                elserv_total_qual_2035 = compute_result(data, :bus, :el_gs_total, :state => "stormness", 2)

                targets = first(values(rps_mod.load_targets))[:targets]

                @test gen_total_qual_2035 / elserv_total_qual_2035 >= targets[:y2035] - tol

                gen_total_qual_2040 = compute_result(data, :gen, :egen_total, [:emis_co2 => 0, :bus_nation => "archenland"], 3)
                elserv_total_qual_2040 = compute_result(data, :bus, :el_gs_total, :state => "stormness", 3)

                @test gen_total_qual_2040 / elserv_total_qual_2040 >= targets[:y2040] - tol

                gen_ref = get_table(data_ref, :gen)
                gen_total_ref = compute_result(data_ref, :gen, :egen_total, :emis_co2 => 0)

                # check that generation is increased for qualifying gens
                @test gen_total_qual > gen_total_ref


                #check that result processed
                @test hasproperty(gen, :example_rps_prc)
                @test hasproperty(gen, :example_rps_gentype_prc)
                @test sum(prc -> sum(prc.v), gen.example_rps_prc) > 0
                @test sum(prc -> sum(prc.v), gen.example_rps_gentype_prc) > 0

                @test compute_result(data, :gen, :example_rps_cost) > 0.0
                @test compute_result(data, :gen, :example_rps_gentype_cost) > 0.0


            end

        end

        @testset "Test CES" begin

            config_file = joinpath(@__DIR__, "config", "config_3bus_ces.yml")
            config = read_config(config_file_ref, config_file)

            data = read_data(config)
            gen = get_table(data, :gen)
            model = setup_model(config, data)

            nyears = get_num_years(data)

            @testset "Test Crediting CES" begin
                # columns added to the gen table
                @test hasproperty(gen, :example_ces)

                # check that some crediting was applied
                @test any(credit -> any(>(0.0), credit), gen[!, :example_ces])

                @test ~any(credit -> any(x -> x > (1.0) || x < (0.0), credit), gen[!, :example_ces])

                fossil_gen = get_subtable(gen, :genfuel => ["coal", "ng", "oil"])
                @test ~any(credit -> any(x -> x != 0, credit), fossil_gen[:, :example_ces])

            end

            @testset "Adding CES to model" begin
                #make sure model still optimizes 
                optimize!(model)
                @test check(config, data, model)

                @test haskey(model, :pl_gs_bus)
                @test haskey(model, :cons_example_ces)

                # process results
                parse_results!(config, data, model)
                process_results!(config, data)

                ## Check that policy is binding
                ces_prices = get_raw_result(data, :cons_example_ces)
                @test abs(ces_prices[2]) + abs(ces_prices[3]) > tol

                ## Check that CES correctly impacts results
                ces_mod = config[:mods][:example_ces]
                targets = first(values(ces_mod.load_targets))[:targets]

                gen_total_qual_2035 = compute_result(data, :gen, :egen_total, [:emis_co2 => <(0.5), :bus_nation => "archenland"], 2)
                gen_total_qual_2035_ref = compute_result(data_ref, :gen, :egen_total, [:emis_co2 => <(0.5), :bus_nation => "archenland"], 2)
                elserv_total_qual_2035 = compute_result(data, :bus, :el_gs_total, :state => "anvard", 2)

                @test gen_total_qual_2035 > gen_total_qual_2035_ref
                @test gen_total_qual_2035 / elserv_total_qual_2035 >= targets[:y2035] - 0.001 #would use approx but need the > in case partial credit gen is used

                gen_total_qual_2040 = compute_result(data, :gen, :egen_total, [:emis_co2 => <(0.5), :bus_nation => "archenland"], 3)
                gen_total_qual_2040_ref = compute_result(data_ref, :gen, :egen_total, [:emis_co2 => <(0.5), :bus_nation => "archenland"], 3)
                elserv_total_qual_2040 = compute_result(data, :bus, :el_gs_total, :state => "anvard", 3)

                @test gen_total_qual_2040 > gen_total_qual_2040_ref
                @test gen_total_qual_2040 / elserv_total_qual_2040 >= targets[:y2040] - 0.001 #would use approx but need the > in case partial credit gen is used

                #test that results are calculated 
                @test hasproperty(gen, :example_ces_prc)
                @test sum(prc -> sum(prc.v), gen.example_ces_prc) > 0
                @test compute_result(data, :gen, :example_ces_cost) > 0.0

            end

        end

    end

    @testset "Test CostAdder" begin
        # test with unscaled obj function because perfect foresight model might behave differently when cost adders are introduced
        config_file = joinpath(@__DIR__, "config", "config_cost_adders.yml")
        config_stor_file = joinpath(@__DIR__, "config", "config_stor.yml")
        config = read_config(config_file_ref, 
            config_stor_file, 
            config_file
        )
        data = read_data(config)
        model = setup_model(config, data)

        
        config_ref = read_config(config_file_ref,
            config_stor_file
        )
        data_ref = read_data(config_ref)
        model_ref = setup_model(config_ref, data_ref)

        obj = model[:obj_unscaled]
        pcap_gen = model[:pcap_gen]
        pgen_gen = model[:pgen_gen]
        pcap_stor = model[:pcap_stor]
        pdischarge_stor = model[:pdischarge_stor]

        obj_ref = model_ref[:obj_unscaled]
        pcap_gen_ref = model_ref[:pcap_gen]
        pgen_gen_ref = model_ref[:pgen_gen]
        pcap_stor_ref = model_ref[:pcap_stor]
        pdischarge_stor_ref = model_ref[:pdischarge_stor]
        
        yrs = get_years(data)
        nyr = get_num_years(data)
        nhr = get_num_hours(data)
        hr_weights = get_hour_weights(data)
        hr_weights_total = sum(hr_weights)

        

        @testset "Test variable generation CostAdder" begin
            ca = config[:mods][:ca_gen_var]
            row_idxs = get_table_row_idxs(data, ca.table_name, parse_comparisons(ca.filters))
            vals = ca.values
            table = get_table(data, ca.table_name)
            
            for (yr_idx, yr) in enumerate(yrs)
                val = vals[Symbol(yr)]
                for hr_idx in 1:nhr, row_idx in row_idxs
                    @test obj[yr_idx][pgen_gen[row_idx, yr_idx, hr_idx]] ≈ 
                    table[row_idx, ca.col_name][yr_idx, hr_idx] * val * hr_weights[hr_idx] + obj_ref[yr_idx][pgen_gen_ref[row_idx, yr_idx, hr_idx]]  
                end
            end
        end

        @testset "Test variable storage CostAdder" begin
            ca = config[:mods][:ca_stor_var]
            row_idxs = get_table_row_idxs(data, ca.table_name, parse_comparisons(ca.filters))
            vals = ca.values
            
            for (yr_idx, yr) in enumerate(yrs)
                val = vals[Symbol(yr)]
                for hr_idx in 1:nhr, row_idx in row_idxs
                    @test obj[yr_idx][pdischarge_stor[row_idx, yr_idx, hr_idx]] ≈
                    val * hr_weights[hr_idx] + obj_ref[yr_idx][pdischarge_stor_ref[row_idx, yr_idx, hr_idx]] 
                end
            end
        end

        @testset "Test fixed generation CostAdder" begin
            ca = config[:mods][:ca_gen_fix]
            row_idxs = get_table_row_idxs(data, ca.table_name, parse_comparisons(ca.filters))
            vals = ca.values
            
            for (yr_idx, yr) in enumerate(yrs)
                val = vals[Symbol(yr)]
                for row_idx in row_idxs
                    @test obj[yr_idx][pcap_gen[row_idx, yr_idx]] ≈ 
                    val * hr_weights_total + obj_ref[yr_idx][pcap_gen_ref[row_idx, yr_idx]] 
                end
            end
        end

        @testset "Test fixed storage CostAdder" begin
            ca = config[:mods][:ca_stor_fix]
            row_idxs = get_table_row_idxs(data, ca.table_name, parse_comparisons(ca.filters))
            vals = ca.values
            
            for (yr_idx, yr) in enumerate(yrs)
                val = vals[Symbol(yr)]
                for row_idx in row_idxs
                    @test obj[yr_idx][pcap_stor[row_idx, yr_idx]] ≈
                    val * hr_weights_total + obj_ref[yr_idx][pcap_stor_ref[row_idx, yr_idx]] 
                end
            end
        end

        @testset "Test ResultsFormulas" begin
            E4ST.run_optimize!(config, data, model)
            parse_results!(config, data, model)
            process_results!(config, data)

            m = config[:mods][:ca_stor_fix]
            ca_stor_fix_val = hr_weights_total * sum(compute_result(data, :storage, :pcap_total, parse_comparisons(m.filters), yr_idx) * m.values[Symbol(yrs[yr_idx])] for yr_idx in 1:nyr)
            @test compute_result(data, :storage, :ca_stor_fix_total) ≈ ca_stor_fix_val
            rf = get_results_formula(data, :storage, :fixed_cost)
            contains(rf.formula, "ca_stor_fix_total")

            m = config[:mods][:ca_stor_var]
            ca_stor_var_val = sum(compute_result(data, :storage, :edischarge_total, parse_comparisons(m.filters), yr_idx) * m.values[Symbol(yrs[yr_idx])] for yr_idx in 1:nyr)
            @test compute_result(data, :storage, :ca_stor_var_total) ≈ ca_stor_var_val
            rf = get_results_formula(data, :storage, :variable_cost)
            contains(rf.formula, "ca_stor_var_total")

            m = config[:mods][:ca_gen_fix]
            ca_gen_fix_val = hr_weights_total * sum(compute_result(data, :gen, :pcap_total, parse_comparisons(m.filters), yr_idx) * m.values[Symbol(yrs[yr_idx])] for yr_idx in 1:nyr)
            @test compute_result(data, :gen, :ca_gen_fix_total) ≈ ca_gen_fix_val
            rf = get_results_formula(data, :gen, :fixed_cost)
            contains(rf.formula, "ca_gen_fix_total")

            m = config[:mods][:ca_gen_var]
            ca_gen_var_val = sum(compute_result(data, :gen, :emis_co2_total, parse_comparisons(m.filters), yr_idx) * m.values[Symbol(yrs[yr_idx])] for yr_idx in 1:nyr)
            @test compute_result(data, :gen, :ca_gen_var_total) ≈ ca_gen_var_val
            rf = get_results_formula(data, :gen, :variable_cost)
            contains(rf.formula, "ca_gen_var_total")
        end
    end

    @testset "Test ReserveRequirements" begin
        config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
        config_file = joinpath(@__DIR__, "config", "config_3bus_reserve_req.yml")
        config_stor = joinpath(@__DIR__, "config", "config_stor.yml")
        config = read_config(config_file_ref, config_file, config_stor)
        # config = read_config(config_file_ref, config_file)
        data = read_data(config)
        model = setup_model(config, data)
        optimize!(model)
        parse_results!(config, data, model)
        process_results!(config, data)
        
        @test compute_result(data, :bus, :elcurt_total) < tol
    
        # Test for narnia
        @test compute_result(data, :gen, :state_reserve_rebate, :, "y2030") == 0.0
        @test compute_result(data, :gen, :state_reserve_rebate) > 0.0
        @test compute_result(data, :gen, :state_reserve_rebate_per_mw_price) > 0.0
        @test compute_result(data, :gen, :pcap_qual_state_reserve) < compute_result(data, :gen, :pcap_total)

    
        if compute_result(data, :storage, :edischarge_total, :bus_nation=>"narnia") > 0
            @test compute_result(data, :storage, :state_reserve_rebate, :, "y2030") == 0.0
            @test compute_result(data, :storage, :state_reserve_rebate) > 0.0
            @test compute_result(data, :storage, :state_reserve_rebate_per_mw_price) > 0.0
        end

        @test compute_result(data, :state_reserve_requirements, :pres_req_sum_min) <= compute_result(data, :state_reserve_requirements, :pres_req_min)
        @test compute_result(data, :state_reserve_requirements, :pres_req_sum_max) >= compute_result(data, :state_reserve_requirements, :pres_req_max)

        @test haskey(data[:results][:raw], :pres_flow_subarea_state_reserve)

        @test compute_result(data, :bus, :state_reserve_merchandising_surplus_total) > 0.0

        @test compute_result(data, :bus, :state_reserve_cost) ≈ compute_result(data, :gen, :state_reserve_rebate) + compute_result(data, :storage, :state_reserve_rebate) + compute_result(data, :bus, :state_reserve_merchandising_surplus_total)
    
        # use welfare check to make sure that reserve requirement is working correctly
        @test compute_welfare(data, :net_rev_prelim_check) ≈ compute_result(data, :gen, :net_total_revenue_prelim) + compute_result(data, :storage, :net_total_revenue_prelim)
    end

    @testset "Test CapacityConstraint" begin
        config_file = joinpath(@__DIR__, "config", "config_capconst.yml")
        config = read_config(config_file_ref, config_file)

        data = read_data(config)
        model = setup_model(config, data)
        gen = get_table(data, :gen)

        optimize!(model)
        @test check(config, data, model)

        @test haskey(model, :cons_solar_cap_const_max)
        @test haskey(model, :cons_solar_cap_const_min)
        @test haskey(model, :cons_storage_cap_const_max)
        @test haskey(model, :cons_storage_cap_const_min)

        # process results
        parse_results!(config, data, model)
        process_results!(config, data)

        @test compute_result(data, :gen, :pcap_total, :gentype => "solar", 1) <= 0.5
        @test compute_result(data, :gen, :pcap_total, :gentype => "solar", 2) >= 0.75
        @test compute_result(data, :gen, :pcap_total, :gentype => "solar", 2) <= 0.76
        @test compute_result(data, :storage, :pcap_total, :, 3) >= 0.035
        @test compute_result(data, :storage, :pcap_total, :, 3) <= 0.040000001

        @testset "Test invalid capacity constraint due to min value bigger than max value" begin
            config_file = joinpath(@__DIR__, "config", "config_capconst_invalid_conflicting.yml")
            config = read_config(config_file_ref, config_file)

            data = read_data(config)

            @test_throws "which is less than min value" setup_model(config, data)

        end
        @testset "Test invalid capacity constraint due to min value bigger possible capacity" begin
            config_file = joinpath(@__DIR__, "config", "config_capconst_invalid_too_high.yml")
            config = read_config(config_file_ref, config_file)

            data = read_data(config)

            @test_throws "which is greater than the max capacity" setup_model(config, data)

        end
    end
end