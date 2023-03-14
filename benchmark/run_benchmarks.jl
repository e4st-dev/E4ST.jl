using Pkg
Pkg.activate(@__DIR__)
using PkgBenchmark, E4ST, Dates
res = benchmarkpkg(E4ST)
ds = Dates.format(now(), dateformat"yymmdd_HHMMSS")
mkpath(joinpath(@__DIR__, "results"))
export_markdown(joinpath(@__DIR__, "results/res$ds.md"), res)