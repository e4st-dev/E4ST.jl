using Documenter, E4ST

makedocs(
    modules = [E4ST],
    doctest = false,
    sitename = "E4ST.jl",
    pages = [
        "Home" => "index.md",
        "Inputs"=>Any[
            "Config File" => "inputs/config.md"
        ]
    ]
)

# deploydocs(
#     repo = "https://github.com/e4st-dev/E4ST.jl"
# )