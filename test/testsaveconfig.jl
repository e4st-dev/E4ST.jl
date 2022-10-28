@Test false

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
testconfig = OrderedDict{Symbol, Any}(:out_path => "../out/t_ann_adj")
testconfig[:mods] = OrderedDict{Symbol, Any}(:example_ann_adj => OrderedDict{Symbol, Any}(:type => "AnnualAdjust", 
        :setname => "test_ann_adj", :input_file => "../test_data/test_ann_adj.csv"))
testconfig[:configfilename] = "config_ann_adj.yml"

save_config!(testconfig)

