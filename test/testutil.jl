import E4ST: Container, ByNothing, ByHour, ByYear, ByYearAndHour, OriginalContainer, scale_hourly, scale_yearly, add_hourly, add_yearly, set_hourly, set_yearly, get_original

function container_compare(c::Container, v::Vector{<:Vector}, nyr, nhr)
    return all(h->(all(y->(c[y,h]==v[y][h]),1:nyr)), 1:nhr)
end
function container_compare(c::Container, v::Matrix, nyr, nhr)
    return all(h->(all(y->(c[y,h]==v[y,h]),1:nyr)), 1:nhr)
end

@testset "Test Utilities" begin
    @testset "Test parse_comparison" begin
        @test parse_comparison("emis_rate => >0.1") == ("emis_rate" => >(0.1))
        @test parse_comparison("emis_rate => <0.1") == ("emis_rate" => <(0.1))
        @test parse_comparison("emis_rate => >=0.1") == ("emis_rate" => >=(0.1))
        @test parse_comparison("emis_rate => <=0.1") == ("emis_rate" => <=(0.1))

        @test parse_comparison("emis_rate => >y2020.54321") == ("emis_rate" => >("y2020.54321"))
        @test parse_comparison("emis_rate => <y2020") == ("emis_rate" => <("y2020"))
        @test parse_comparison("emis_rate => >=y2020") == ("emis_rate" => >=("y2020"))
        @test parse_comparison("emis_rate => <=y2020") == ("emis_rate" => <=("y2020"))

        @test parse_comparison("genfuel=>[ng,solar,wind]") == ("genfuel" => ["ng", "solar", "wind"])
        @test parse_comparison("bus_idx=>[1,2,3]") == ("bus_idx" => [1,2,3])
        @test parse_comparison("emis_rate=>[1.5,2.5,3.5]") == ("emis_rate" => [1.5,2.5,3.5])

        @test parse_comparison("emis_rate => (-Inf, 1)") == ("emis_rate" => (-Inf, 1))
        @test parse_comparison("emis_rate => (-1, 1)") == ("emis_rate" => (-1, 1))
        @test parse_comparison("year_on => (y2020, y2030)") == ("year_on" => ("y2020", "y2030"))
        @test parse_comparison("country=>narnia") == ("country"=>"narnia")

        d = Dict(:emis_co2 => "<= 0.1")
        @test ("emis_co2" => <=(0.1)) in parse_comparisons(d)
    end






    @testset "Test Container Adjustments" begin
        nhr = 8
        nyr = 3
        v_hr = rand(nhr)
        v_yr = rand(nyr)
        orig = rand()
        orig_hr = fill(orig, nhr)
        orig_yr = fill(orig, nyr)
        c = ByNothing(orig)

        @testset "Test Yearly Adjustments" begin
            # Yearly adjusting
            c1 = E4ST.set_yearly(c, v_yr)
            @test container_compare(c1, v_yr .* ones(nhr)', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_yearly(c, v_yr)
            @test container_compare(c1, v_yr .* orig_hr', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_yearly(c, v_yr)
            @test container_compare(c1, v_yr .+ orig_hr', nyr, nhr)
            @test get_original(c1) == orig
        end

        @testset "Test Hourly Adjustments" begin
            # Hourly adjusting for specific year (year 3)
            c1 = E4ST.set_hourly(c, v_hr, 3, nyr)
            @test container_compare(c1, [orig_hr, orig_hr, v_hr], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_hourly(c, v_hr, 3, nyr)
            @test container_compare(c1, [orig_hr, orig_hr, v_hr.*orig_hr], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_hourly(c, v_hr, 3, nyr)
            @test container_compare(c1, [orig_hr, orig_hr, v_hr.+orig_hr], nyr, nhr)
            @test get_original(c1) == orig

            # Hourly adjusting for all years
            c1 = E4ST.set_hourly(c, v_hr, :, nyr)
            @test container_compare(c1, [v_hr, v_hr, v_hr], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_hourly(c, v_hr, :, nyr)
            @test container_compare(c1, orig_yr .* v_hr', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_hourly(c, v_hr, :, nyr)
            @test container_compare(c1, orig_yr .+ v_hr', nyr, nhr)
            @test get_original(c1) == orig
        end

        @testset "Test Yearly, then Hourly Adjustments" begin
            c_yr = E4ST.set_yearly(c, v_yr)

            # Hourly adjusting for specific year (year 3)
            c1 = E4ST.set_hourly(c_yr, v_hr, 3, nyr)
            @test container_compare(c1, [ones(nhr)*v_yr[1], ones(nhr)*v_yr[2], v_hr], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_hourly(c_yr, v_hr, 3, nyr)
            @test container_compare(c1, [ones(nhr)*v_yr[1], ones(nhr)*v_yr[2], v_hr.*v_yr[3]], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_hourly(c_yr, v_hr, 3, nyr)
            @test container_compare(c1, [ones(nhr)*v_yr[1], ones(nhr)*v_yr[2], v_hr.+v_yr[3]], nyr, nhr)
            @test get_original(c1) == orig

            # Hourly adjusting for all years
            c1 = E4ST.set_hourly(c_yr, v_hr, :, nyr)
            @test container_compare(c1, [v_hr, v_hr, v_hr], nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_hourly(c_yr, v_hr, :, nyr)
            @test container_compare(c1, v_yr .* v_hr', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_hourly(c_yr, v_hr, :, nyr)
            @test container_compare(c1, v_yr .+ v_hr', nyr, nhr)
            @test get_original(c1) == orig
            
        end

        @testset "Test Hourly, then Yearly Adjustments" begin
            c_hr = E4ST.set_hourly(c, v_hr, :, nyr)

            # Yearly adjusting
            c1 = E4ST.set_yearly(c_hr, v_yr)
            @test container_compare(c1, v_yr .* ones(nhr)', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.scale_yearly(c_hr, v_yr)
            @test container_compare(c1, v_yr .* v_hr', nyr, nhr)
            @test get_original(c1) == orig

            c1 = E4ST.add_yearly(c_hr, v_yr)
            @test container_compare(c1, v_yr .+ v_hr', nyr, nhr)
            @test get_original(c1) == orig
        end
    end
    
    @testset "Test Util Helper Functions" begin
        str_year = "y2020"
        str_years = ["y2020", "y2025"]
        @test year2int(str_year) isa Int
        @test year2int.(str_years) isa Vector{Int}

        int_year = 2020
        int_years = [2020, 2025]
        @test year2str(int_year) isa AbstractString
        @test year2str.(int_years) isa Vector{String}
    end

end