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
            "Demand" => "inputs/demand.md",
            "Availability Factor Table" => "inputs/af.md",
            "Arbitrary Hourly/Yearly Adjustments" => "inputs/adjust.md",
            "Logging" => "inputs/logging.md"
        ],
        "Types"=>Any[
            "Modication"=>"types/mod.md",
            "Iterable"=>"types/iterable.md",
        ],
        "Model"=>Any[
            "DC Optimal Power Flow"=>"model/dcopf.md"
            "Model Formulation"=>"model/formulation.md"
        ]
    ],
    # TODO: Comment out format line before deploying, this is only for testing locally
    format = Documenter.HTML(prettyurls = false)
)

# TODO: Uncomment below to deploy the docs to the github repo!
# deploydocs(
#     repo = "https://github.com/e4st-dev/E4ST.jl"
# )