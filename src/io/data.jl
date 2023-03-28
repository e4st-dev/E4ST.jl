################################################################################
# Main Data Interfaces
################################################################################

"""
    load_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`.

Calls the following functions:
* [`load_data_files!(config, data)`](@ref) - load in the data from files
* [`modify_raw_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the raw data before the data gets setup.
* [`setup_data!(config, data)`](@ref) - Sets up the data, modifying/adding to the tables as needed.
* [`modify_setup_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the setup data before the model is built.
"""
function load_data(config)
    log_header("LOADING DATA")

    # Try loading the data directly
    if haskey(config, :data_file)
        @info "Loading data from $(config[:data_file])"
        data = deserialize(config[:data_file])
        return data
    end
    data = OrderedDict{Symbol, Any}()
    
    load_data!(config, data)

    return data
end

"""
    load_data!(config, data) -> data

Loads data specified by `config` into `data`. `data` can be empty or full.
"""
function load_data!(config, data)
    # Check to see if data is empty
    if ~isempty(data)
        @warn "Inside load_data! and `data` is not empty, clearing."
        empty!(data)
    end

    load_data_files!(config, data)
    modify_raw_data!(config, data)
    setup_data!(config, data)  
    modify_setup_data!(config, data)

    # Save the data to file as specified.
    if get(config, :save_data, true)
        serialize(get_out_path(config, "data.jls"), data)
    end
    return data
end
export load_data!

"""
    load_data_files!(config, data)

Loads in the data files presented in the `config`.
"""
function load_data_files!(config, data)
    load_summary_table!(config, data)

    # Other things to load
    load_voll!(config, data)
    load_years!(config, data)

    load_table!(config, data, :bus_file      => :bus)
    load_table!(config, data, :gen_file      => :gen)
    load_table!(config, data, :branch_file   => :branch)
    load_table!(config, data, :hours_file    => :hours)
    load_table!(config, data, :demand_file   => :demand_table)
    

    # Optional tables
    load_table!(config, data, :af_file       => :af_table, optional = true)
    load_table!(config, data, :demand_shape_file=>:demand_shape, optional=true)
    load_table!(config, data, :demand_match_file=>:demand_match, optional=true)
    load_table!(config, data, :demand_add_file=>:demand_add, optional=true)
    load_table!(config, data, :build_gen_file => :build_gen, optional=true)
    load_table!(config, data, :gentype_genfuel_file => :genfuel, optional=true)
    load_table!(config, data, :adjust_yearly_file => :adjust_yearly, optional=true)
    load_table!(config, data, :adjust_hourly_file => :adjust_hourly, optional=true)
end
export load_data_files!

"""
    modify_raw_data!(config, data)

Allows [`Modification`](@ref)s to modify the raw data - calls [`modify_raw_data!(mod, config, data)`](@ref)
"""
function modify_raw_data!(config, data)    
    for (sym, mod) in get_mods(config)
        modify_raw_data!(mod, config, data)
    end
    return nothing
end

"""
    modify_setup_data!(config, data)

Allows [`Modification`](@ref)s to modify the raw data - calls [`modify_setup_data!(mod, config, data)`](@ref)
"""
function modify_setup_data!(config, data)    
    for (sym, mod) in get_mods(config)
        modify_setup_data!(mod, config, data)
    end
    return nothing
end

"""
    setup_data!(config, data)

Sets up the data, modifying, adding to, or combining the tables as needed.
New generators built in the `setup_gen_table!` function. 
"""
function setup_data!(config, data)

    # Note that order matters for these functions because later ones rely on data from earlier tables.
    setup_table!(config, data, :build_gen)
    setup_table!(config, data, :genfuel)
    setup_table!(config, data, :bus)
    setup_table!(config, data, :branch)
    setup_table!(config, data, :hours)
    setup_table!(config, data, :demand_table)
    setup_table!(config, data, :gen) # needs to come after build_gen setup for newgens
    setup_table!(config, data, :af_table)
    setup_table!(config, data, :adjust_yearly)
    setup_table!(config, data, :adjust_hourly)
end
export setup_data!

"""
    setup_table!(config, data, table_name)

Sets up the `data[:table_name]`.  Calls `setup_table!(config, data, Val(table_name))`, if defined.
"""
function setup_table!(config, data, table_name::Symbol)
    if hasmethod(setup_table!, Tuple{typeof(config), typeof(data), Val{table_name}}) && has_table(data, table_name)
        @info "Setting up data[:$(table_name)]"
        setup_table!(config, data, Val(table_name))
    end
    return 
end
export setup_table!


"""
    summarize_table(s::Symbol) -> summary::DataFrame

Returns a summary of the table `s`.  Note that more information can be provided in the the `summary_table`, which contains a summary of all tables, including all information from `summarize_table`, plus additional columns specified.

See also [`get_table(data, name)`](@ref), [`load_summary_table!(config, data)`](@ref), [`get_table_summary(data, name)`](@ref)
"""
function summarize_table(s::Symbol)
    return summarize_table(Val(s))
end
export summarize_table


################################################################################
# Data Loading
################################################################################

"""
    load_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function load_table(filename::String)
    CSV.read(filename, DataFrame, missingstring=nothing, stripwhitespace=true)
end
export load_table


"""
    load_table!(config, data, p::Pair)
    
