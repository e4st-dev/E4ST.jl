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
export load_data
export save_results!, load_results

export setup_model, check
export setup_dcopf!
export parse_results, process_results
export should_iterate, iterate!
export Modification, Policy
export modify_raw_data!, modify_setup_data!, modify_model!, modify_results!, fieldnames_for_yaml
export run_e4st
export setup_new_gens!

#Include types
include("types/Modification.jl")
include("types/Policy.jl")
include("types/Unit.jl")
include("types/Containers.jl")
include("types/AggregationTemplate.jl")

#Include policies
include("types/policies/ITC.jl")
include("types/policies/PTC.jl")

#Include IO
include("io/config.jl")
include("io/data.jl")
include("io/adjust.jl")
include("io/util.jl")
include("io/demand.jl")
include("io/results.jl")

#Include model
include("model/setup.jl")
include("model/dcopf.jl")
include("model/check.jl")
include("model/results.jl")
include("model/iteration.jl")
include("model/newgens.jl")


"""
    run_e4st(config) -> results

    run_e4st(filename) -> run_e4st(load_config(filename))

Top-level function for running E4ST.  Here is a general overview of what happens:
1. Book-keeping
    * [`load_config(config_file)`](@ref) - loads in the `config` from file, if not passed in directly.  
    * [`save_config(config)`](@ref) - the config is saved to `config[:out_path]`
    * [`start_logging!(config)`](@ref) - Logging is started
    * [`log_info`](@ref) - some information is logged.
2. Load Input Data
    * [`load_data(config)`](@ref) - The data is loaded in from files specified in the `config`.
3. Construct JuMP Model and optimize
    * [`setup_model(config, data)`](@ref) - The `model` (a JuMP Model) is set up.
    * [`JuMP.optimize!(model)`](https://jump.dev/JuMP.jl/stable/reference/solutions/#JuMP.optimize!) - The `model` is optimized.
4. Process Results
    * TODO: Add more here for the results processing stuff once we get to it
5. Iterate, running more simulations as needed.
    * See [`Iterable`](@ref) and [`load_config`](@ref) for more information.
"""
function run_e4st(config)
    save_config(config)

    start_logging!(config)

    log_start(config)

    data  = load_data(config)
    model = setup_model(config, data)
    optimize!(model)
    check(model)

    all_results = []

    results_raw = parse_results(config, data, model)
    results_user = process_results(config, data, results_raw)
    push!(all_results, results_user)
    
    # Iteration: Check to see if the model should keep iterating.  See the Iteratable interface in model/iteration.jl for more information
    iter = get_iterator(config)
    while should_iterate(iter, config, data, model, results_raw, results_user)
        iterate!(iter, config, data, model, results_raw, results_user)
        data = should_reload_data(iter) ? load_data(config) : data

        model = setup_model(config, data)

        optimize!(model)
        check(model)

        results_raw = parse_results(config, data, model)
        results_user = process_results(config, data, results_raw)
        push!(all_results, results_user)
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
    reload_types!(Unit)
    reload_types!(AbstractString)
    reload_types!(AbstractFloat)
    reload_types!(Integer)
end
function reload_types!(::Type{T}) where T
    global STR2TYPE
    global SYM2TYPE
    symtype = Base.typename(T).name
    SYM2TYPE[symtype] = T
    strtype = string(symtype)
    STR2TYPE[strtype] = T
    for type in subtypes(T)
        symtype = Base.typename(type).name
        SYM2TYPE[symtype] = type
        strtype = string(symtype)
        STR2TYPE[strtype] = type
        if isabstracttype(type)
            reload_types!(type)
        end
    end
end

Core.Type(s::AbstractString) = get_type(String(s))
Core.Type(s::Symbol) = get_type(s)
Core.AbstractString(s) = String(s)

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

function get_type(str::AbstractString)
    global STR2TYPE
    return get(STR2TYPE, str) do 
        reload_types!()
        get(STR2TYPE, str) do
            error("There has been no type $str defined!")
        end
    end
end

end # module
