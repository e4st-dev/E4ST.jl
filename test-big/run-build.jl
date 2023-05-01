using Gurobi, E4ST
config_2016 = "L:/Project-Gurobi/Workspace3/E4ST/erussell/repos/e4st-input-processing/data/config/config_2016.yml"
config_gurobi = joinpath(@__DIR__, "config/config_gurobi.yml")
base_out_path = joinpath(@__DIR__, "out/gurobi-expansion")
@time out_path, _ = run_e4st(config_2016, config_gurobi; base_out_path, warn_overwrite = false)