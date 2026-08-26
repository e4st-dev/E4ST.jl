@testset "Test Saving Config" begin

    function fieldnames_for_yaml(::Type{ExamplePolicyType})
        (:type, :some_parameter, :other_parameter)
    end

    filename = joinpath(@__DIR__, "config/config_3bus_examplepol.yml")

    config = read_config(filename)

    save_config(config)

    # test if there is a config 
    outfilename  = get_out_path(config, "config.yml")

    @test ispath(outfilename)

    # test if it can read in the saved config
    newconfig = read_config(outfilename)

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
            elseif i == :out_path
                continue # out_path should be different.
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

    @testset "YAML printing of NamedTuple config values" begin
        # Modification/Policy fields aren't required to be OrderedDicts - a field could be a
        # NamedTuple, which YAML.jl doesn't know how to serialize on its own. E4ST teaches it how
        # via a YAML._print(io, ::NamedTuple, ...) override (see config.jl), converting the
        # NamedTuple to an OrderedDict before printing. Test that override directly here.
        nt = (a = 1, b = "two", c = [1, 2, 3])
        io = IOBuffer()
        YAML.write(io, nt)
        yaml_str = String(take!(io))

        reloaded = YAML.load(yaml_str, dicttype = OrderedDict{Symbol, Any})
        @test reloaded == OrderedDict(pairs(nt))
    end

end

