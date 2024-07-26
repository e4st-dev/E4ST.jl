"""
    match_capacity!(data, model, table_name::Symbol, pcap_name::Symbol, name::Symbol, sets::Vector{Vector{Int64}})

Constrains `sets` of generator indices so that their `pcap_gen` values sum to the max and min specified in the first member of the set.  The names of the constraints are:
* `Symbol("cons_pcap_max_\$name")`
* `Symbol("cons_pcap_min_\$name")`
"""
function match_capacity!(data, model, table_name::Symbol, pcap_name::Symbol, name::Symbol, sets::Vector{Vector{Int64}})
    nset = length(sets)
    nhour = get_num_hours(data)
    nyear = get_num_years(data)
    gen = get_table(data, table_name)
    pcap = model[pcap_name]

    # Set up the names of the constraints
    name_max = Symbol("cons_$(pcap_name)_match_max_$name")
    name_min = Symbol("cons_$(pcap_name)_match_min_$name")

    # Constrain the max capacity to add up to the desired max capacity
    model[name_max] = @constraint(model,
        [set_idx=1:nset, yr_idx = 1:nyear],
        sum(pcap[idx, yr_idx] for idx in sets[set_idx]) <= get_table_num(data, table_name, :pcap_max, first(sets[set_idx]), yr_idx, :)
    )
    
    # Lower bound the capacities with zero
    for set in sets
        for idx in set
            for yr_idx in 1:nyear
                is_fixed(pcap[idx, yr_idx]) && continue
                set_lower_bound(pcap[idx, yr_idx], 0.0)
            end
        end
    end

    # Constrain the minimum capacities to add up to the desired min capacity
    model[name_min] = @constraint(model,
        [set_idx=1:nset, yr_idx = 1:nyear],
        sum(pcap[idx, yr_idx] for idx in sets[set_idx]) >= get_table_num(data, table_name, :pcap_min, first(sets[set_idx]), yr_idx, :)
    )

    return nothing
end
export match_capacity!


"""
    add_build_constraints!(data, model, table_name, pcap_name)

Adds constraints to the model for:
* `cons_<pcap_name>_prebuild` - Constrain Capacity to 0 before the start/build year 
* `cons_<pcap_name>_noadd` - Constrain existing capacity to only decrease (only retire, not add capacity)
* `cons_<pcap_name>_exog` - Constrain unbuilt exogenous or real generators to be built to pcap0 in the first year after year_on
* `cons_<pcap_name>_match_min_build` - Constrain minimum capacity of generators at the same site to add up to the >= minimum capacity.
* `cons_<pcap_name>_match_min_build` - Constrain minimum capacity of generators at the same site to add up to the <= maximum capacity. 
"""
function add_build_constraints!(data, model, table_name::Symbol, pcap_name::Symbol, pgen_name::Symbol)
    @info "Adding build constraints for table $table_name"

    table = get_table(data, table_name)
    years = get_years(data)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)

    pcap = model[pcap_name]::Matrix{VariableRef}
    pgen = model[pgen_name]::Array{VariableRef, 3}
    years = get_years(data)

    year_built_idx = map(eachrow(table)) do r
        # Retrieve the investment year (either the retrofit year or the build year)
        year_retrofit = get(r, :year_retrofit, "")
        year_invest = isempty(year_retrofit) ? r.year_on : year_retrofit

        yr_idx = findlast(year -> year_invest >= year, years)
        yr_idx === nothing || return yr_idx
        year_invest < first(years) && return 1
        return length(years) + 1
    end

    # Constrain Capacity to 0 before the start/build year 
    if any(>(first(years)), table.year_on)
        for row_idx in axes(table, 1), yr_idx in 1:nyr
            yr_idx >= year_built_idx[row_idx] && continue
            fix(pcap[row_idx, yr_idx], 0.0; force=true);
        end
    end

    # Constrain existing capacity to only decrease (only retire, not add capacity)
    if nyr > 1
        name = Symbol("cons_$(pcap_name)_noadd")
        model[name] = @constraint(model, 
            [
                row_idx in axes(table,1),
                yr_idx in 1:(nyr-1);
                yr_idx >= year_built_idx[row_idx]
            ], 
            pcap[row_idx, yr_idx+1] <= pcap[row_idx, yr_idx])
    end

    # Constrain unbuilt exogenous generators to be built to pcap0 in the first year after year_on
    if any(row->(row.build_type ∈ ("real", "exog") && row.build_status == "unbuilt" && last(years) >= row.year_on), eachrow(table))
        for row_idx in axes(table,1), yr_idx in 1:nyr
            if table.build_type[row_idx] ∈ ("exog", "real") && 
                    table.build_status[row_idx] == "unbuilt" &&
                    yr_idx == year_built_idx[row_idx]
                fix(pcap[row_idx, yr_idx], table.pcap_max[row_idx], force=true)
            end
        end
    end

    # Enforce retirement
    for (i, row) in enumerate(eachrow(table))
        year_shutdown = row.year_shutdown
        isempty(year_shutdown) && continue
        year_shutdown > last(years) && continue
        yr_off_idx = findfirst(>=(year_shutdown), years)
        for yr_idx in yr_off_idx:nyr
            fix(pcap[i, yr_idx], 0.0, force=true)
            for hr_idx in 1:nhr
                fix(pgen[i, yr_idx, hr_idx], 0.0, force=true)
            end
        end
    end

    # Make capacities of sites add up for endogenous sites
    matching_rows = Vector{Int64}[]
    grouping_cols = intersect!([:bus_idx, :build_id, :genfuel, :gentype, :pcap_max], propertynames(table))
    st = get_subtable(table, :build_type=>"endog")
    gdf = groupby(st, grouping_cols)
    for key in keys(gdf)
        isempty(key.build_id) && continue
        sdf = gdf[key]
        nrow(sdf) <= 1 && continue
        row_idxs = getfield(sdf, :rows)
        push!(matching_rows, row_idxs)
    end

    if !isempty(matching_rows)
        match_capacity!(data, model, table_name, pcap_name, :build, matching_rows)
    end