Loads the table from the file in `config[p[1]]` into `data[p[2]]`
"""
function load_table!(config, data, p::Pair{Symbol, Symbol}; optional=false)
    optional===true && !haskey(config, first(p)) && return
    @info "Loading data[:$(last(p))] from $(config[first(p)])"
    table_file = config[first(p)]::String
    table_name = last(p)
    table = load_table(table_file)
    st = get_table_summary(data, table_name)
    force_table_types!(table, table_name, st)
    
    # Force columns that have unknown number of columns.
    for row in eachrow(st)
        if row.column_name == :h_
            for i in 1:get_num_hours(data)
                force_table_types!(table, string("h",i) => row.data_type, optional = !(row.required))
            end
        elseif row.column_name == :y_
            for yr in get_years(data)
                force_table_types!(table, yr => row.data_type, optional = !(row.required))
            end
        elseif row.column_name == :filter_
            for i in 1:1000 # arbitrarily high limit
                col_name = "filter$i"
                if hasproperty(table, col_name)
                    force_table_types!(table, col_name => row.data_type, optional = !(row.required))
                end
            end
        end
    end
    data[table_name] = table
    return
end


"""
    load_summary_table!(config, data)

Loads in the summary table for each of the other tables.
"""
function load_summary_table!(config, data)
    st = DataFrame(
        :table_name => Symbol[],
        :column_name => Symbol[],
        :data_type => Type[],
        :unit => Type{<:Unit}[],
        :required => Bool[],
        :description => String[],
    )

    # Loop through and add all the tables for which summarize_table has been defined
    for m in methods(summarize_table)
        if m.sig.parameters[2] <: Val
            append_to_summary_table!(st, m.sig.parameters[2]())
        end
    end

    rows_to_add = DataFrameRow[]
    if haskey(config, :summary_table_file)
        gst = groupby(st, [:table_name, :column_name])
        df = load_table(config[:summary_table_file])

        force_table_types!(df, :summary_table,
            (cn=>eltype(st[!,cn]) for cn in propertynames(st))...
        )

        for row in eachrow(df)
            if haskey(gst, (row.table_name, row.column_name))
                continue
            end
            push!(rows_to_add, row)
        end        
    end

    for row in rows_to_add
        push!(st, row)
    end

    data[:summary_table] = st
    
    # Make a dictionary of units such that d[(:table_name, :column_name)] = unit 
    data[:unit_lookup] = Dict(
        (row.table_name, row.column_name)=>row.unit for row in eachrow(st)
    )
    data[:desc_lookup] = Dict(
        (row.table_name, row.column_name)=>row.description for row in eachrow(st)
    )
    
    return
end
export load_summary_table!

"""
    append_to_summary_table!(summary_table::DataFrame, v::Val)

Appends a summary table, from `summarize_table(s)`, to `summary_table`
"""
function append_to_summary_table!(summary_table::DataFrame, v::V) where {s, V<:Val{s}}
    st = summarize_table(v)
    st.table_name .= s
    append!(summary_table, st)
end

"""
    load_voll!(config, data)

Return the marginal cost of load curtailment / VOLL as a variable in data
"""
function load_voll!(config, data)
    default_voll = 5000.0;
    haskey(config, :voll) ? data[:voll] = config[:voll] : data[:voll] = default_voll
    hasmethod(Float64, Tuple{typeof(data[:voll])}) || error("data[:voll] cannot be converted to a Float64")
    data[:voll] = Float64.(data[:voll]) 
end
export load_voll!

"""
    load_years!(config, data)

Loads the years from config into data
"""
function load_years!(config, data)
    data[:years] = config[:years]
    return
end
export load_years!

"""
    force_table_types!(df::DataFrame, name, pairs...)

Forces `df` to have columns associated with column=>Type `pairs`.  The table's `name` is included for descriptive errors.
"""
function force_table_types!(df::DataFrame, name, pairs...; optional=false)
    for (col, T) in pairs
        if ~hasproperty(df, col)
            optional ? continue : error(":$name table missing column :$col")
        end
        ET = eltype(df[!,col])
        ET <: T && continue
        hasmethod(T, Tuple{ET}) || error("Column $name[$col] cannot be forced into type $T from type $ET")
        df[!, col] = T.(df[!,col])
    end
end
export force_table_types!

function force_table_types!(df::DataFrame, name, summary::AbstractDataFrame; kwargs...) 
    for row in eachrow(summary)
        force_table_types!(df, name, row; kwargs...)
    end
end

function force_table_types!(df::DataFrame, name, row::DataFrameRow; kwargs...)
    col = row["column_name"]
    req = row["required"]
    T = row["data_type"]
    if ~hasproperty(df, col)
        # Return for special column identifiers - these will get checked inside load_table!
        col === :h_ && return
        col === :y_ && return
        col === :filter_ && return
        req || return
        error(":$name table missing column :$col")
    end
    ET = eltype(df[!,col])
    if ~(ET <: T)
        hasmethod(T, Tuple{ET}) || error("Column $name[$col] with eltype $ET cannot be forced into type $T")
        df[!, col] = T.(df[!,col])
    end
    return
end


################################################################################
# Table Setup
################################################################################

"""
    setup_table!(config, data, ::Val{:gen})

