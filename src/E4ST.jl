module E4ST

using E4STUtil

export save_config!, load_config
export load_data
export save_results!, load_results

export setup_model, solve_model!
export postprocess!
export run_e4st

include("io/config.jl")
include("io/data.jl")
include("io/results.jl")
include("model/setup.jl")
include("model/solve.jl")
include("post/postprocessing.jl")

"""
    run_e4st(config) -> results

    run_e4st(filename) -> run_e4st(load_config(filename))

Top-level file for running E4ST
"""
function run_e4st(config)
    save_config!(config)
    data = load_data(config)
    model = setup_model(config, data)
    results = solve_model!(config, data, model)
    save_results!(config, results)
    postprocess!(config, results)
    return results
end
run_e4st(path::String) = run_e4st(load_config(path))


end # module
