"""
    setup_model(config, data) -> model
"""
function setup_model(config, data)
    log_header("SETTING UP MODEL")

    optimizer_factory = getoptimizer(config)
    model = JuMP.Model(optimizer_factory)

    setup_dcopf!(config, data, model)

    for mod in getmods(config)
        apply!(mod, config, data, model)
    end

    @objective(model, Min, model[:obj])

    @info "Model Summary: $(summarize(model))"

    return model
end

"""
    summarize(model::Model) -> summary::String

Returns the string that would be output by show(model).
"""
function summarize(model::Model)
    buf = IOBuffer() 
    show(buf, model)
    summary = String(take!(buf))
    return summary
end

"""
    getoptimizer(config) -> optimizer_factory
"""
function getoptimizer(config)
    opt_type_str = config[:optimizer][:type]
    opt_type = getoptimizertype(opt_type_str)
    return optimizer_with_attributes(
        opt_type,
        optimizer_attributes_pairs(config)...
    )
end
function optimizer_attributes_pairs(config, args...; kwargs...)
    nt = optimizer_attributes(config, args...; kwargs...)
    return (string(i)=>nt[i] for i in eachindex(nt))
end

"""
    optimizer_attributes(config) -> attributes::NamedTuple

Returns the default optimizer attributes associated with `config`, as a named tuple.
"""
function optimizer_attributes(config::AbstractDict)
    optimizer_attributes(config; config[:optimizer]...)
end
function optimizer_attributes(config; type=nothing, kwargs...)
    optimizer_attributes(config, Val(Symbol(type)); kwargs...)
end


"""
    optimizer_attributes(config, ::Val{T}; kwargs...) -> attributes::NamedTuple

Returns the optimizer attributes associated with `T`, with defaults overwritten by `kwargs`, as a named tuple.
"""
function optimizer_attributes(config, ::Val{T}; kwargs...) where T
    @warn "No default optimizer attributes defined for type $T"
end
function optimizer_attributes(config, ::Val{:HiGHS}; log_file = nothing, kwargs...)
    if log_file == nothing
        log_file_full = abspath(config[:out_path], "HiGHS.log")
    elseif ispath(dirname(log_file))
        log_file_full = log_file
    else
        log_file_full = abspath(config[:out_path], log_file)
    end
    (;
        dual_feasibility_tolerance   = 1e-7, # Notional, not sure what this should be
        primal_feasibility_tolerance = 1e-7,
        log_to_console = false,
        # log_file = log_file_full,
        kwargs...
    )
end
function optimizer_attributes(config, ::Val{:Gurobi}; kwargs...)
    # These defaults came from e4st_core.m
    (;
        NumericFocus    = 0,
        BarHomogeneous  =-1,
        method          = 2,
        BarIterLimit    = 1000,
        Crossover       = 0,
        FeasibilityTol  = 1e-2,
        OptimalityTol   = 1e-6,
        BarConvTol      = 1e-6,
        kwargs...
    )
end

function get_model_val_by_gen(data, model, name::Symbol, idxs = :, year_idxs = :, hour_idxs = :)

    _idxs, _year_idxs, _hour_idxs = get_gen_idxs(data, idxs, year_idxs, hour_idxs)
    v = _view_model(model, name, _idxs, _year_idxs, _hour_idxs)
    return sum(value, v)
end
export get_model_val_by_gen

function _view_model(model, name, idxs, year_idxs, hour_idxs)
    var = model[name]::Array{<:Any, 3}
    return view(var, idxs, year_idxs, hour_idxs)
end

function get_gen_idxs(data, idxs, year_idxs, hour_idxs)
    _idxs = get_gen_idxs(data, idxs)
    _year_idxs = get_year_idxs(data, year_idxs)
    _hour_idxs = get_hour_idxs(data, hour_idxs)
    return _idxs, _year_idxs, _hour_idxs
end
function get_gen_idxs(data, idxs)
    return table_rows(get_gen_table(data), idxs)
end
export get_gen_idxs

function get_year_idxs(data, year_idxs::Colon)
    year_idxs
end
function get_year_idxs(data, year_idxs::AbstractVector{Int64})
    year_idxs
end
function get_year_idxs(data, year_idxs::Int64)
    year_idxs
end
function get_year_idxs(data, year_idxs::AbstractString)
    return findfirst(==(y), get_years(data))
end
function get_year_idxs(data, year_idxs::AbstractVector{<:AbstractString})
    yrs = get_years(data)
    return map(y->findfirst(==(y), yrs), year_idxs)
end
export get_year_idxs


function get_hour_idxs(data, year_idxs::Colon)
    year_idxs
end
function get_hour_idxs(data, year_idxs::AbstractVector{Int64})
    year_idxs
end
function get_hour_idxs(data, year_idxs::Int64)
    year_idxs
end
export get_hour_idxs

function table_rows(table, idxs::Colon)
    return idxs
end

function table_rows(table, idxs::AbstractVector{Int64})
    return idxs
end

function table_rows(table, idxs::Int64)
    return idxs
end

function table_rows(table, pairs)
    row_idxs = Int64[i for i in 1:nrow(table)]
    for pair in pairs
        key, val = pair
        v = table[key, !]
        comp = ==(val)
        filter!(row_idx->comp(v[row_idx]), row_idxs)
    end

    return row_idxs
end
function table_rows(table, pair::Pair)
    row_idxs = Int64[i for i in 1:nrow(table)]
    key, val = pair
    v = table[!, key]
    comp = ==(val)
    filter!(row_idx->comp(v[row_idx]), row_idxs)
    return row_idxs
end