Sets up the generator table.
Creates potential new generators and exogenously built generators. 
Calls [`setup_new_gens!`](@ref)
Creates capex_obj column which is the capex cost seen in the objective function. It is a ByYear column that is only non zero for year_on.
Creates age column which is a ByYear column. Unbuilt generators have a negative age before year_on.
"""
function setup_table!(config, data, ::Val{:gen})
    bus = get_table(data, :bus)
    gen = get_table(data, :gen)

    data[:gen_table_original_cols] = propertynames(gen)

    #removes capex_obj if loaded in from previous sim
    :capex_obj in propertynames(data[:gen]) && select!(data[:gen], Not(:capex_obj))

    #set build_status to 'built' for all gens marked 'new'. This marks gens built in a previous sim as 'built'.
    c = ==("new") # Comparison, one allocation
    b = "built" # pre-allocate
    transform!(gen, :build_status => ByRow(s->c(s) ? b : s) => :build_status) # transform in-place

    ### Create new gens and add to the gen table
    if haskey(config, :build_gen_file) 
        setup_new_gens!(config, data)  
    end  

    ### Create capex_obj (the capex used in the optimization/objective function)
    # set to capex for unbuilt generators in the year_on
    # set to 0 for already built capacity because capacity expansion isn't considered for existing generators
    capex_obj = Container[ByNothing(0.0) for i in 1:nrow(gen)]
    for idx_g in 1:nrow(gen)
        g = gen[idx_g,:]
        g_capex_obj = [(g.build_status=="unbuilt")* g.capex*(g.year_on==year) for year in get_years(data)]
        capex_obj[idx_g] = ByYear(g_capex_obj) 
    end
    add_table_col!(data, :gen, :capex_obj, capex_obj, DollarsPerMWBuiltCapacity, "Hourly capital expenditures that is passed into the objective function. 0 for already built capacity")

    
    ### Add age column as by ByYear based on year_on
    years = year2float.(get_years(data))
    gen_age = Container[ByNothing(0.0) for i in 1:nrow(gen)]
    for idx_g in 1:nrow(gen)
        year_on = year2float(gen[idx_g, :year_on])
        g_age = [year - year_on for year in years]
        gen_age[idx_g] = ByYear(g_age)
    end

    add_table_col!(data, :gen, :age, gen_age, NumYears, "The age of the generator in each simulation year, given as a byYear container. Negative age is given for gens before their year_on.")

    ### Map bus characteristics to generators
    names_before = propertynames(gen)
    leftjoin!(gen, bus, on=:bus_idx)
    disallowmissing!(gen)
    names_after = propertynames(gen)

    for name in names_after
        name in names_before && continue
        add_table_col!(data, :gen, name, gen[!,name], get_table_col_unit(data, :bus, name), get_table_col_description(data, :bus, name))
    end

    # Add necessary columns if they don't exist.
    hasproperty(gen, :af) || (gen.af = fill(ByNothing(1.0), nrow(gen)))
    hasproperty(gen, :fuel_cost) || (gen.fuel_cost = fill(ByNothing(0.0), nrow(gen)))
    return gen
end
export setup_table!

"""
    setup_table!(config, data, ::Val{:build_gen})

Sets up the new generator characteristics/specs table.
"""
function setup_table!(config, data, ::Val{:build_gen})
    # Return if there is no build_gen_file
    if ~haskey(config, :build_gen_file) 
        return
    end

end
export setup_table!

"""
    setup_table!(config, data, ::Val{:bus})

Sets up the bus table.  
* Makes a `:bus_idx` to track row numbers.
"""
function setup_table!(config, data, ::Val{:bus})
    bus = get_table(data, :bus)
    bus_idx = collect(1:nrow(bus))
    add_table_col!(data, :bus, :bus_idx, bus_idx, NA, "The bus index of each bus, should correspond to the row number, used for joining.")
    return
end
export setup_table!

"""
    setup_table!(config, data, ::Val{:branch})

Sets up the branch table.
* Makes bus[:connected_branch_idxs] which contains a vector of the signed index of each branch leaving that bus. (`+` for `f_bus_idx`, `-` for `to_bus_idx`). 
"""
function setup_table!(config, data, ::Val{:branch})
    branch = get_table(data, :branch)
    hasproperty(branch, :status) && filter!(:status => ==(true), branch)

    # Handle duplicate lines
    if ~allunique((row.f_bus_idx,row.t_bus_idx) for row in eachrow(branch))
        @warn "Handling Duplicate Lines"
        gdf = groupby(branch, [:f_bus_idx, :t_bus_idx])
        cols_remaining = setdiff(propertynames(branch), [:f_bus_idx, :t_bus_idx, :x, :pflow_max])
        res = combine(gdf,
            [:pflow_max, :x] => ((pflow_max, x)->(minimum(prod, zip(pflow_max, x)))/(inv(sum(inv, x)))) => :pflow_max,
            :x => (x->(inv(sum(inv, x)))) => :x,
            (col=>first=>col for col in cols_remaining)...
        )
        branch = res
        data[:branch] = res
    end



    bus = get_table(data, :bus)

    # Add connected branches, connected buses.
    connected_branch_idxs = [Int64[] for _ in 1:nrow(bus)]
    add_table_col!(data, :bus, :connected_branch_idxs, connected_branch_idxs, NA, "A vector containing the indices of the branches connected to this bus")
    for (br_idx, br) in enumerate(eachrow(branch))
        f_bus_idx = br.f_bus_idx::Int64
        t_bus_idx = br.t_bus_idx::Int64
        push!(bus[f_bus_idx, :connected_branch_idxs], br_idx)
        push!(bus[t_bus_idx, :connected_branch_idxs], -br_idx)
    end
    return
end
export setup_table!

"""
    setup_table!(config, data, ::Val{:hours})

