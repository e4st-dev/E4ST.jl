using Pkg
Pkg.activate(@__DIR__)
using PkgBenchmark, E4ST
res = benchmarkpkg(E4ST)
export_markdown(joinpath(@__DIR__, "results.md"), res)