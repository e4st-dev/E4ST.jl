#@Test false

using E4ST
using YAML
import OrderedCollections: OrderedDict

function fieldnames_for_yaml(::Type{ExamplePolicyType})
    (:type, :some_parameter, :other_parameter)
end
export fieldnames_for_yaml

filename = joinpath(@__DIR__, "config/config_3bus_examplepol.yml")

config = load_config(filename)

save_config(config)

# test if there is a config 
outfilename  = joinpath(config[:out_path],basename(config[:config_file]))

@test ispath(outfilename)

# test if it can load in the saved config 
newconfig = load_config(outfilename)

@test isabspath(newconfig[:out_path])
@test isabspath(newconfig[:gen_file])
@test isabspath(newconfig[:bus_file])
@test isabspath(newconfig[:branch_file])

@test newconfig[:mods] isa OrderedDict{Symbol, <:Modification}




function dictcompare(dict1::OrderedDict, dict2::OrderedDict)
    for (i, j) in dict1
        if j isa OrderedDict && dict2[i] isa OrderedDict
            dictcompare(dict1[i], dict2[i])
        elseif typeof(j) <:Modification
            dictcompare(dict1[i], dict2[i])
        elseif i == :config_file
            continue
        else
            @test dict2[i] == j
        end
    end
end

function dictcompare(dict1::M, dict2::M) where M <: Modification
    #@test dict1 == dict2
    for f in propertynames(dict1)
        if dict1[f] isa OrderedDict && dict2[f] isa OrderedDict
            dictcompare(dict1[f], dict2[f])
        else 
            @test dict1[f] == dict2[f]
        end
    end
end

dictcompare(newconfig, config)
# remove the config that was just created

newconfig = nothing



