using Documenter, E4ST

makedocs(
    modules = [E4ST],
    doctest = false,
    sitename = "E4ST.jl",
    pages = [
        "Home" => "index.md",
        "Inputs"=>Any[
            "Config File" => "inputs/config.md",
            "Bus Table" => "inputs/bus.md",
            "Generator Table" => "inputs/gen.md",
            "Branch Table" => "inputs/branch.md",
            "Hours Table" => "inputs/hours.md",
            "Availability Factor Table" => "inputs/af.md",
        ],
        "Types"=>Any[
            "Modication"=>"types/mod.md"
        ]
    ],
    # TODO: Comment out format line before deploying, this is only for testing locally
    format = Documenter.HTML(prettyurls = false)
)

# TODO: Uncomment below to deploy the docs to the github repo!
# deploydocs(
#     repo = "https://github.com/e4st-dev/E4ST.jl"
# )