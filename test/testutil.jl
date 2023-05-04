import E4ST: Container, ByNothing, ByHour, ByYear, ByYearAndHour, OriginalContainer, scale_hourly, scale_yearly, add_hourly, add_yearly, set_hourly, set_yearly, get_original

function container_compare(c::Container, v::Vector{<:Vector}, nyr, nhr)
    return all(h->(all(y->(c[y,h]==v[y][h]),1:nyr)), 1:nhr)
end
function container_compare(c::Container, v::Matrix, nyr, nhr)
    return all(h->(all(y->(c[y,h]==v[y,h]),1:nyr)), 1:nhr)
end

function test_container_broadcast(f, x1, x2, T, nyr, nhr)
    x = broadcast(f, x1, x2)
    @test x isa T
    @test all(x[yr_idx, hr_idx] == f(x1[yr_idx, hr_idx], x2[yr_idx, hr_idx]) for yr_idx in 1:nyr, hr_idx in 1:nhr)
end

function test_original_container_broadcast(f, oc, x1, nyr, nhr)
    x = broadcast(f, oc, x1)
    @test x isa OriginalContainer
    @test get_original(x) == get_original(oc)
    @test all(x[yr_idx, hr_idx] == f(oc[yr_idx, hr_idx], x1[yr_idx, hr_idx]) for yr_idx in 1:nyr, hr_idx in 1:nhr)

    x = broadcast(f, x1, oc)
    @test x isa OriginalContainer
    @test get_original(x) == get_original(oc)
    @test all(x[yr_idx, hr_idx] == f(x1[yr_idx, hr_idx], oc[yr_idx, hr_idx]) for yr_idx in 1:nyr, hr_idx in 1:nhr)
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

        @testset "Test Yearly adjustments by single value" begin
            nyr = 3
            nhr = 4
            bn = ByNothing(rand())
            by = ByYear(rand(nyr))
            byh = ByYearAndHour(map(x->rand(nhr), 1:nyr))
            bh = ByHour(rand(nhr))

            @testset "Test add_yearly" begin
                x = rand()
                by_new =  add_yearly(by, x, 2, nyr)
                @test by[1,:] == by_new[1,:]
                @test by[2,:] + x == by_new[2,:]

                bn_new = add_yearly(bn, x, 2, nyr)
                @test bn[1,:] == bn_new[1, :]
                @test bn[2,:] + x == bn_new[2,:]

                byh_new = add_yearly(byh, x, 2, nyr)
                @test all(byh[1,h] == byh_new[1,h] for h in 1:nhr)
                @test all(byh[2,h] + x == byh_new[2,h] for h in 1:nhr)

                bh_new = add_yearly(bh, x, 2, nyr)
                @test all(bh[1,h] == bh_new[1,h] for h in 1:nhr)
                @test all(bh[2,h] + x == bh_new[2,h] for h in 1:nhr)
            end

            @testset "Test scale_yearly" begin
                x = rand()
                by_new =  scale_yearly(by, x, 2, nyr)
                @test by[1,:] == by_new[1,:]
                @test by[2,:] * x == by_new[2,:]

                bn_new = scale_yearly(bn, x, 2, nyr)
                @test bn[1,:] == bn_new[1, :]
                @test bn[2,:] * x == bn_new[2,:]

                byh_new = scale_yearly(byh, x, 2, nyr)
                @test all(byh[1,h] == byh_new[1,h] for h in 1:nhr)
                @test all(byh[2,h] * x == byh_new[2,h] for h in 1:nhr)

                bh_new = scale_yearly(bh, x, 2, nyr)
                @test all(bh[1,h] == bh_new[1,h] for h in 1:nhr)
                @test all(bh[2,h] * x == bh_new[2,h] for h in 1:nhr)
            end

            @testset "Test set_yearly" begin
                x = rand()
                by_new =  set_yearly(by, x, 2, nyr)
                @test by[1,:] == by_new[1,:]
                @test x == by_new[2,:]

                bn_new = set_yearly(bn, x, 2, nyr)
                @test bn[1,:] == bn_new[1, :]
                @test x == bn_new[2,:]

                byh_new = set_yearly(byh, x, 2, nyr)
                @test all(byh[1,h] == byh_new[1,h] for h in 1:nhr)
                @test all(x == byh_new[2,h] for h in 1:nhr)

                bh_new = set_yearly(bh, x, 2, nyr)
                @test all(bh[1,h] == bh_new[1,h] for h in 1:nhr)
                @test all(x == bh_new[2,h] for h in 1:nhr)
            end

            @testset "Test broadcasted operations" begin
                nyr = 3
                nhr = 4
                bn = ByNothing(rand())
                by = ByYear(rand(nyr))
                byh = ByYearAndHour(map(x->rand(nhr), 1:nyr))
                bh = ByHour(rand(nhr))

                test_container_broadcast(+, bn, bn, ByNothing, nyr, nhr)
                test_container_broadcast(+, bn, by, ByYear, nyr, nhr)
                test_container_broadcast(+, by, bn, ByYear, nyr, nhr)
                test_container_broadcast(+, bn, bh, ByHour, nyr, nhr)
                test_container_broadcast(+, bh, bn, ByHour, nyr, nhr)
                test_container_broadcast(+, bn, byh, ByYearAndHour, nyr, nhr)
                test_container_broadcast(+, byh, bn, ByYearAndHour, nyr, nhr)
                
                test_container_broadcast(+, by, by, ByYear, nyr, nhr)
                test_container_broadcast(+, by, bh, ByYearAndHour, nyr, nhr)
                test_container_broadcast(+, bh, by, ByYearAndHour, nyr, nhr)
                test_container_broadcast(+, byh, by, ByYearAndHour, nyr, nhr)
                test_container_broadcast(+, by, byh, ByYearAndHour, nyr, nhr)
                
                test_container_broadcast(+, bh, bh, ByHour, nyr, nhr)
                test_container_broadcast(+, bh, byh, ByYearAndHour, nyr, nhr)
                test_container_broadcast(+, byh, bh, ByYearAndHour, nyr, nhr)

                oc = Container(rand())

                test_original_container_broadcast(+, oc, bn, nyr, nhr)
                test_original_container_broadcast(+, oc, by, nyr, nhr)
                test_original_container_broadcast(+, oc, bh, nyr, nhr)
                test_original_container_broadcast(+, oc, byh, nyr, nhr)
            end


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