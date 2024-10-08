"""
    abstract type Modification

Modification represents an abstract type for really anything that would make changes to a model.

`Modification`s represent ways to modify the behavior of E4ST.  Some possible examples of `Modifications` (not necessarily implemented) include:
* Scale the NG price for each year
* Enforce a cap on carbon emissions in Colorado.
* Adding a national CES with changing target and benchmark rate
* Preventing the addition of new Nuclear Generation in PJM
* Logging a custom calculated result to file
* Plotting and saving a heat map of emissions by state as part of the results processing 
* The sky is the limit!

## Defining a `Modification`
When defining a concrete `Modification` type, you should know the following.
* Since Modifications are specified in a YAML config file, `Modification`s must be constructed with keyword arguments.  `Base.@kwdef` may come in handy here.
* All `Modication`s are paired with a name in the config file.  That name is automatically passed in as a keyword argument to the `Modification` constructor if the type has a `name` field.  The `name` will be passed in as a `Symbol`.

`Modification`'s can modify things in up to four places, with the default behavior of the methods being to make no changes:
* [`modify_raw_data!(mod, config, data)`](@ref) - In the data preparation step, right after [`read_data_files!(config, data)`](@ref) before setting up the data
* [`modify_setup_data!(mod, config, data)`](@ref) - In the data preparation step, right after [`setup_data!(config, data)`](@ref) before setting up the `Model`
* [`modify_model!(mod, config, data, model)`](@ref) - In the model setup step, after setting up the DC-OPF but before optimizing
* [`modify_results!(mod, config, data)`](@ref) - After optimizing the model, in the results generation step

Modifications get printed to YAML when the config file is saved at the beginning of a call to `run_e4st`.  If you implement a Modification for which it is undesirable to print every field, you can implement the following interface:
* [`fieldnames_for_yaml(::Type)`](@ref) - returns the desired fieldnames as a collection of `Symbol`s

Modification can be given a rank which will determine the order that they are called in when modifying the model. This can be important if a mod requires information calculated in a previous mod or needs to be applied on top of another mod. 
Ranks is specified by defining a method for [`mod_rank(::Type{<:Modification})`](@ref). The default rank is 0. Modifications that setup data and model features like `CCUS` and `DCLines` can have negative values to signify that they are called before
while mods like policies would have a positive rank meaning they would modify the model after the setup mods. 

## Specifying a `Modification` in the config file YAML
`Modifications` must be be specified in the config file.  They must have a type key, and keys for each other desired keyword argument in the constructor.

## An Example

Say we want to make a Modification to change the price of natural gas based on a table in a CSV file.

```julia
using E4ST, CSV, DataFrames
struct UpdateNGPrice <: Modification
    filename::String
    prices::DataFrame
end

# Define kwarg constructor
function UpdateNGPrice(; filename=nothing)
    filename === nothing && error("Must provide UpdateNGPrice with a filename")
    prices = CSV.read(filename, DataFrame)
    return UpdateNGPrice(filename, prices)
end

# Make sure YAML doesn't try printing out the whole prices table
function E4ST.fieldnames_for_yaml(::Type{UpdateNGPrice})
    return (:filename,)
end

function E4ST.modify_raw_data!(mod::UpdateNGPrice, config, data)
    # update the price of natural gas from mod.prices here
end
```

Now, to add this to the `mods` list in the config file:
```yaml
mods:
  ...                                   # other mods as needed
  update_ng_price:                      # This is the name of the mod
    type: UpdateNGPrice
    filename: "C:/path/to/file.csv"
  ...                                   # other mods as needed
```
"""
abstract type Modification end



"""
    Modification(p::Pair) -> mod

Constructs a Modification from `p`, a `Pair` of `name=>d`.  The Modification is of type `d[:type]` with keyword arguments for all the other key value pairs in `d`.
"""
function Modification(p::Pair)
    name, d = p
    T = get_type(d[:type])
    if hasfield(T, :name)
        mod = _discard_type(T; name, d...)
    else
        mod = _discard_type(T; d...)
    end
    return mod
end

"""
    function _discard_type(T; type=nothing, kwargs...)

Makes sure type doesn't get passed in as a keyword argument. 
"""
function _discard_type(T; type=nothing, kwargs...) 
    T(;kwargs...)
end


"""
    modify_raw_data!(mod::Modification, config, data, model)

Change the raw data with `mod`.
"""
function modify_raw_data!(mod::Modification, config, data)
    @info "No modify_raw_data! function defined for mod type $(typeof(mod)), doing nothing"
end

"""
    modify_setup_data!(mod::Modification, config, data, model)

Change the setup data with `mod`.
"""
function modify_setup_data!(mod::Modification, config, data)
    @info "No modify_setup_data! function defined for mod type $(typeof(mod)), doing nothing"
end


"""
    modify_model!(mod::Modification, config, data, model)

Apply mod to the model, called in `setup_model`
"""
function modify_model!(mod::Modification, config, data, model)
    @info "No modify_model! function defined for mod type $(typeof(mod)), doing nothing"
end

"""
    modify_results!(mod::Modification, config, data)

Gather the results from `mod` from the solved model, called in `parse_results!`
"""
function modify_results!(mod::Modification, config, data)
    @info "No modify_results! function defined for mod type $(typeof(mod)), doing nothing"
end

"""
    fieldnames_for_yaml(::Type{M}) where {M<:Modification}

returns the fieldnames in a yaml, used for printing, modified for different types of mods 
"""
function fieldnames_for_yaml(::Type{M}) where {M<:Modification}
    return setdiff(fieldnames(M), (:name,))
end
export fieldnames_for_yaml


"""
    function YAML._print(io::IO, mod::M, level::Int=0, ignore_level::Bool=false) where {M<:Modification}

Prints the field determined in fieldnames_for_yaml from the Modification. 
"""
function YAML._print(io::IO, mod::M, level::Int=0, ignore_level::Bool=false) where {M<:Modification}
    println(io)
    moddict = OrderedDict(:type => clean_type_string(mod), (k=>getproperty(mod, k) for k in fieldnames_for_yaml(M))...)
    YAML._print(io::IO, moddict, level, ignore_level)
end

"""
    function Base.getindex(mod::M, key) where {M<:Modification}

Returns value of the Modification for the given key (not index)
"""
function Base.getindex(mod::M, key::Symbol) where {M<:Modification}
    return getproperty(mod, key)
end



## Rank 

"""
    mod_rank(::Type{Modification}) -> 

Returns the rank of the Modification. 
Rank is the order in which the type of mod should be applied relative to other types of mods. 
Defaults to 0, where 1 would come after other mods and -1 would come before. 
Ranks is defined for mod types. 
"""
function mod_rank(::Type{<:Modification}) 
   return 0.0
end

mod_rank(m::Modification) = mod_rank(typeof(m))
export mod_rank

function list_type_ranks()
    global SYM2TYPE
    all_types = filter!(t -> t <: Modification, collect(values(SYM2TYPE)))
    ranks = OrderedDict{Any, Float64}()
    for t in all_types
        ranks[t] = mod_rank(t)
    end
    sort!(ranks; byvalue=true)
    return ranks
end
export list_type_ranks

function list_mod_ranks(config)
    mods = config[:mods]
    ranks = OrderedDict{Symbol, Float64}()
    for (k,v) in mods
        ranks[k] = mod_rank(v)
    end
    #ranks = DataFrame(:types = [k for (k,v) in mods], :rank = [mod_rank(v) for (k,v) in mods])
    sort!(ranks; byvalue=true)
    return ranks
end
export list_mod_ranks