Doesn't do anything yet.
"""
function setup_table!(config, data, ::Val{:hours})
    weights = get_hour_weights(data)
    data[:hours_container] = HoursContainer(weights)
    return
end

@doc raw"""
    setup_table!(config, data, ::Val{:af_table})

Populates the `af` column of the `gen_table`.  

Updates the generator table with the availability factors provided.  By default assigns an availability factor of `1.0` for every generator.  See [`summarize_table(::Val{:af_table})`](@ref).

Often, generators are unable to generate energy at their nameplate capacity over the course of any given representative hour.  This could depend on any number of things, such as how windy it is during a given representative hour, the time of year, the age of the generating unit, etc.  The ratio of available generation capacity to nameplate generation capacity is referred to as the availability factor (AF).

The availability factor table includes availability factors for groups of generators specified by any combination of area, genfuel, gentype, year, and hour.

```math
P_{G_{g,h,y}} \leq f_{\text{avail}_{g,h,y}} \cdot P_{C{g,y}} \qquad \forall \{g \in \text{generators}, h \in \text{hours}, y \in \text{years} \}
```
"""
function setup_table!(config, data, ::Val{:af_table})
    # Fill in gen table with default af of 1.0 for every hour
    gens = get_table(data, :gen)
    default_af = ByNothing(1.0)
    gens.af = Container[default_af for _ in 1:nrow(gens)]
    
    # Return if there is no af_file
    if ~haskey(data, :af_table) 
        return
    end

    af_table = data[:af_table]

    hr_idx = findfirst(s->s=="h1",names(af_table))
    all_years = get_years(data)
    nyr = get_num_years(data)

    for i = 1:nrow(af_table)
        row = af_table[i, :]
        if get(row, :status, true) == false
            continue
        end

        if isempty(row.year)
            yr_idx = (:)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue
        end
        
        pairs = parse_comparisons(row)
        gens = get_table(data, :gen, pairs)

        isempty(gens) && continue
        
        af = [row[i_hr] for i_hr in hr_idx:ncol(af_table)]
        foreach(eachrow(gens)) do gen
            gen.af = set_hourly(gen.af, af, yr_idx; nyr)
        end
    end
    return data
end
export setup_af!


"""
    setup_table!(config, data, ::Val{:genfuel}) -> nothing

Currently does nothing
"""
function setup_table!(config, data, ::Val{:genfuel})
end


# Table Summaries
################################################################################
"""
    summarize_table(::Val{:gen}) -> summary
"""
function summarize_table(::Val{:gen})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[],  "required"=>Bool[],"description"=>String[])
    push!(df, 
        (:bus_idx, Int64, NA, true, "The index of the `bus` table that the generator corresponds to"),
        (:status, Bool, NA, false, "Whether or not the generator is in service"),
        (:build_status, AbstractString, NA, true, "Whether the generator is 'built', 'new', or 'unbuilt'. All generators marked 'new' when the gen file is read in will be changed to 'built'."),
        (:build_type, AbstractString, NA, true, "Whether the generator is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:year_on, AbstractString, Year, true, "The first year of operation for the generator. (For new gens this is also the year it was built)"),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses"),
        (:gentype, AbstractString, NA, true, "The generation technology type that the generator uses"),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power generation capacity for the generator"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of generation"),
        (:fuel_cost, Float64, DollarsPerMWhGenerated, false, "Fuel cost per MWh of generation"),
        (:fom, Float64, DollarsPerMWCapacity, true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacity, false, "Hourly capital expenditures for a MW of generation capacity"),
        (:cf_min, Float64, MWhGeneratedPerMWhCapacity, false, "The minimum capacity factor, or operable ratio of power generation to capacity for the generator to operate.  Take care to ensure this is not above the hourly availability factor in any of the hours, or else the model may be infeasible."),
        (:cf_max, Float64, MWhGeneratedPerMWhCapacity, false, "The maximum capacity factor, or operable ratio of power generation to capacity for the generator to operate"),
        (:af, Float64, MWhGeneratedPerMWhCapacity, false, "The availability factor, or maximum available ratio of pewer generation to nameplate capacity for the generator."),
        (:emis_co2, Float64, ShortTonsPerMWhGenerated, false, "The emission rate per MWh of CO2"),
        (:capt_co2_percent, Float64, ShortTonsPerMWhGenerated, false, "The percentage of co2 emissions captured, to be sequestered."),
    )
    return df
end


"""
    summarize_table(::Val{:bus}) -> summary
"""
function summarize_table(::Val{:bus})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:ref_bus, Bool, NA, true, "Whether or not the bus is a reference bus.  There should be a single reference bus for each island."),
    )
    return df
end

"""
    summarize_table(::Val{:branch}) -> summary
"""
function summarize_table(::Val{:branch})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:f_bus_idx, Int64, NA, true, "The index of the `bus` table that the branch originates **f**rom"),
        (:t_bus_idx, Int64, NA, true, "The index of the `bus` table that the branch goes **t**o"),
        (:status, Bool, NA, false, "Whether or not the branch is in service"),
        (:x, Float64, PU, true, "Per-unit reactance of the line (resistance assumed to be 0 for DC-OPF)"),
        (:pflow_max, Float64, MWFlow, true, "Maximum power flowing through the branch")
    )
    return df
end

"""
    summarize_table(::Val{:hours}) -> summary
