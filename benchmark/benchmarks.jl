using BenchmarkTools
using E4ST

include("benchmark_helper.jl")

const SUITE = BenchmarkGroup()

config = make_random_inputs()
data = OrderedDict{Symbol, Any}()
SUITE["load_bus_table!"] = @benchmarkable E4ST.load_bus_table!($config, $data)
SUITE["load_gen_table!"] = @benchmarkable E4ST.load_gen_table!($config, $data)
SUITE["load_branch_table!"] = @benchmarkable E4ST.load_branch_table!($config, $data)
SUITE["load_time!"] = @benchmarkable E4ST.load_time!($config, $data)
SUITE["load_af!"] = @benchmarkable E4ST.load_af!($config, $data)
SUITE["testrand"] = @benchmarkable rand($s, $s)

SUITE["testzeros"] = @benchmarkable zeros($s, $s)