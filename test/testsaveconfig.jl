#@Test false

using E4ST
using YAML
import OrderedCollections: OrderedDict
include("../src/io/config.jl")
include("../src/types/Modification.jl")


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





# testconfig = load_config(config_ann_adj)

# temp making config dict manually to get around load config
testconfig = OrderedDict{Symbol, Any}(:out_path => "test_data/out/")
     
testconfig[:mods] = OrderedDict{Symbol, Any}(:example_ann_adj => OrderedDict{Symbol, Any}(:type => "AnnualAdjust", 
        :setname => "test_ann_adj", :input_file => "../test_data/test_ann_adj.csv", :extra_key => [2,3,4,5]))

convert_types!(testconfig, :mods)

testconfig[:configfilename] = "config_ann_adj.yml"

save_config(testconfig)