"""
function summarize_table(::Val{:hours})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:hours, Float64, Hours, true, "The number of hours spent in each representative hour over the course of a year (must sum to 8760)"),
    )
    return df
end

"""
    summarize_table(::Val{:af_table}) -> summary
"""
function summarize_table(::Val{:af_table})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses. Leave blank to not filter by genfuel."),
        (:gentype, AbstractString, NA, true, "The generation technology type that the generator uses. Leave blank to not filter by gentype."),
        (:year, AbstractString, Year, true, "The year to apply the AF's to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this AF adjustment"),
        (:h_, Float64, MWhGeneratedPerMWhCapacity, true, "Availability factor of hour _.  Include 1 column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end


"""
    summarize_table(::Val{:build_gen}) -> summary
"""
function summarize_table(::Val{:build_gen})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:build_status, AbstractString, NA, true, "Whether the generator is 'built', 'new', or 'unbuilt'. Should be unbuilt for all new gens. This will be updated to 'new' for generators that were built in the sim."),
        (:build_type, AbstractString, NA, true, "Whether the generator is 'real', 'exog' (exogenously built), or 'endog' (endogenously built). Should either be exog or endog for buil_gen."),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses. Leave blank to not filter by genfuel."),
        (:gentype, AbstractString, NA, true, "The generation technology type that the generator uses. Leave blank to not filter by gentype."),
        (:status, Bool, NA, false, "Whether or not to use this set of characteristics/specs"),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power generation capacity for the generator. Should be 0 for endog new gens."),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of generation"),
        (:fuel_cost, Float64, DollarsPerMWhGenerated, false, "Fuel cost per MWh of generation"),
        (:fom, Float64, DollarsPerMWCapacity, true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacity, false, "Hourly capital expenditures for a MW of generation capacity"),
        (:cf_min, Float64, MWhGeneratedPerMWhCapacity, false, "The minimum capacity factor, or operable ratio of power generation to capacity for the generator to operate.  Take care to ensure this is not above the hourly availability factor in any of the hours, or else the model may be infeasible."),
        (:cf_max, Float64, MWhGeneratedPerMWhCapacity, false, "The maximum capacity factor, or operable ratio of power generation to capacity for the generator to operate"),
        (:year_on, AbstractString, NA, true, "The first year of operation for the generator. (For new gens this is also the year it was built). Endogenous unbuilt generators will be left blank"),
        (:year_on_min, AbstractString, NA, true, "The first year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
        (:year_on_max, AbstractString, NA, true, "The last year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
        (:emis_co2, Float64, ShortTonsPerMWhGenerated, false, "The CO2 emission rate of the generator, in short tons per MWh generated.  This is the net emissions. (i.e. not including captured CO2 that gets captured)"),
        (:capt_co2_percent, Float64, ShortTonsPerMWhGenerated, false, "The percentage of co2 emissions captured, to be sequestered."),
    )
    return df
end

"""
    summarize_table(::Val{:genfuel}) -> 
"""
function summarize_table(::Val{:genfuel})
    df = DataFrame("column_name"=>Symbol[], "data_type"=>Type[], "unit"=>Type{<:Unit}[], "required"=>Bool[], "description"=>String[])
    push!(df, 
        (:gentype, AbstractString, NA, true, "The generator type (ie. ngcc, dist_solar, os_wind)"),
        (:genfuel, AbstractString, NA, true, "The corresponding generator fuel or renewable type (ie. ng, solar, wind)"),
    )
    return df
end

# Data Accessor Functions
################################################################################

"""
    get_table(data, table_name::Symbol) -> table::DataFrame

Retrieves `data[table_name]`, enforcing that it is a DataFrame.  See [`get_table_names`](@ref) for a list of available tables.
"""
function get_table(data, table_name::Symbol)
    return data[table_name]::DataFrame
end

function get_table(data, table_name::AbstractString)
    return get_table(data, Symbol(table_name))
end

"""
    get_table(data, table_name, conditions...) -> subtable::SubDataFrame

Return a subset of the table `table_name` for which the row passes the `conditions`.  Conditions are `Pair`s generally consisting of `<column name> => value`.  Here are some examples of supported conditions:
* `:genfuel => "ng"` - All rows for which `row.genfuel == "ng"`
* `"bus_idx" => 1` - All rows for which `row.bus_idx == 1`.  Note that the column name can be String or Symbol
* `:bus_idx  => "1"` - All rows for which `row.bus_idx == 1`.  Note that this is a String but it will get converted to the eltype of table.bus_idx for the comparison
* `:year_on  => ("y2022", "y2030")` - All rows for which `row.year_on` is between "y2022" and "y2030", inclusive.  Also works for fractional years.
* `:genfuel => ["ng", "solar", "wind"]` - All rows for which `row.genfuel` is either "ng", "solar", or "wind"
* `:emis_co2 => f::Function` - All rows for which f(row.emis_co2) returns `true`.  For example `>(0)`, or `x->(0<x<=0.5)`
"""
function get_table(data, table_name::Union{Symbol, AbstractString}, conditions...)
    table = get_table(data, table_name)
    get_subtable(table, conditions...)
end
export get_table

"""
    get_subtable(table::DataFrame, conditions...)