end
export add_build_constraints!

function Base.getindex(ex::GenericAffExpr{V, K}, x::K) where {K, V}
    return get(ex.terms, x, zero(V))
end

function Base.getindex(ex::GenericAffExpr{V, K}, x) where {K, V}
    return 0.0
end


"""
    get_gentype_cf_hist(gentype::AbstractString)

These defaults are used to set historical capacity factor if no cf_hist column is provided. It is much prefered to provide a cf_hist column as these defaults currently come from a previous E4ST run and are set by gentype. 
"""
function get_gentype_cf_hist(gentype::AbstractString)
    # default cf are drawn from a previous E4ST run, using the year 2030 with baseline policies including the IRA
    # they could be updated over time and it is much better to specify cf_hist in the gen and build_gen tables
    # E4ST run: OSW 230228, no_osw_build_230228
    gentype == "nuclear" && return 0.92
    gentype == "ngcc" && return 0.58
    gentype == "ngt" && return 0.04 
    gentype == "ngo" && return 0.06 
    gentype == "ngccccs" && return 0.55
    gentype == "coal" && return 0.68
    gentype == "igcc" && return 0.55 # this is taken from the EIA monthly average coal (in general)
    gentype == "coalccs_new" && return 0.85 # set to same as ret because no new in run
    gentype == "coal_ccus_retrofit" && return 0.85 
    gentype == "solar" && return 0.25
    gentype == "dist_solar" && return 0.25 # set to same as solar
    gentype == "wind" && return 0.4
    gentype == "oswind" && return 0.39 
    gentype == "geothermal" && return 0.77 
    gentype == "deepgeo" && return 0.77 # set to same as geothermal
    gentype == "biomass" && return 0.48 
    #battery, unsure what to do for this but should mostly recieve itc anyways
    gentype == "hyc" && return 0.43 
    gentype == "hyps" && return 0.11 
    gentype == "hyrr" && return 0.39 
    gentype == "oil" && return 0.01 
    # hcc_new, unsure
    # hcc_ret, unsure
    gentype == "other" && return 0.67

    @warn "No default cf_hist provided for $(gentype) in E4ST, setting to 0.35"
    return 0.35 # overall system capacity factor
end
export get_gentype_cf_hist
