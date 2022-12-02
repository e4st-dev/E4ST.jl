using BenchmarkTools
using E4ST

include("benchmark_helper.jl")

const SUITE = BenchmarkGroup()

config = make_random_inputs()
data = load_data(config)
SUITE["load_bus_table!"] = @benchmarkable E4ST.load_bus_table!($config, $data)
SUITE["load_gen_table!"] = @benchmarkable E4ST.load_gen_table!($config, $data)
SUITE["load_branch_table!"] = @benchmarkable E4ST.load_branch_table!($config, $data)
SUITE["load_hours_table!"] = @benchmarkable E4ST.load_hours_table!($config, $data)
SUITE["load_af!"] = @benchmarkable E4ST.load_af_table!($config, $data)
SUITE["get_generator"] = @benchmarkable get_generator($data, 1)
SUITE["get_af"] = @benchmarkable get_af($data, 50, 3, 50)