Returns a `SubDataFrame` of `table`, based on `conditions`.  See [`get_table`](@ref) for ideas of appropriate `conditions`
"""
function get_subtable(table::DataFrame, conditions...)
    row_idxs = get_row_idxs(table, conditions...)
    return view(table, row_idxs, :)
end
export get_subtable

"""
    get_table_row_idxs(data, table_name, conditions...) -> row_idxs::Vector{Int64}

Gets the row indices for `data[table_name]` for which the `conditions` hold true.  See [`get_table`](@ref) for a description of possible conditions
"""
function get_table_row_idxs(data, table_name, conditions...)
    table = get_table(data, table_name)
    row_idxs = get_row_idxs(table, conditions...)
    return row_idxs
end
export get_table_row_idxs

"""
    get_table_col(data, table_name, col_name) -> col::Vector
"""
function get_table_col(data, table_name, col_name)
    table = get_table(data, table_name)
    col = table[!, col_name]
    return col::AbstractVector
end
export get_table_col
"""
    add_table_col!(data, table_name, col_name, col, unit, description)

Adds `col` to `data[table_name][!, col_name]`, also adding the description and unit to the summary table.
"""
function add_table_col!(data, table_name, column_name, col::AbstractVector, unit, description)
    # Add col to table
    table = get_table(data, table_name)
    hasproperty(table, column_name) && @warn "Table data[$table_name] already has column $column_name, overwriting"
    table[!, column_name] = col

    # Document in the summary table
    summary_table = get_table(data, :summary_table)
    data_type = _eltype(col)
    row = (;table_name, column_name, data_type, unit, required=false, description)
    push!(summary_table, row)
    data[:unit_lookup][(table_name, column_name)] = unit
    data[:desc_lookup][(table_name, column_name)] = description
end
function add_table_col!(data, table_name, column_name, ar::AbstractArray{<:Real, 3}, unit, description)
    v = [view(ar, i, :, :) for i in 1:size(ar, 1)]
    return add_table_col!(data, table_name, column_name, v, unit, description)
end
function add_table_col!(data, table_name, column_name, ar::AbstractMatrix{<:Real}, unit, description)
    # Might need to make this into a container.
    v = [view(ar, i, :) for i in 1:size(ar, 1)]
    return add_table_col!(data, table_name, column_name, v, unit, description)
end
export add_table_col!


"""
    get_table_col_unit(data, table_name, column_name) -> unit::Type{<:Unit}
"""
function get_table_col_unit(data, table_name::Symbol, column_name::Symbol)
    ul = data[:unit_lookup]::Dict{Tuple{Symbol, Symbol}, DataType}
    unit = get(ul, (table_name, column_name)) do
        cn = string(column_name)
        if contains(cn, r"h\d*")
            haskey(ul, (table_name, :h_)) && return ul[(table_name, :h_)]
        elseif contains(cn, r"y\d*")
            haskey(ul, (table_name, :h_)) && return ul[(table_name, :y_)]
        end
        error("No unit found for table column $table_name[:$column_name].\nConsider defining the column in the summary_table.")
    end::Type{<:Unit}
    return unit
end
function get_table_col_unit(data, table_name, column_name)
    get_table_col_unit(data, Symbol(table_name), Symbol(column_name))
end
export get_table_col_unit

"""
    get_table_col_description(data, table_name, column_name) -> description
"""
function get_table_col_description(data, table_name::Symbol, column_name::Symbol)
    ul = data[:desc_lookup]::Dict{Tuple{Symbol, Symbol}, String}
    desc = get(ul, (table_name, column_name)) do
        cn = string(column_name)
        if contains(cn, r"h\d*")
            haskey(ul, (table_name, :h_)) && return ul[(table_name, :h_)]
        elseif contains(cn, r"y\d*")
            haskey(ul, (table_name, :h_)) && return ul[(table_name, :y_)]
        end
        error("No description found for table column $table_name[:$column_name].\nConsider defining the column in the summary_table.")
    end::String
    return desc
end
function get_table_col_description(data, table_name, column_name)
    get_table_col_description(data, Symbol(table_name), Symbol(column_name))
end
export get_table_col_description

"""
    get_table_col_type(data, table_name, column_name) -> ::Type
"""
function get_table_col_type(data, table_name, column_name)
    return eltype(get_table_col(data, table_name, column_name))
end
export get_table_col_type


_eltype(::AbstractVector{<:Container}) = Float64
_eltype(::AbstractVector{<:AbstractVector{Float64}}) = Float64
_eltype(v) = eltype(v)

"""
    get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx) -> num::Float64

Retrieves a `Float64` from  `table[row_idx, col_idx][yr_idx, hr_idx]`.  This indexes into [`Container`](@ref)s as needed and will still work for `Float64` columns.

Related functions:
* [`get_table_val(data, table_name, col_name, row_idx)`](@ref): retrieves the raw value from the table (without indexing by year/hour).
* [`get_num(data, name, yr_idx, hr_idx)`](@ref): retrieves a `Float64` from `data`, indexing by year and hour.
"""
function get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)
    table = get_table(data, table_name)
    container = table[row_idx, col_name]
    return container[yr_idx, hr_idx]::Float64
end
export get_table_num

"""
    get_num(data, variable_name, yr_idx, hr_idx) -> num::Float64

