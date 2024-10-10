@testset "Test Welfare Balancing" begin
    @testset "Without Storage" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        config = read_config(config_file, log_model_summary=true)
        delete!(config, :build_gen_file)

        data = read_data(config)
        model = setup_model(config, data)

        optimize!(model)
        # solution_summary(model)

        @test check(config, data, model)

        parse_results!(config, data, model)
        process_results!(config, data)

        @test sum(abs, get_raw_result(data, :pflow_dc)) > 0.1

        # Test that revenue of electricity for generators equals the cost for users
        line_loss_rate = config[:line_loss_rate]
        @test compute_result(data, :bus, :elcurt_total) < 1e-6
        @test compute_result(data, :bus, :elserv_total) ≈ (compute_result(data, :gen, :egen_total)) * (1 - line_loss_rate)

        @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
        @test compute_result(data, :bus, :merchandising_surplus_total) > 10 # Not truly a requirement, except that we want to design our test case so that this is true.

        @test compute_result(data, :bus, :electricity_cost) - compute_result(data, :bus, :merchandising_surplus_total) ≈ compute_result(data, :gen, :electricity_revenue)
        @test abs(compute_welfare(data, :electricity_payments)) < 1e-6
    end

    @testset "With Storage" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
        config = read_config(config_file, storage_config_file, log_model_summary=true)
        delete!(config, :build_gen_file)
        delete!(config[:mods], :example_emiscap)
        delete!(config[:mods], :example_summer_emiscap)


        data = read_data(config)
        model = setup_model(config, data)

        optimize!(model)
        # solution_summary(model)

        @test check(config, data, model)

        parse_results!(config, data, model)
        process_results!(config, data)

        @test compute_result(data, :storage, :eloss_total) > 0.0

        @test sum(abs, get_raw_result(data, :pflow_dc)) > 0.1

        # Test that revenue of electricity for generators equals the cost for users
        line_loss_rate = config[:line_loss_rate]
        @test compute_result(data, :bus, :elcurt_total) < 1e-6
        @test compute_result(data, :bus, :elserv_total) ≈ (1 - line_loss_rate) *
            (
                compute_result(data, :gen, :egen_total) - 
                compute_result(data, :storage, :eloss_total)
            )

        @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
        @test compute_result(data, :bus, :merchandising_surplus_total) > 10 # Not truly a requirement, except that we want to design our test case so that this is true.

        @test (
            compute_result(data, :bus, :electricity_cost) +
            compute_result(data, :storage, :electricity_cost) +
            -compute_result(data, :bus, :merchandising_surplus_total)
        ) ≈ (
            compute_result(data, :gen, :electricity_revenue) +
            compute_result(data, :storage, :electricity_revenue)
        )
        @test abs(compute_welfare(data, :electricity_payments)) < 1e-6
    end

    @testset "With Generation Standards" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        # storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
        gs_config_file = joinpath(@__DIR__, "config", "config_3bus_rps.yml")
        config = read_config(config_file, gs_config_file, log_model_summary=true)
        delete!(config[:mods], :stor)
        # delete!(config[:mods], :example_rps_gentype)
        # delete!(config[:mods], :example_emiscap)
        # delete!(config[:mods], :example_summer_emiscap)


        data = read_data(config)
        model = setup_model(config, data)

        optimize!(model)
        # solution_summary(model)

        @test check(config, data, model)

        parse_results!(config, data, model)
        process_results!(config, data)

        @test sum(abs, get_raw_result(data, :pflow_dc)) > 0.1

        # Test that revenue of electricity for generators equals the cost for users
        line_loss_rate = config[:line_loss_rate]
        @test compute_result(data, :bus, :elcurt_total) < 1e-6
        
        @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
        @test compute_result(data, :bus, :merchandising_surplus_total) > 10 # Not truly a requirement, except that we want to design our test case so that this is true.

        @test -1e-6 < compute_welfare(data, :electricity_payments) < 1e-6
    end

    @testset "With Emis Caps" begin
        config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
        storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
        config = read_config(config_file, storage_config_file, log_model_summary=true)
        delete!(config[:mods], :example_emiscap)
        delete!(config[:mods], :example_summer_emiscap)


        data = read_data(config)
        model = setup_model(config, data)

        optimize!(model)
        # solution_summary(model)

        @test check(config, data, model)

        parse_results!(config, data, model)
        process_results!(config, data)

        @test compute_result(data, :storage, :eloss_total) > 0.0

        @test sum(abs, get_raw_result(data, :pflow_dc)) > 0.1

        # Test that revenue of electricity for generators equals the cost for users
        line_loss_rate = config[:line_loss_rate]
        @test compute_result(data, :bus, :elcurt_total) < 1e-6
        @test compute_result(data, :bus, :elserv_total) ≈ (1 - line_loss_rate) *
            (
                compute_result(data, :gen, :egen_total) - 
                compute_result(data, :storage, :eloss_total)
            )

        @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
        # @test compute_result(data, :bus, :merchandising_surplus_total) > 10 # Not truly a requirement, except that we want to design our test case so that this is true.

        @test (
            compute_result(data, :bus, :electricity_cost) +
            compute_result(data, :storage, :electricity_cost) +
            -compute_result(data, :bus, :merchandising_surplus_total)
        ) ≈ (
            compute_result(data, :gen, :electricity_revenue) +
            compute_result(data, :storage, :electricity_revenue)
        )
        @test abs(compute_welfare(data, :electricity_payments)) < 1e-6
    end

    # @testset "With Storage and Reserve Requirements" begin
    #     config_file = joinpath(@__DIR__, "config", "config_3bus.yml")
    #     storage_config_file = joinpath(@__DIR__, "config", "config_stor.yml")
    #     rr_config_file = joinpath(@__DIR__, "config", "config_3bus_reserve_req.yml")
    #     config = read_config(config_file, storage_config_file, rr_config_file, log_model_summary=true)
    #     # delete!(config, :build_gen_file)
    #     delete!(config[:mods], :example_emiscap)
    #     delete!(config[:mods], :example_summer_emiscap)
        
    #     data = read_data(config)

    #     gen = get_table(data, :gen)
    #     filter!(row->!(row.build_status == "unbuilt" && row.bus_idx == 2), gen)

    #     model = setup_model(config, data)

    #     optimize!(model)

    #     @test check(config, data, model)

    #     parse_results!(config, data, model)
    #     process_results!(config, data)

    #     @test sum(abs, get_raw_result(data, :pflow_dc)) > 0.1


    #     # Test that revenue of electricity for generators equals the cost for users
    #     line_loss_rate = config[:line_loss_rate]
    #     @test compute_result(data, :bus, :elcurt_total) < 1e-6
    #     @test compute_result(data, :bus, :elserv_total) ≈ (1 - line_loss_rate) *
    #         (
    #             compute_result(data, :gen, :egen_total) - 
    #             compute_result(data, :storage, :eloss_total)
    #         )

    #     @test compute_result(data, :bus, :distribution_cost_total) ≈ 60 * compute_result(data, :bus, :elserv_total)
    #     @test compute_result(data, :bus, :merchandising_surplus_total) > 10 # Not truly a requirement, except that we want to design our test case so that this is true.

    #     @test (
    #         compute_result(data, :bus, :electricity_cost) +
    #         compute_result(data, :storage, :electricity_cost) +
    #         -compute_result(data, :bus, :merchandising_surplus_total)
    #     ) ≈ (
    #         compute_result(data, :gen, :electricity_revenue) +
    #         compute_result(data, :storage, :electricity_revenue)
    #     )
    # end
end