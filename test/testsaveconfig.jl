#@Test false

using E4ST
using YAML
import OrderedCollections: OrderedDict



"""
struct AnnualAdjust <: Policy

This is an example subtype of Policy that applies some annual adjustment to a value which comes from csv.
"""
mutable struct AnnualAdjust <: Modification
    type::String
    setname::String
    inputfilepath::String
end

function fieldnames_for_yaml(::Type{AnnualAdjust})
    (:type, :polname, :polvalfile)
end



filename = joinpath(@__DIR__, "config/config_dac1.yml")

config = load_config(filename)

save_config(config)

# test if there is a config 

# test if it can load in the saved config 

# remove the config that was just created



