@testset "Test Basic Policy Types" begin 
    # Test basic poltypes 
    # Includes PTC, ITC, ...

    # Setup reference case 
    ####################################################################
    config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
    config_file_res = joinpath(@__DIR__, "config", "config_res.yml")
    config_ref = read_config(config_file_ref, config_file_res)

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

            #test that there are byYear containers 
            @test typeof(gen.example_ptc) == Vector{Container}

            @test any(ptc -> typeof(ptc) == E4ST.ByYear, gen.example_ptc)
            
            # test that ByYear containers have non zero values
            @test sum(ptc->sum(ptc.v), gen.example_ptc) > 0

            #TODO: test that only has byYear for qualifying gens 
        end

        @testset "Adding PTC to model" begin
            #test that PTC is added to the obj 
            @test haskey(data[:obj_vars], :example_ptc)
            @test haskey(model, :example_ptc) 

            #make sure model still optimizes 
            optimize!(model)
            @test check(model)
            parse_results!(config, data, model)

            #make sure obj was lowered
            @test get_raw_result(data, :obj) < get_raw_result(data_ref, :obj) #if this isn't working, check that it isn't due to differences between the config files
        end

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
            @test typeof(gen.example_itc) == Vector{Container}

            # Check that there are ByYear containers
            @test any(itc -> typeof(itc) == E4ST.ByYear, gen.example_itc)
            
            # test that ByYear containers have non zero values
            @test sum(itc->sum(itc.v), gen.example_itc) > 0
        end

        @testset "Adding ITC to the model" begin
            #test that ITC is added to the obj 
            @test haskey(data[:obj_vars], :example_itc)
            @test haskey(model, :example_itc) 

            #make sure model still optimizes 
            optimize!(model)
            @test check(model)
            parse_results!(config, data, model)

            #make sure obj was lowered
            @test get_raw_result(data, :obj) < get_raw_result(data_ref, :obj) #if this isn't working, check that it isn't due to differences between the config files

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

            outfile = get_out_path(config,"config.yml")
            savedconfig = YAML.load_file(outfile, dicttype=OrderedDict{Symbol, Any})
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
                @test gen[i, :example_emiscap] == true
            end


            # Constraint added to the model
            @test haskey(model, :cons_example_emiscap_max)

        end

        @testset "Model optimizes correctly" begin
            ## make sure model still optimizes 
            optimize!(model)
            @test check(model)


            parse_results!(config, data, model)
            process_results!(config, data)

            ## Check that policy impacts results 
            gen = get_table(data, :gen)
            years = get_years(data)
            emis_co2_total = aggregate_result(total, data, :gen, :emis_co2, :, [2,3])


            gen_ref = get_table(data_ref, :gen)
            emis_co2_total_ref = aggregate_result(total, data_ref, :gen, :emis_co2, :, [2,3])

            # check that emissions are reduced
            @test emis_co2_total < emis_co2_total_ref

            # check that yearly cap values are actually followed
            idx_2035 = get_year_idxs(data, "y2035")
            emis_co2_total_2035 = aggregate_result(total, data, :gen, :emis_co2, :, idx_2035)

            @test emis_co2_total_2035 <= config[:mods][:example_emiscap][:targets][:y2035] + 0.001
            

            idx_2040 = get_year_idxs(data, "y2040")
            emis_co2_total_2040 = aggregate_result(total, data, :gen, :emis_co2, :, idx_2040)

            @test emis_co2_total_2040 <= config[:mods][:example_emiscap][:targets][:y2040] + 0.001
            

            

            #check that policy is binding 
            cap_prices = get_raw_result(data, :cons_example_emiscap_max)

            @test abs(cap_prices[:y2035]) + abs(cap_prices[:y2040]) > 1e-6 # At least one will be binding, but potentially not both bc of perfect foresight

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
                @test sum(emisprc->sum(emisprc.v), gen.example_emisprc) > 0
            end

            @testset "Adding Emis Prc to the model" begin
                #test that emis prc is added to the obj 
                @test haskey(data[:obj_vars], :example_emisprc)
                @test haskey(model, :example_emisprc) 

                #make sure model still optimizes 
                optimize!(model)
                @test check(model)

                # process results
                parse_results!(config, data, model)
                process_results!(config, data)

                ## Check that policy impacts results 
                gen = get_table(data, :gen)
                years = get_years(data)
                emis_prc_mod = config[:mods][:example_emisprc]
                emis_co2_total = aggregate_result(total, data, :gen, :emis_co2, parse_comparisons(emis_prc_mod.gen_filters))

                gen_ref = get_table(data_ref, :gen)
                emis_co2_total_ref = aggregate_result(total, data_ref, :gen, :emis_co2, parse_comparisons(emis_prc_mod.gen_filters))

            # check that emissions are reduced for qualifying gens
            @test emis_co2_total < emis_co2_total_ref
        end
    end


    @testset "Test Generation Standards" begin

        @testset "Test RPS" begin

            config_file = joinpath(@__DIR__, "config", "config_3bus_rps.yml")
            config = read_config(config_file_ref, config_file_res, config_file)

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
                @test any(credit -> get_original(credit) > 0.0, gen[!,:example_rps])
                @test any(credit -> get_original(credit) > 0.0, gen[!,:example_rps_gentype])

                @test ~any(credit -> get_original(credit) > 1.0 || get_original(credit) < 0.0, gen[!,:example_rps])
                @test ~any(credit -> get_original(credit) > 1.0 || get_original(credit) < 0.0, gen[!,:example_rps_gentype])

            end 

            @testset "Adding RPS to model" begin

                #make sure model still optimizes 
                optimize!(model)
                @test check(model)
                
                @test haskey(model, :pl_gs_bus)
                @test haskey(model, :cons_example_rps)
                @test haskey(model, :cons_example_rps_gentype)

                # process results
                parse_results!(config, data, model)
                process_results!(config, data)

                ## Check that policy is binding
                rps_prices = get_raw_result(data, :cons_example_rps)
                rps_gentype_prices = get_raw_result(data, :cons_example_rps_gentype)


                @test abs(rps_prices[:y2035]) + abs(rps_prices[:y2040]) > 1e-6
                # @test abs(rps_gentype_prices[:y2035]) + abs(rps_gentype_prices[:y2040]) > 1e-6 

                ## Check that policy impacts results for example_rps (other rps isn't binding)
                rps_mod = config[:mods][:example_rps]

                gen = get_table(data, :gen)

                gen_total_qual = aggregate_result(total, data, :gen, :egen, [:emis_co2=>0, :country=>"archenland"])
                eserv_total_qual = aggregate_result(total, data, :bus, :eserv, :state=>"stormness")

                @show gen_total_qual_2035 = aggregate_result(total, data, :gen, :egen, [:emis_co2=>0, :country=>"archenland"], 2)
                @show eserv_total_qual_2035 = aggregate_result(total, data, :bus, :eserv, :state=>"stormness", 2)

                @test gen_total_qual_2035/eserv_total_qual_2035 ≈ rps_mod.targets[:y2035]

                @show gen_total_qual_2040 = aggregate_result(total, data, :gen, :egen, [:emis_co2=>0, :country=>"archenland"], 3)
                @show eserv_total_qual_2040 = aggregate_result(total, data, :bus, :eserv, :state=>"stormness", 3)

                @test gen_total_qual_2040/eserv_total_qual_2040 ≈ rps_mod.targets[:y2040]

                @show curt_2035 = aggregate_result(total, data, :bus, :ecurt, :state=>"stormness", 2)
                @show curt_2040 = aggregate_result(total, data, :bus, :ecurt, :state=>"stormness", 3)

                gen_ref = get_table(data_ref, :gen)
                gen_total_ref = aggregate_result(total, data_ref, :gen, :egen, :emis_co2=>0)

                # check that generation is increased for qualifying gens
                @test gen_total_qual > gen_total_ref
            
            end

        end

        @testset "Test CES" begin

            config_file = joinpath(@__DIR__, "config", "config_3bus_ces.yml")
            config = read_config(config_file_ref, config_file)

            data = read_data(config)
            gen = get_table(data, :gen)
            
            @testset "Test Crediting CES" begin
                # columns added to the gen table
                @test hasproperty(gen, :example_ces)

                # check that some crediting was applied
                @test any(credit -> get_original(credit) > 0.0, gen[!,:example_ces])

                @test ~any(credit -> get_original(credit) > 1.0 || get_original(credit) < 0.0, gen[!,:example_ces])

            end

            @testset "Adding CES to model" begin
                
            end

        end

    end
end