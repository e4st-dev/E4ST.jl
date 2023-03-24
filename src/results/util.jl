"""
    load_parsed_results(config) -> data

    load_parsed_results(out_path) -> data

Loads `data` in from `get_out_path(config, "data_parsed.jls")`.
"""
function load_parsed_results(config::OrderedDict)
    load_parsed_results(get_out_path(config))
end
function load_parsed_results(out_path::AbstractString)
    file = joinpath(out_path, "data_parsed.jls")
    isfile(file) || error("No parsed data file found at $file")
    return deserialize(file)
end
export load_parsed_results

"""
    load_processed_results(config) -> data

    load_processed_results(out_path) -> data

Loads `data` in from `data_processed.jls`.
"""
function load_processed_results(config::OrderedDict)
    return load_processed_results(get_out_path(config))
end
function load_processed_results(out_path::AbstractString)
    file = joinpath(out_path, "data_processed.jls")
    isfile(file) || error("No parsed data file found at $file")
    return deserialize(file)
end
export load_processed_results

"""
    get_raw_results(data) -> raw::Dict{Symbol, Any}
"""
function get_raw_results(data)
    results = get_results(data)
    return results[:raw]::Dict{Symbol, Any}
end
export get_raw_results

"""
    get_raw_result(data, name) -> x

Retrieves the raw result in `data[:raw][name]`.  See also [`get_raw_results`](@ref).
"""
function get_raw_result(data, name)
    raw = get_raw_results(data)
    return raw[Symbol(name)]
end
export get_raw_result

"""
    get_results(data) -> results::OrderedDict{Symbol, Any}
"""
function get_results(data)
    return data[:results]::OrderedDict{Symbol, Any}
end
export get_results

"""
    add_result!(data, name, result) -> nothing

Adds `result` to `data[:results]`.  See also [`get_result`](@ref)
"""
function add_result!(data, name, result)
    results = get_results(data)
    results[Symbol(name)] = result
    return nothing
end
export add_result!

"""
    get_result(data, name) -> retult

Retrieves `data[:results][name]`.  See also [`add_results!`](@ref)
"""
function get_result(data, name)
    results = get_results(data)
    return results[Symbol(name)]
end
export get_result

# ECR: I don't think we'll ever use the function below, commenting out for now.
# """
#     weight_hourly!(data, ar)
#     weight_hourly!(data, ar, sign=+)

# Multiplies (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
# """
# function weight_hourly!(data, ar, s=+)
#     weights = get_hour_weights(data)
#     for (hr_idx, hr_wgt) in enumerate(weights)
#         v = view(ar, :, :, hr_idx)
#         _hr_wgt = s(hr_wgt)
#         v .*= _hr_wgt
#     end
#     return
# end
# export weight_hourly!

"""
    weight_hourly(data, ar, sign=+)

Multiplies each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function weight_hourly(data, ar::AbstractArray{<:Real, I}, s=+) where I
    w = get_hour_weights(data)
    return [s(ar[ci]) * w[ci[I]] for ci in CartesianIndices(ar)]
end
function weight_hourly(data, v::Vector{<:Container}, s=+)
    w = get_hour_weights(data)
    ny = get_num_years(data)
    nh = get_num_hours(data)
    return [s(v[i][y,h]) * w[h] for i in 1:length(v), y in 1:ny, h in 1:nh]
end
export weight_hourly




# ECR: I don't think we'll ever use the function below, commenting out for now.
# """
#     unweight_hourly!(data, ar, sign=+)

# Divides (inplace) each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
# """
# function unweight_hourly!(data, ar, s=+)
#     weights = get_hour_weights(data)
#     for (hr_idx, hr_wgt) in enumerate(weights)
#         v = view(ar, :, :, hr_idx)
#         inv_hr_weight = s(1/hr_wgt)
#         v .*= inv_hr_weight
#     end
#     return
# end
# export unweight_hourly!

"""
    unweight_hourly(data, ar, sign=+)

Multiplies each member of `ar` by its hourly weight, assuming the last index set of `ar` is hour indices.
"""
function unweight_hourly(data, ar::AbstractArray{<:Any, I}, s=+) where I
    w = get_hour_weights(data)
    return [s(ar[ci]) / w[ci[I]] for ci in CartesianIndices(ar)]
end

function unweight_hourly(data, v::Vector{<:Container}, s=+)
    w = get_hour_weights(data)
    ny = get_num_years(data)
    nh = get_num_hours(data)
    return [s(v[i][y,h]) / w[h] for i in 1:length(v), y in 1:ny, h in 1:nh]
end
export unweight_hourly
