#=#############################################################################
Benchmarking E4ST
###############################################################################
This runs as part of the pipeline in pull requests.  However, if you want to 
run it manually, you can run it and print the results by including run_benchmarks.jl
=##############################################################################
using BenchmarkTools
using E4ST

include("benchmark_helper.jl")

const SUITE = BenchmarkGroup()

SUITE["load_bus_table!"] = @benchmarkable E4ST.load_bus_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["load_gen_table!"] = @benchmarkable E4ST.load_gen_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["load_branch_table!"] = @benchmarkable E4ST.load_branch_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["load_hours_table!"] = @benchmarkable E4ST.load_hours_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["load_af_table!"] = @benchmarkable E4ST.load_af_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["load_demand_table!"] = @benchmarkable E4ST.load_demand_table!(config, data) setup=(config=make_random_inputs(); data = load_data(config))
SUITE["get_generator"] = @benchmarkable get_generator(data, 1) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000
SUITE["get_af"] = @benchmarkable get_af(data, 50, 3, 50) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000
SUITE["get_pdem"] = @benchmarkable get_pdem(data, 50, 3, 50) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000