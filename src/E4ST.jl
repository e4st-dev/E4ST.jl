module E4ST

# General Packages
using InteractiveUtils
using JuMP

# E4ST Packages
using E4STUtil

export save_config!, load_config
export load_data
export save_results!, load_results

export setup_model, solve_model!
export postprocess!
export run_e4st
export Policy, get_type
export apply!, results!

include("io/config.jl")
include("io/data.jl")
include("io/results.jl")
include("model/setup.jl")
include("model/results.jl")
include("post/postprocessing.jl")
include("policy/Policy.jl")

"""
    run_e4st(config) -> results

    run_e4st(filename) -> run_e4st(load_config(filename))

Top-level file for running E4ST
"""
function run_e4st(config)
    save_config!(config)
    data = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    results = get_results(config, data, model)
    save_results!(config, results)
    postprocess!(config, results)
    return results
end
run_e4st(path::String) = run_e4st(load_config(path))

"""
    reload_policies!() -> nothing

Reloads the any `Policy` types so that `PolicyFromString` will work.
"""
function reload_policies!()
    reload_types!(Policy)
end

global STR2TYPE = Dict{String, Type}()

"""
    reload_types!()

    reload_types!(::Type)

Loads all types associated with E4ST so that the type will accessible by string with `get_type(str)`.
"""
function reload_types!()
    reload_types!(Policy)
end
function reload_types!(::Type{T}) where T
    global STR2TYPE
    for type in subtypes(T)
        strtype = string(type)
        STR2TYPE[strtype] = type
        if isabstracttype(type)
            reload_types!(type)
        end
    end
end

"""
    get_type(str::String) -> type

Returns the E4ST-related `type` corresponding to `str`.  See also `reload_types!`

# Examples:
```julia
julia> get_type("MyType")
ERROR: There has been no type MyType defined!
julia> struct MyType <: Policy end
julia> T = get_type("MyType")
MyType
julia> T()
MyType()
```
"""
function get_type(str::String)
    global STR2TYPE
    return get(STR2TYPE, str) do 
        reload_types!()
        get(STR2TYPE, str) do
            error("There has been no type $str defined!")
        end
    end
end

end # module
