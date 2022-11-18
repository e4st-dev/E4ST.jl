using DataFrames
using BenchmarkTools
using Test
import Arrow
import CSV
import XLSX
import JSON
import BSON
import YAML
import SQLite
import SQLite.DBInterface
using Query

# Create a mix of test data to save.
# mat = rand(2000, 200)
strs = ["nuclear", "geothermal", "natural_gas", "direct_air_capture"]
nr = 2000
nc = 100
df = DataFrame("gentype"=>rand(strs, nr), "idx"=>1:nr, ["x_$n"=>rand(nr) for n in 1:nc]...)

# in_file = "L:/Project-Gurobi/Workspace3/E4ST/Output/Results/prj_aet_mc/aet_init/us_can/result_aet_init_us_can_Y2029_gen_res.xlsx"
# df = XLSX.readtable(in_file, "annual")

res = DataFrame(
    "name"=>String[],
    "Read Time"=>Float64[],
    "Write Time"=>Float64[],
    "Filter Time"=>Float64[],
    "File Size"=>Int64[]
)

n = "SQLite.jl"

@testset "Test Data Saving" begin
    @testset "$n" begin
        filename = "testfile.sqlite"
        println("$n\n", "#"^80)
        println("Saving Table")
        bm_write = @benchmark (db = SQLite.DB($filename); $df |> SQLite.load!(db, "mytable"); close(db)) setup=(rm($filename, force=true))
        
        println("Loading Table")
        bm_read = @benchmark (db=SQLite.DB($filename); DBInterface.execute(db, "SELECT * FROM mytable") |> DataFrame; close(db))
        db = SQLite.DB(filename)
        dfnew = DBInterface.execute(db, "SELECT * FROM mytable") |> DataFrame
        close(db)
        
        bm_filter = @benchmark (db = SQLite.DB("testfile.sqlite"); DBInterface.execute(db, "SELECT * FROM mytable WHERE gentype = 'direct_air_capture' AND x_1 > 0.5 AND x_2 < 0.5") |> DataFrame; close(db))

        @test dfnew == df
        println("Filesize: $(filesize(filename))")
        push!(res, (n, median(bm_read.times), median(bm_write.times), median(bm_filter.times), filesize(filename)))
    end

    n = "Arrow.jl"
    @testset "$n" begin
        filename = "testfile.arrow"
        println("$n\n", "#"^80)
        println("Saving Table")
        bm_write = @benchmark Arrow.write($filename, $df) setup=(rm($filename, force=true)) evals=1
        
        println("Loading Table")
        bm_read = @benchmark Arrow.Table($filename) |> DataFrame
        dfnew = Arrow.Table(filename) |> DataFrame

        bm_filter = @benchmark Tables.datavaluerows(Arrow.Table("testfile.arrow")) |> @filter(_.gentype == "direct_air_capture" && _.x_1 > 0.5 && _.x_2 < 0.5) |> DataFrame

        @test dfnew == df
        println("Filesize: $(filesize(filename))")
        push!(res, (n, median(bm_read.times), median(bm_write.times), median(bm_filter.times), filesize(filename)))
    end

    n = "XLSX.jl"
    @testset "$n" begin
        filename = "testfile.xlsx"
        println("$n:\n", "#"^80)
        println("Saving Table")
        bm_write = @benchmark XLSX.writetable($filename, "SHEET1"=>$df) setup=(rm($filename, force=true)) evals=1
        
        println("Loading Table")
        bm_read = @benchmark XLSX.readtable($filename, "SHEET1") |> DataFrame
        dfnew = XLSX.readtable(filename, "SHEET1") |> DataFrame


        bm_filter = @benchmark XLSX.readtable($filename, "SHEET1") |> DataFrame |> @filter(_.gentype == "direct_air_capture" && _.x_1 > 0.5 && _.x_2 < 0.5) |> DataFrame
        @test dfnew == df

        println("Filesize: $(filesize(filename))")
        push!(res, (n, median(bm_read.times), median(bm_write.times), median(bm_filter.times), filesize(filename)))
    end

    n = "CSV.jl"
    @testset "$n" begin
        filename = "testfile.csv"
        println("$n:\n", "#"^80)
        println("Saving Table")
        bm_write = @benchmark CSV.write($filename, $df) setup=(rm($filename, force=true)) evals=1
        
        println("Loading Table")
        bm_read = @benchmark CSV.File($filename) |> DataFrame
        dfnew = CSV.File(filename) |> DataFrame

        bm_filter = @benchmark CSV.File("testfile.csv") |> @filter(_.gentype == "direct_air_capture" && _.x_1 > 0.5 && _.x_2 < 0.5) |> DataFrame
        
        @test dfnew == df
        println("Filesize: $(filesize(filename))")
        push!(res, (n, median(bm_read.times), median(bm_write.times), median(bm_filter.times), filesize(filename)))
    end
end
transform!(res, 
    "Write Time"=>(x->x./1e9)=>"Write Time",
    "Read Time"=>(x->x./1e9)=>"Read Time",
    "Filter Time"=>(x->x./1e9)=>"Filter Time"
    )
CSV.write("res.csv", res)