"""
    struct RunSequential <: Iterable

    RunSequential(;years)

Runs E4ST sequentially by running `years` (or sets of years) one after another.  Overwrites `config[:years]`, throwing a warning if the first set in `iter` is different than that in the config.
* `years = ["y2020", "y2025"]`: this will run E4ST twice, once for each year
* `years = ["y2020", ["y2025", "y2030"]]`: this will run E4ST twice, once for `"y2020"` and once for `["y2025", "y2030"]`
"""
mutable struct RunSequential <: Iterable
    years::Vector
    state::Int64
    function RunSequential(;years)
        return new(years, 1)
    end
end
export RunSequential

fieldnames_for_yaml(::Type{RunSequential}) = (:years,)

"""
    init!(iter::RunSequential, config)

Sets up a new `config[:out_path]` by appending `iter1` to `config[:out_path]`
"""
function init!(iter::RunSequential, config)
    @info "Initializing RunSequential iterable"
    iter.state = 1
    
    # Set up a new out path for the iteration
    iter_string = get_iter_string(iter)
    out_path_tmp = joinpath(config[:out_path], iter_string)
    mkpath(out_path_tmp)
    @info "Setting config[:out_path] to be $out_path_tmp"
    config[:out_path] = out_path_tmp

    # Set up the years
    years = check_years(iter.years[iter.state])
    if years != config[:years]
        @warn "config[:years] different than years specified in RunSequential iterator.\n    config[:years] = $(config[:years])\n    iter.years[1] =  $years"
        config[:years] = years
    end

    save_config(config)
end

"""
    should_iterate(iter::RunSequential, args...) -> ::Bool

Returns true if E4ST has run through each of the sets of years in `iter.years`
"""
function should_iterate(iter::RunSequential, args...)
    return iter.state < length(iter.years)
end

"""
    iterate!(iter::RunSequential, config, data) -> nothing

Iterates by:
* Incrementing the years in the config
* Changing the `config[:out_path]` to be `"iter<n>"`
* Changing `config[:gen_file]`
"""
function iterate!(iter::RunSequential, config, data)
    # Increment iter.state
    iter.state += 1
    
    # Update config[:out_path]
    old_out_path = config[:out_path]
    iter_string = get_iter_string(iter)
    new_out_path = abspath(old_out_path, "..", iter_string)
    mkpath(new_out_path)
    @info "Setting config[:out_path] to be $new_out_path"
    config[:out_path] = new_out_path

    # Update the years
    config[:year_gen_data] = last(config[:years])
    years = check_years(iter.years[iter.state])
    config[:years] = years
    
    config[:gen_file] = abspath(old_out_path, "gen.csv")
    
    mods = get_mods(config)

    for m in values(mods)
        m isa Storage || continue
        m.file = abspath(old_out_path, "storage.csv")
    end
    
    save_config(config)
    return nothing
end

function get_iter_string(iter::RunSequential)
    get_iter_string(iter.years, iter.state)
end

function get_iter_string(years::Vector{<:AbstractString}, state)
    years[state] |> YearString
end

function get_iter_string(years::Vector{<:Integer}, state)
    years[state] |> YearString
end

function get_iter_string(years, state)
    iter_str_length = ceil(Int, log10(length(years)))
    string("iter", lpad(state, iter_str_length, "0"))
end

"""
    should_reread_data(::RunSequential) -> true
"""
function should_reread_data(::RunSequential)
    true
end


