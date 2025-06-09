@testset "Test Perfect Foresight" begin
    # Test discounting in objective function
    # Test shadow prices

    # Setup reference case 
    ####################################################################
    config_file_ref = joinpath(@__DIR__, "config", "config_3bus.yml")
    config_ref = read_config(config_file_ref)

    data_ref = read_data(config_ref)
    model_ref = setup_model(config_ref, data_ref)

    optimize!(model_ref)

    parse_results!(config_ref, data_ref, model_ref)
    process_results!(config_ref, data_ref)
    
    config_file = joinpath(@__DIR__, "config", "config_3bus_pfs.yml")
    config = read_config(config_file_ref, config_file)

    data = read_data(config)
    model = setup_model(config, data)

    nyr = get_num_years(data)

    # Perfect foresight tests
    #####################################################################

    @testset "Test objective scalars" begin
        @test haskey(config, :yearly_objective_scalars)
        yearly_obj_scalars = config[:yearly_objective_scalars
        
        #test that number of scalars is equal to number of years
        @test length(yearly_obj_scalars) == nyr
        
        #test that discount reduces each year
        @test all(yr_idx->(yearly_obj_scalars[yr_idx] > yearly_obj_scalars[yr_idx+1]) , 1:nyr-1)
    end

    @testset "Test terminal conditions" begin
        years = get_years(data)
        gen_idxs = get_table_row_idxs(data, :gen)
        gen = get_table(data, :gen)
        
        # test that yearly capex objs are equal to capex for plants with econ lifetime longer than sim years
        for gen_idx in gen_idxs
            status = gen[gen_idx, :build_status]
            if status == "unbuilt"
                year_on = gen[gen_idx, :year_on]
                econ_life = gen[gen_idx, :econ_life]
                yr_idx_on = findfirst(==(year_on), years)
                yr_on = isnothing(yr_idx_on) ? 1 : yr_idx_on
                if add_to_year(year_on, econ_life) > years[end]
                    @test all(y->(get_table_num(data, :gen, :capex_obj, gen_idx, y, :) == get_table_num(data, :gen, :capex, gen_idx, y, :)), yr_on:nyr)
                end
            end
        end
        
        # test capex_obj for plants that retire during sim years
        for (year_idx, year) in enumerate(years)
            gen_idxs = get_table_row_idxs(data, :gen, :year_off=>year)
            for gen_idx in gen_idxs
                # Check that capex_obj is 0 for years >= year_off
                for y in 1:nyr
                    if y > year_idx
                        @test get_table_num(data, :gen, :capex_obj, gen_idx, y, :) == 0
                    end
                end
            end
        end
    end

    @testset "Test objective function" begin
        #test that objective function has a term for each year
        @test length(model[:obj]) == nyr
        
        optimize!(model)
        @test check(config, data, model)
        parse_results!(config, data, model)
        process_results!(config, data)
        
        #test total obj was lowered
        @test sum(get_raw_result(data, :obj)) < sum(get_raw_result(data_ref, :obj))
    end

end



        
