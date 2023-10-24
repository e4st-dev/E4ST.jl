"""
    e4st_post(post_config)

Runs post-processing on `post_config`.  See [`read_post_config`](@ref) for information about the `post_config`.  The general outline of post processing is:
* `post_data = ` [`extract_results(post_config)`](@ref): Create a `post_data` file and extract the results from each simulation from each mod into it.
* [`combine_results(post_config, post_data)`](@ref): allow the mod to combine anything into a single result, plot, etc.  Store any output into [`get_out_path(post_config)`](@ref).
"""
function e4st_post(post_config)

    post_data = extract_results(post_config)

    combine_results(post_config, post_data)
end

export e4st_post

e4st_post(filenames::String...; kwargs...) = e4st_post(read_post_config(filenames; kwargs...))

"""
    read_post_config(filenames...; create_out_path = true, kwargs...) -> post_config

Reads a config file for [`e4st_post`](@ref).  See [`summarize_post_config`](@ref) for the required fields.
"""
function read_post_config(filenames...; create_out_path = true, kwargs...)
    post_config = _read_config(filenames; kwargs...)
    check_post_config!(post_config)
    create_out_path && make_out_path!(post_config)
    convert_mods!(post_config)
    sort_mods_by_rank!(post_config)
    return post_config
end
export read_post_config

"""
    check_post_config!(post_config) -> nothing

Ensures that `post_config` has required fields listed in [`summarize_post_config`](@ref), adds defaults as needed.
"""
function check_post_config!(post_config)
    summary = summarize_post_config()
    _check_config!(post_config, summary)

    # Set up `sim_names` as needed
    if isnothing(post_config[:sim_names])
        sim_paths = post_config[:sim_paths]::Vector{String}
        post_config[:sim_names] = map(sim_paths) do sim_path
            config = YAML.load_file(filename, dicttype=OrderedDict{Symbol,Any})
            get(config, :sim_name) do
                @warn "No sim_name found for simulation results at $sim_path, using the path instead"
                sim_path
            end
        end
    end

    return nothing
end
export check_post_config!

@doc """
    summarize_post_config() -> summary

Summarizes the `post_config`, with columns for:
* `name` - the property name, i.e. key
* `required` - whether or not the property is required
* `default` - default value of this property
* `description`

$(table2markdown(summarize_post_config()))
"""
function summarize_post_config()
    df = DataFrame("name"=>Symbol[], "required"=>Bool[], "default"=>[], "description"=>String[])
    push!(df, 
        # Required
        (:sim_paths, true, nothing, "The paths to the desired simulation outputs."),
        (:sim_names, false, nothing, "The names of each of the sims. This will get used in post processing.  If none given, `e4st_post` will check the configs in each of the `sim_paths` to see if there is a `name` given."),
        (:base_sim_name, false, "", "The name of the base simulation to use for comparisons.  Used by Modifications"),
        (:out_path, true, nothing, "The path to the desired output path for the results of postprocessing."),
        (:mods, false, OrderedDict{Symbol, Modification}(), "A list of `Modification`s specifying changes for how `e4st_post` runs.  See [`extract_results`](@ref) and [`combine_results`](@ref)."),
    )
    return df
end
export summarize_post_config

"""
    get_sim_names(post_config) -> names::Vector{String}
"""
function get_sim_names(post_config)
    post_config[:sim_names]::Vector{String}
end
export get_sim_names

"""
    extract_results(post_config) -> post_data::OrderedDict{Symbol, Any}

Initializes `post_data`, and extracts results for each modification in `post_config[:mods]`, for each of the simulations in `post_config[:sim_paths]` and `post_config[:sim_names]`.  

Calls `extract_results(post_mod, config, data)` for each `post_mod`, where `config` is the simulation config, and `data` is the simulation data, read in from `read_processed_results`.
"""
function extract_results(post_config)
    post_data = OrderedDict{Symbol, Any}()
    post_mods = get_mods(post_config)
    sim_names = post_config[:sim_names]::Vector{String}
    sim_paths = post_config[:sim_paths]::Vector{String}
    

    # Initialize an OrderedDict for each mod to drop their results into.
    for (key, post_mod) in post_mods
        post_data[key] = OrderedDict{String, Any}()
    end

    # Pull in the processed results for each of the paths and transfer/compute necessary things, add to `post_data`
    for (sim_path, sim_name) in zip(sim_paths, sim_names)
        @info "Beginning extract_results for $sim_name"
        data = read_processed_results(sim_path)
        @info "Data has been read, starting result extraction"
        config = read_config(sim_path)
        for (key, post_mod) in post_mods
            post_data[key][sim_name] = extract_results(post_mod, config, data)
        end
        @info "Done extracting results"
        
    end
    return post_data
end
export extract_results


"""
    extract_results(post_mod::Modification, config, data) -> results

One of the main steps in [`e4st_post`](@ref).  Extract results (or compute new ones) from `data` (the full set of `data` deserialized from an E4ST run).  This will get stored into an `OrderedDict` mapping `sim_name` to `results`.  See [`combine_results`](@ref) for the next step.

Note that we do this to prevent excessive memory usage.  If [`e4st_post`](@ref) is run with a large number of simulations, storing the entire set of `data` in memory for all of them may cost too much RAM.
"""
function extract_results(post_mod::Modification, config, data)
end


"""
    combine_results(post_config, post_data) -> nothing

Combine results for each of the `mods` in `post_config[:mods]`.  Calls `combine_results(post_mod, post_config, post_mod_data)`, where `post_mod_data` is `post_data[mod_name]`.
"""
function combine_results(post_config, post_data)
    # Pull out the mods
    post_mods = get_mods(post_config)

    # Combine results
    for (key, post_mod) in post_mods
        combine_results(post_mod, post_config, post_data[key])
    end
end
export combine_results

"""
    combine_results(post_mod::Modification, post_config, post_mod_data)

Combine results and probably save them to the out path specified in `post_config`.

`post_mod_data` is the porton of `post_data` for this particular `post_mod`, an OrderedDict mapping `sim_name` to the extracted `results` from [`extract_results`](@ref).
"""
function combine_results(post_mod::Modification, post_config, post_data)
end


"""
    join_sim_tables(post_mod_data, keep_col)

Joins tables for multiple sims stored in `post_mod_data`, with `keep_col` as the column to keep, and the remaining columns as the joining columns.

* `replace_missing` - replaces missing values in res after the tables are joined with the value of the kw arg. To keep missing values, set replace_missing = missing. 
"""
function join_sim_tables(post_mod_data, keep_col; replace_missing = 0.)
    first_sim_name = first(keys(post_mod_data))
    res = deepcopy(post_mod_data[first_sim_name])
    joining_cols = filter!(!=(string(keep_col)), names(res))
    rename!(res, keep_col=>first_sim_name)

    for (sim_name, df) in post_mod_data
        sim_name === first_sim_name && continue
        res = outerjoin(res, df, on=joining_cols, matchmissing=:equal)
        rename!(res, keep_col=>sim_name)
    end

    # Call dropmissing to change the types from Vector{Union{Missing, etc}}
    for col in names(res)
        replace!(res[!, col], missing=>replace_missing)
    end

    dropmissing!(res)

    sort!(res)

    return res
end
export join_sim_tables
