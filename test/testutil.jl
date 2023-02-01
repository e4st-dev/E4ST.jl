@testset "Test parse_comparison" begin
    @test parse_comparison("emis_rate => >0.1") == ("emis_rate" => >(0.1))
    @test parse_comparison("emis_rate => <0.1") == ("emis_rate" => <(0.1))
    @test parse_comparison("emis_rate => (-Inf, 1)") == ("emis_rate" => (-Inf, 1))
    @test parse_comparison("emis_rate => (-1, 1)") == ("emis_rate" => (-1, 1))
    @test parse_comparison("year_on => (y2020, y2030)") == ("year_on" => ("y2020", "y2030"))
    @test parse_comparison("country=>narnia") == ("country"=>"narnia")
end