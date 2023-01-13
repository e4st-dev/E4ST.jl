module E4ST

# General Packages
using JuMP
using InteractiveUtils
using DataFrames
using Serialization
using Logging
using MiniLoggers
using Pkg
import Dates: @dateformat_str, format, now
import OrderedCollections: OrderedDict
import CSV
import YAML
import JuMP.MOI.AbstractOptimizer

# E4ST Packages
using E4STUtil

export save_config, load_config
export load_data, initialize_data!
export save_results!, load_results

export setup_model, check
export setup_dcopf!
export parse_results, process!
export should_iterate, iterate!
export Modification, Policy
export modify_raw_data!, modify_setup_data!, apply!, results!, fieldnames_for_yaml
export run_e4st

include("types/Modification.jl")
include("types/Policy.jl")
include("io/config.jl")
include("io/data.jl")
include("io/util.jl")
include("io/demand.jl")
include("io/results.jl")
include("model/setup.jl")
include("model/dcopf.jl")
include("model/check.jl")
include("model/results.jl")
include("model/iteration.jl")


"""
    run_e4st(config) -> results

    run_e4st(filename) -> run_e4st(load_config(filename))

Top-level file for running E4ST
"""
function run_e4st(config)
    save_config(config)

    start_logging!(config)
    log_info(config)
    @info "Config saved to: $(config[:out_path])"

    data  = load_data(config)
    model = setup_model(config, data)


    optimize!(model)
    check(model)

    all_results = []

    parse_results!(config, data, model, all_results)  
    process!(config, all_results)

    iter = get_iterator(config)

    while should_iterate(iter, config, data, model, all_results)
        iterate!(iter, config, data, model, all_results)
        data = should_reload_data(iter) ? load_data(config) : data

        model = setup_model(config, data)

        # Optimize and save
        optimize!(model)

        check(model)
        parse_results!(config, data, model, all_results)
        process!(config, all_results)
    end

    stop_logging!(config)
    return all_results
end

run_e4st(path::String) = run_e4st(load_config(path))

global STR2TYPE = Dict{String, Type}()
global SYM2TYPE = Dict{Symbol, Type}()
global STR2OPT= Dict{String, Type}()

function reload_optimizers!()
    global STR2OPT
    for type in subtypes(AbstractOptimizer)
        if isconcretetype(type)
            s = string(parentmodule(type))
            STR2OPT[s] = type
        end
    end
end

function getoptimizertype(s::String)
    global STR2OPT
    return get(STR2OPT, s) do 
        reload_optimizers!()
        get(STR2OPT, s) do
            error("There is no AbstractOptimizer defined in $s, or $s has not been imported yet!")
        end
    end
end

"""
    reload_types!()

    reload_types!(::Type)

Loads all types associated with E4ST so that the type will accessible by string with `get_type(str)`.
"""
function reload_types!()
    reload_types!(Modification)
    reload_types!(Iterable)
end
function reload_types!(::Type{T}) where T
    global STR2TYPE
    global SYM2TYPE
    for type in subtypes(T)
        symtype = Symbol(type)
        SYM2TYPE[symtype] = type
        strtype = string(type)
        STR2TYPE[strtype] = type
        if isabstracttype(type)
            reload_types!(type)
        end
    end
end

"""
    get_type(sym::Symbol) -> type (preferred)

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
function get_type(sym::Symbol)
    global SYM2TYPE
    return get(SYM2TYPE, sym) do 
        reload_types!()
        get(SYM2TYPE, sym) do
            error("There has been no type $sym defined!")
        end
    end
end

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
