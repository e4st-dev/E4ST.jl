using Documenter, E4ST

makedocs(
    modules = [E4ST],
    doctest = false,
    sitename = "E4ST.jl",
    pages = [
        "Home" => "index.md",
        "Overview" => "overview.md",
        "Inputs"=>Any[
            "Config File" => "inputs/config.md",
            "Data" => "inputs/data.md",
            "Bus Table" => "inputs/bus.md",
            "Generator Table" => "inputs/gen.md",
            "Branch Table" => "inputs/branch.md",
            "Hours Table" => "inputs/hours.md",
            "Load" => "inputs/load.md",
            "Availability Factor Table" => "inputs/af.md",
            "Arbitrary Temporal Adjustments" => "inputs/adjust.md",
            "Logging" => "inputs/logging.md"
        ],
        "Model"=>Any[
            "DC Optimal Power Flow"=>"model/dcopf.md",
            "Model Formulation"=>"model/formulation.md",
        ],
        "Results" => Any[
            "Overview" => "results/overview.md",
            "Aggregation" => "results/aggregation.md",
            "Plotting" => "results/plotting.md",
        ],
        "Types"=>Any[
            "Modication"=>"types/mod.md",
            "Iterable"=>"types/iterable.md",
            "Policy"=>"types/policy.md",
            "Unit"=>"types/unit.md",
        ],
        "Technologies"=>Any[
            "CO₂ Capture, Utilization & Storage"=>"types/modifications/ccus.md",
            "DC Transmission Lines" => "types/modifications/dcline.md",
            "Storage" => "types/modifications/storage.md",
            "Retrofits" => "types/modifications/retrofits.md",
        ],
        
    ],
    # TODO: Comment out format line before deploying, this is only for testing locally
    format = Documenter.HTML(prettyurls = false)
)

# TODO: Uncomment below to deploy the docs to the github repo!
# deploydocs(
#     repo = "https://github.com/e4st-dev/E4ST.jl"
# )