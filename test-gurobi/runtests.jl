using E4ST
using Gurobi
using YAML
using OrderedCollections

mktempdir(@__DIR__) do path

    # Copy the entire test directory.
    cp(joinpath(@__DIR__,"../test"), path, force=true)

    # Change config files to use Gurobi
    gurobi_settings = OrderedDict(
        :type=>"Gurobi"
    )
    config_path = joinpath(path, "config")
    for config_file in readdir(config_path, join=true)
        contains(config_file, ".yml") || continue
        config = YAML.load_file(config_file, dicttype=OrderedDict{Symbol, Any})
        config[:optimizer] = gurobi_settings
        YAML.write_file(config_file, config)
    end

    # Run Tests
    include(joinpath(path, "runtests.jl"))


end