Retrieves a `Float64` from `data[variable_name]`, indexing by year and hour.  Works for [`Container`](@ref)s and `Number`s.

Related functions:
* [`get_table_val(data, table_name, col_name, row_idx)`](@ref): retrieves the raw value from the table (without indexing by year/hour).
* [`get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)`](@ref): retrieves the `Float64` from `data[variable_name]`, indexing by year and hour.
"""
function get_num(data, variable_name::Symbol, yr_idx, hr_idx)
    c = data[variable_name]
    return c[yr_idx, hr_idx]::Float64
end
export get_num

"""
    get_table_val(data, table_name, col_name, row_idx) -> val

Returns the value of the table at column `col_name` and row `row_idx`

Related functions:
* [`get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)`](@ref): retrieves the `Float64` from `data[variable_name]`, indexing by year and hour.
* [`get_num(data, name, yr_idx, hr_idx)`](@ref): retrieves a `Float64` from `data`, indexing by year and hour.
"""
function get_table_val(data, table_name, col_name, row_idx)
    table = get_table(data, table_name)
    val = table[row_idx, col_name]
    return val
end
export get_table_val

"""
    get_table_names(data) -> table_list

Returns a list of all the tables in `data`.
"""
function get_table_names(data)
    return [k for (k,v) in data if v isa DataFrame]
end
export get_table_names


"""
    has_table(data, table_name) -> Bool
"""
function has_table(data, table_name::Symbol)
    return haskey(data, table_name) && data[table_name] isa DataFrame
end

function has_table(data, table_name::AbstractString)
    has_table(data, Symbol(table_name))
end
export has_table

"""
    get_table_summary(config, data, table_name) -> summary::SubDataFrame

