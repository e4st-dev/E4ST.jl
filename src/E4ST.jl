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

export save_config, read_config
export read_data

export setup_model, check
export setup_dcopf!
export parse_results!, process_results!
export should_iterate, iterate!
export Modification, Policy
export modify_raw_data!, modify_setup_data!, modify_model!, modify_results!, fieldnames_for_yaml
export run_e4st
export setup_new_gens!

# Include types
include("types/Modification.jl")
include("types/Policy.jl")
include("types/Unit.jl")
include("types/Containers.jl")
include("types/Iterable.jl")
include("types/Term.jl")

# Include Modifications
include("types/modifications/DCLine.jl")
include("types/modifications/AggregationTemplate.jl")
include("types/modifications/GenerationConstraint.jl")
include("types/modifications/YearlyTable.jl")
include("types/modifications/CCUS.jl")

# Include Policies
include("types/policies/ITC.jl")
include("types/policies/PTC.jl")
#include("types/policies/RPS.jl")
include("types/policies/EmissionCap.jl")
include("types/policies/EmissionPrice.jl")

# Include Iterables
include("types/iterables/RunOnce.jl")
include("types/iterables/RunSequential.jl")

#Include IO
include("io/config.jl")
include("io/data.jl")
include("io/adjust.jl")
include("io/load.jl")
include("io/util.jl")

# Include model
include("model/setup.jl")
include("model/dcopf.jl")
include("model/check.jl")
include("model/newgens.jl")
include("model/util.jl")

# Include Results
include("results/parse.jl")
include("results/process.jl")
include("results/aggregate.jl")
include("results/util.jl")


"""
    run_e4st(config) -> out_path, results

    run_e4st(filename(s)) -> out_path, results

Top-level function for running E4ST.  Here is a general overview of what happens:
1. Book-keeping
    * [`read_config(config_file)`](@ref) - loads in the `config` from file, if not passed in directly.  
    * [`save_config(config)`](@ref) - the config is saved to `config[:out_path]`
    * [`start_logging!(config)`](@ref) - Logging is started, some basic information is logged via [`log_start`](@ref).
2. Load Input Data
    * [`read_data(config)`](@ref) - The data is loaded in from files specified in the `config`.
3. Construct JuMP Model and optimize
    * [`setup_model(config, data)`](@ref) - The `model` (a JuMP Model) is set up.
    * [`JuMP.optimize!(model)`](https://jump.dev/JuMP.jl/stable/reference/solutions/#JuMP.optimize!) - The `model` is optimized.
4. Process Results
    * [`parse_results!(config, data, model)`](@ref) - Retrieves all necessary values and shadow prices from `model`, storing them into data[:results][:raw], (see [`get_raw_results`](@ref) and [`get_results`](@ref)) and saves `data` if `config[:save_data_parsed]` is `true` (default is `true`).  This is mostly stored in case the results processing throws an error before completion.  That way, there is no need to re-run the model.
    * [`process_results!(config, data)`](@ref) - Calls [`modify_results!(mod, config, data)`](@ref) for each `mod` in the `config`. Saves `data` if `config[:save_data_processeded]` is `true` (default is `true`)
5. Iterate, running more simulations as needed.
    * See [`Iterable`](@ref) and [`read_config`](@ref) for more information.
"""
function run_e4st(config::OrderedDict)

    # Initial config setup
    save_config(config)
    start_logging!(config)

    # Initialize the iterator
    iter = get_iterator(config)
    init!(iter, config)

    # Load in all the data
    data  = read_data(config)

    # Initialize the results
    all_results = []

    ### Begin iteration loop
    while true
        model = setup_model(config, data)
    
        log_header("OPTIMIZING MODEL!")
        optimize!(model)
        log_header("MODEL OPTIMIZED!")

        check(model) || return model # all_results

        ### Results
        parse_results!(config, data, model)
        process_results!(config, data)
        results = get_results(data)
        push!(all_results, results)

        ### Iteration
        # First check to see if we even need to iterate
        should_iterate(iter, config, data) || break

        # Now make any changes to things based on the iteration
        iterate!(iter, config, data)

        # Reload data as needed
        should_reread_data(iter) && read_data!(config, data)
    end

    stop_logging!(config)
    return get_out_path(config), all_results
end

run_e4st(path...) = run_e4st(read_config(path...))

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
            error("There is no AbstractOptimizer defined called $s, or $s has not been imported yet!")
        end
    end
end

"""
    reload_types!()

    reload_types!(::Type)

Loads all types associated with E4ST so that the type will accessible by string with `get_type(str)`.
"""
function reload_types!()
    global STR2TYPE
    global SYM2TYPE
    for n in names(E4ST)
        try
            T = getfield(E4ST, n)
            if T isa Type
                reload_types!(T)
            end
        catch
            @warn "No definition for name `$n` - consider removing the export statement, or defining it."
        end
    end
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
Core.AbstractString(s) = string(s)

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
