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
Base.global_logger(Base.NullLogger())
Base.disable_logging(Base.CoreLogging.Warn)

function warmup()
    config = make_random_inputs()
    data = load_data(config)
    model = setup_model(config, data)
    return nothing
end

warmup()

SUITE["get_generator"] = @benchmarkable get_generator(data, 1) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000
SUITE["get_af"] = @benchmarkable get_af(data, 50, 3, 50) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000
SUITE["get_pdem"] = @benchmarkable get_pdem(data, 50, 3, 50) setup=(config=make_random_inputs(); data = load_data(config)) evals=1000
SUITE["setup_model"] = @benchmarkable setup_model(config, data) setup=(config=make_random_inputs(); data=load_data(config))
SUITE["load_data"] = @benchmarkable load_data(config) setup=(config=make_random_inputs())