Returns a summary of `table_name`, loaded in from [`summarize_table`](@ref)` and [`load_summary_table!`](@ref).
"""
function get_table_summary(data, table_name)
    st = get_table(data, :summary_table)
    return filter(:table_name => ==(table_name), st; view=true)
end
export get_table_summary

"""
    get_demand_array(data)

Returns the demand array, a 3d array of demand indexed by [demand_idx, yr_idx, hr_idx]
"""
function get_demand_array(data)
    return data[:demand_array]::Array{Float64,3}
end
export get_demand_array

"""
    get_generator(data, gen_idx) -> row

Returns the row of the gen table corresponding to `gen_idx`
"""
function get_generator(data, gen_idx)
    return get_table(data, :gen)[gen_idx,:]
end

"""
    get_bus(data, bus_idx) -> row

Returns the row of the bus table corresponding to `bus_idx`
"""
function get_bus(data, bus_idx)
    return get_table(data, :bus)[bus_idx,:]
end

"""
    get_branch(data, branch_idx) -> row

Returns the row of the branch table corresponding to `branch_idx`
"""
function get_branch(data, branch_idx)
    return get_table(data, :branch)[branch_idx,:]
end

export get_generator, get_bus, get_branch
export get_bus_from_generator_idx

"""
    get_af(data, gen_idx, year_idx, hour_idx) -> af

Retrieves the availability factor for a generator at a year and a time.
"""
function get_af(data, gen_idx, year_idx, hour_idx)
    return get_table_num(data, :gen, :af, gen_idx, year_idx, hour_idx)
end

export get_af

"""
    get_pdem(data, bus_idx, year_idx, hour_idx) -> pdem

Retrieves the demanded power for a bus at a year and a time.
"""
function get_pdem(data, bus_idx, year_idx, hour_idx)
    return get_table_num(data, :bus, :pdem, bus_idx, year_idx, hour_idx)
end
export get_pdem

"""
    get_edem(data, bus_idx, year_idx, hour_idx) -> ed::Float64 (MWh)

    get_edem(data, bus_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

Retrieve the total energy demanded for a bus at a given year and hour(s).
"""
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idx::Int64)
    return get_hour_weight(data, hour_idx) * get_pdem(data, bus_idx, year_idx, hour_idx)
end
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idxs)
    return sum(get_hour_weight(data, hour_idx) * get_pdem(data, bus_idx, year_idx, hour_idx) for hour_idx in hour_idxs)
end
function get_edem(data, bus_idx::Int64, year_idx::Int64, hour_idxs::Colon)
    hour_weights = get_hour_weights(data)
    return sum(hour_weights[hour_idx] * get_pdem(data, bus_idx, year_idx, hour_idx) for hour_idx in eachindex(hour_weights))
end
function get_edem(data, bus_idx=(:), year_idx=(:), hour_idx=(:))
    _bus_idxs = get_table_row_idxs(data, :bus, bus_idx)
    _year_idxs = get_year_idxs(data, year_idx)
    _hour_idxs = get_hour_idxs(data, hour_idx)
    hour_weights = get_hour_weights(data)
    return sum(hour_weights[h] * get_pdem(data, b, y, h) for h in _hour_idxs, y in _year_idxs, b in _bus_idxs)
end

"""
    get_edem_demand(data, demand_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

    get_edem_demand(data, demand_idxs, year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

    get_edem_demand(data, pair(s), year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

Return the energy demanded by demand elements corresponding to `demand_idx` or `demand_idxs`, for `year_idx` and `hour_idx`.  Note `year_idx` can be the index or the year string (i.e. "y2030").

If pair(s) are given, filters the demand elements by pair.  i.e. pairs = ("country"=>"narnia", "load_type"=>"residential").
"""
function get_edem_demand(data, demand_idxs::AbstractVector{Int64}, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, demand_idxs, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end
function get_edem_demand(data, ::Colon, year_idx::Int64, hour_idxs)
    demand_arr = get_demand_array(data)
    demand_mat = view(demand_arr, :, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(demand_mat, hour_weights)
end

function get_edem_demand(data, pairs, year_idx::Int64, hour_idxs)
    demand_table = get_table(data, :demand_table, pairs...)
    return get_edem_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end

function get_edem_demand(data, pair::Pair, year_idx::Int64, hour_idxs)
    demand_table = get_table(data, :demand_table, pair)
    return get_edem_demand(data, getfield(demand_table, :rows), year_idx, hour_idxs)
end
function get_edem_demand(data, demand_idxs, y::String, hr_idx)
    year_idx = findfirst(==(y), get_years(data))
    return get_edem_demand(data, demand_idxs, year_idx, hr_idx)
end
export get_edem, get_edem_demand


"""
    get_num_hours(data) -> nhr

Returns the number of representative hours in a year
"""
function get_num_hours(data)
    return nrow(get_table(data, :hours))
end

"""
    get_hour_weights(data) -> weights

    get_hour_weights(data, hour_idxs) -> weights (view)

Returns the number of hours in a year spent at each representative hour
""" 
function get_hour_weights(data)
    hours_table = get_table(data, :hours)
    return hours_table.hours::Vector{Float64}
end
function get_hour_weights(data, hour_idxs)
    return view(get_hour_weights(data), hour_idxs)
end
function get_hour_weights(data, ::Colon)
    return get_hour_weights(data)
end

"""
    get_hour_weight(data, hour_idx)

Returns the number of hours in a year spent at the `hour_idx` representative hour
"""
function get_hour_weight(data, hour_idx::Int64)
    return get_hour_weights(data)[hour_idx]
end
export get_num_hours, get_hour_weights, get_hour_weight

"""
    get_years(data) -> years

Returns the vector of years as strings (i.e. "y2022") that are being represented in the sim.
"""
function get_years(data)
    return data[:years]::Vector{String}
end

"""
    get_num_years(data) -> nyr

Returns the number of years in this simulation
"""
function get_num_years(data)
    return length(get_years(data))
end
export get_num_years, get_years


"""
    get_prebuild_year_idxs(data, gen_idx) -> prebuild_year_idxs::Array

Returns an array of the year indexes for years in the simulation before the start year of the specified generator. 
"""
function get_prebuild_year_idxs(data, gen_idx)
    years = get_years(data)
    year_on = get_table_val(data, :gen, :year_on, gen_idx)
    idxs = findall(x -> years[x] < year_on, 1:length(years))
    return idxs
end
export get_prebuild_year_idxs

"""
    get_year_on_sim_idx(data, gen_idx) -> year_on_sim_idx

Gets the index for the generator on year. 
If the on_year is in the set of sim years, it returns that index. 
If this year is not part of the set of year, it returns the index of the next closest year. (ie. years = [2020, 2025, 2030], year_on = 2022, year_on_sim = 2025, year_on_sim_idx = 2)
If this year is after the simulation years it returns length(years)+1 indicating that it is in the future.
"""
function get_year_on_sim_idx(data, gen_idx)
    years = get_years(data)
    year_on = get_table_val(data, :gen, :year_on, gen_idx)
    year_on_sim_idx = findfirst(x -> years[x] >= year_on, 1:length(years)) 
    if year_on_sim_idx === nothing
        year_on_sim_idx = length(years)+1
    end
    return year_on_sim_idx
end
export get_year_on_sim_idx

## Moved from dcopf, will organize later

### System mapping helper functions

"""
    get_bus_gens(data, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, bus_idx) 
    gen = get_table(data, :gen)
    return findall(x -> x == bus_idx, gen.bus_idx)
end
export get_bus_gens

"""
    get_ref_bus_idxs(data)

Returns reference bus ids
"""
function get_ref_bus_idxs(data) 
    bus = get_table(data, :bus)
    return findall(bus.ref_bus)
end
export get_ref_bus_idxs

### Constraint info functions (change name)

"""
    get_pcap_min(data, gen_idx, year_idx)

Returns min capacity for a generator
"""
function get_pcap_min(data, gen_idx, year_idx) 
    return get_table_num(data, :gen, :pcap_min, gen_idx, year_idx, :)
end
export get_pcap_min


"""
    get_pcap_max(data, model, gen_idx, year_idx)

Returns max capacity for a generator
"""
function get_pcap_max(data, gen_idx, year_idx) 
    return get_table_num(data, :gen, :pcap_max, gen_idx, year_idx, :)
end
export get_pcap_max


""" 
    get_pflow_branch_max(data, branch_idx, year_idx, hour_idx)

Returns max power flow on a branch at a given time. 
"""
function get_pflow_branch_max(data, branch_idx, year_idx, hour_idx) 
    return get_table_num(data, :branch, :pflow_max, branch_idx, year_idx, hour_idx)
end
export get_pflow_branch_max


### Misc

"""
    get_voll(data, bus_idx, year_idx, hour_idx)

Returns the value of lost load at given bus and time
"""
function get_voll(data, bus_idx, year_idx, hour_idx) 
    # If we want voll to be by bus_idx this could be modified and load_voll() will need to be changed
    return data[:voll]
end
export get_voll


