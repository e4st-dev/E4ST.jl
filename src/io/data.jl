################################################################################
# Main Data Interfaces
################################################################################

"""
    read_data(config) -> data

Pulls in data found in files listed in the `config`, and stores into `data`.

Calls the following functions:
* [`read_data_files!(config, data)`](@ref) - read in the data from files
* [`modify_raw_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the raw data before the data gets setup.
* [`setup_data!(config, data)`](@ref) - Sets up the data, modifying/adding to the tables as needed.
* [`modify_setup_data!(config, data)`](@ref) - Gives [`Modification`](@ref)s a chance to modify the setup data before the model is built.
"""
function read_data(config)
    log_header("READING DATA")

    # Try loading the data directly
    if haskey(config, :data_file)
        @info "Reading data from $(config[:data_file])"
        data = deserialize(config[:data_file])
        return data
    end
    data = OrderedDict{Symbol, Any}()
    
    read_data!(config, data)

    return data
end

"""
    read_data!(config, data) -> data

Loads data specified by `config` into `data`. `data` can be empty or full.
"""
function read_data!(config, data)
    # Check to see if data is empty
    if ~isempty(data)
        @warn "Inside read_data! and `data` is not empty, clearing."
        empty!(data)
    end

    read_data_files!(config, data)
    modify_raw_data!(config, data)
    setup_data!(config, data)  
    modify_setup_data!(config, data)

    setup_results_formulas!(config, data)
    setup_welfare!(config, data)

    # Save the data to file as specified.
    if get(config, :save_data, true)
        serialize(get_out_path(config, "data.jls"), data)
    end
    return data
end
export read_data!

"""
    read_data_files!(config, data)

Loads in the data files presented in the `config`.
"""
function read_data_files!(config, data)
    read_summary_table!(config, data)

    # Other things to read in
    read_num_params!(config, data)
    read_years!(config, data)

    read_table!(config, data, :bus_file      => :bus)
    read_table!(config, data, :gen_file      => :gen)
    read_table!(config, data, :branch_file   => :branch)
    read_table!(config, data, :hours_file    => :hours)
    read_table!(config, data, :nominal_load_file   => :nominal_load)
    

    # Optional tables
    read_table!(config, data, :af_file       => :af_table, optional = true)
    read_table!(config, data, :load_shape_file=>:load_shape, optional=true)
    read_table!(config, data, :load_match_file=>:load_match, optional=true)
    read_table!(config, data, :load_add_file=>:load_add, optional=true)
    read_table!(config, data, :build_gen_file => :build_gen, optional=true)
    read_table!(config, data, :gentype_genfuel_file => :genfuel, optional=true)
end
export read_data_files!

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
    setup_table!(config, data, :nominal_load)
    setup_table!(config, data, :gen) # needs to come after build_gen setup for newgens
    setup_table!(config, data, :af_table)
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

See also [`get_table(data, name)`](@ref), [`read_summary_table!(config, data)`](@ref), [`get_table_summary(data, name)`](@ref)
"""
function summarize_table(s::Symbol)
    return summarize_table(Val(s))
end
export summarize_table


################################################################################
# Data Loading
################################################################################

"""
    read_table(filename) -> table

Loads a table from filename, where filename is a csv.
"""
function read_table(filename::String)
    CSV.read(filename, DataFrame, missingstring=nothing, stripwhitespace=true)
end

"""
    read_table(filenames::AbstractVector) -> table

Reads tables in from `filenames`, appending them together.
"""
function read_table(filenames::AbstractVector)
    table = read_table(first(filenames))
    for i in 2:length(filenames)
        filename = filenames[i]
        tmp = read_table(filename)
        append!(table, tmp, promote=true)
    end
    return table
end
export read_table


"""
    read_table!(config, data, p::Pair)
    
Loads the table from the file in `config[p[1]]` into `data[p[2]]`
"""
function read_table!(config, data, p::Pair{Symbol, Symbol}; optional=false)
    optional===true && !haskey(config, first(p)) && return
    @info "Loading data[:$(last(p))] from $(config[first(p)])"
    table_file = config[first(p)]
    table_name = last(p)
    table = read_table(data, table_file, table_name)
    st = get_table_summary(data, table_name)
    
    data[table_name] = table

    # Add other columns to the summary, with NA unit and empty descriptions
    for name in propertynames(table)
        name in st.column_name && continue
        name_str = string(name)
        match(r"h\d+", name_str) !== nothing && continue
        match(r"y\d+", name_str) !== nothing && continue
        add_table_col!(data, table_name, name, table[!, name], NA, "", warn_overwrite=false)
    end

    return
end

"""
    read_table(data, table_file, table_name) -> table

Reads a table from `table_file`, pulling in the summary from `data[:summary_table]`, and forcing types.  Returns the resulting `table`.
"""
function read_table(data, table_file, table_name)
    table = read_table(table_file)
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

    return table
end
export read_table


"""
    read_summary_table!(config, data)

Loads in the summary table for each of the other tables.
"""
function read_summary_table!(config, data)
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
        df = read_table(config[:summary_table_file])

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
export read_summary_table!

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
    read_voll!(config, data)

Return the marginal cost of load curtailment / VOLL as a variable in data
"""
function read_voll!(config, data)
    data[:voll] = Float64(config[:voll]) 
end
export read_voll!

"""
    read_num_params!(config, data) -> 

Any parameter specified as a numeric in the config will be added to `data`. This is so that parameters with a single value (i.e. VOLL, ng_upstream_ch4_leakage) can be tracked and accessed easily in data. 
"""
function read_num_params!(config, data)
    for (k,v) in config
        (typeof(v) <: Number) ? data[k] = v : continue
    end 
end
export read_num_params!

"""
    read_years!(config, data)

Loads the years from config into data
"""
function read_years!(config, data)
    data[:years] = config[:years]
    return
end
export read_years!

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
        # Return for special column identifiers - these will get checked inside read_table!
        col === :h_ && return
        col === :y_ && return
        col === :filter_ && return
        req || return
        error(":$name table missing column :$col")
    end
    ET = eltype(df[!,col])
    if ET === Missing
        df[!,col] = convert(Vector{T}, df[!,col])
    elseif ~(ET <: T)
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
Calls [`append_builds!`](@ref)
Creates age column which is a ByYear column. Unbuilt generators have a negative age before year_on.
"""
function setup_table!(config, data, ::Val{:gen})
    bus = get_table(data, :bus)
    gen = get_table(data, :gen)
    years = get_years(data)

    # Set up year_unbuilt before setting up new gens.  Plus we will want to save the column
    hasproperty(gen, :year_unbuilt) || (gen.year_unbuilt = map(y->add_to_year(y, -1), gen.year_on))
    
    # Set up past capex cost and subsidy to be for built generators only
    # Make columns as needed
    hasproperty(gen, :past_invest_cost) || (gen.past_invest_cost = zeros(nrow(gen)))
    hasproperty(gen, :past_invest_subsidy) || (gen.past_invest_subsidy = zeros(nrow(gen)))
    z = Container(0.0)
    to_container!(gen, :past_invest_cost)
    to_container!(gen, :past_invest_subsidy)
    for (idx_g, g) in enumerate(eachrow(gen))
        if g.build_status == "unbuilt"
            if any(!=(0), g.past_invest_cost) || any(!=(0), g.past_invest_subsidy)
                @warn "Generator $idx_g is unbuilt yet has past capex cost/subsidy, setting to zero"
                g.past_invest_cost = z
                g.past_invest_subsidy = z
            end
        else
            past_invest_percentages = get_past_invest_percentages(g, years)
            g.past_invest_cost = g.past_invest_cost .* past_invest_percentages
            g.past_invest_subsidy = g.past_invest_subsidy .* past_invest_percentages
        end
    end

    original_cols = propertynames(gen)
    data[:gen_table_original_cols] = original_cols

    #removes capex_obj if read in from previous sim
    :capex_obj in propertynames(data[:gen]) && select!(data[:gen], Not(:capex_obj))

    #set build_status to 'built' for all gens marked 'new'. This marks gens built in a previous sim as 'built'.
    b = "built" # pre-allocate
    transform!(gen, :build_status => ByRow(s->isnew(s) ? b : s) => :build_status) # transform in-place

    # Set the pcap_max to be equal to pcap0 for built generators
    gen.pcap_max = map(row->isbuilt(row) ? row.pcap0 : row.pcap_max, eachrow(gen))
    gen.pcap0 = map(row->isbuilt(row) ? row.pcap0 : 0.0, eachrow(gen))


    ### Create new gens and add to the gen table
    if haskey(config, :build_gen_file) 
        append_builds!(config, data, :gen, :build_gen)  
    end
    
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
    join_bus_columns!(data, :gen)
    
    # Add necessary columns if they don't exist.
    hasproperty(gen, :af) || (gen.af = fill(ByNothing(1.0), nrow(gen)))
    hasproperty(gen, :fuel_price) || (gen.fuel_price = fill(0.0, nrow(gen)))

    return gen
end
export setup_table!

"""
    join_bus_columns!(data, table_name)

Joins relevant columns of the bus table to table `table_name`
"""
function join_bus_columns!(data, table_name)
    table = get_table(data, table_name)
    bus = get_table(data, :bus)

    names_before = names(table)
    bus_names_no_join = [:reg_factor, :ref_bus, :plnom, :distribution_cost, :connected_branch_idxs]
    bus_join = select(bus, Not(bus_names_no_join))
    bus_names = names(bus_join)
    for col_name in bus_names
        col_name == "bus_idx" && continue  
        rename!(bus_join, col_name => "bus_$col_name")
    end
    leftjoin!(table, bus_join, on=:bus_idx)
    disallowmissing!(table)
    names_after = names(table)

    for name in names_after
        name in names_before && continue
        name_old = name[5:end] # Take off bus_
        add_table_col!(data, table_name, Symbol(name), table[!,name], get_table_col_unit(data, :bus, name_old), get_table_col_description(data, :bus, name_old), warn_overwrite=false)
    end
end
export join_bus_columns!

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

    # Add distribution loss as a column
    dist_cost = config[:distribution_cost] |> Float64
    add_table_col!(data, :bus, :distribution_cost, fill(dist_cost, nrow(bus)), DollarsPerMWhServed, "The assumed cost per MWh of served power, for the transmission and distribution of the power.")
    return
end
export setup_table!

"""
    setup_table!(config, data, ::Val{:branch})

Sets up the branch table.
* Flips `f_bus_idx` and `t_bus_idx` so that `f_bus_idx` < `t_bus_idx`
* Makes bus[:connected_branch_idxs] which contains a vector of the signed index of each branch leaving that bus. (`+` for `f_bus_idx`, `-` for `to_bus_idx`). 
"""
function setup_table!(config, data, ::Val{:branch})
    branch = get_table(data, :branch)
    hasproperty(branch, :status) && filter!(:status => ==(true), branch)

    # Switch f_bus_idx and t_bus_idx if they are out of order
    for row in eachrow(branch)
        f_bus_idx = row.f_bus_idx::Int
        t_bus_idx = row.t_bus_idx::Int
        f_bus_idx < t_bus_idx && continue
        row.t_bus_idx = f_bus_idx
        row.f_bus_idx = t_bus_idx
    end

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
    af_threshold = config[:cf_threshold]::Float64

    # Return if there is no af_file
    if ~haskey(data, :af_table) 
        return
    end

    af_table = data[:af_table]

    hr_idx = findfirst(s->s=="h1",names(af_table))
    all_years = get_years(data)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)

    for i = 1:nrow(af_table)
        row = af_table[i, :]
        if get(row, :status, true) == false
            continue
        end

        if !haskey(row, :year) || isempty(row.year)
            yr_idx = (:)
        elseif row.year ∈ all_years
            yr_idx = findfirst(==(row.year), all_years)
        else
            continue
        end
        
        pairs = parse_comparisons(row)
        gens = get_table(data, :gen, pairs)

        isempty(gens) && continue
        
        af = [(row[i_hr] < af_threshold ? 0.0 : row[i_hr]) for i_hr in hr_idx:(hr_idx + nhr - 1)]
        foreach(eachrow(gens)) do gen
            gen.af = set_hourly(gen.af, af, yr_idx, nyr)
        end
    end
    return data
end

"""
    setup_table!(config, data, ::Val{:genfuel}) -> nothing

Currently does nothing
"""
function setup_table!(config, data, ::Val{:genfuel})
end


# Table Summaries
################################################################################
@doc """
    summarize_table(::Val{:gen})

$(table2markdown(summarize_table(Val(:gen))))
"""
function summarize_table(::Val{:gen})
    df = TableSummary()
    push!(df, 
        (:bus_idx, Int64, NA, true, "The index of the `bus` table that the generator corresponds to"),
        (:status, Bool, NA, false, "Whether or not the generator is in service"),
        (:build_status, String15, NA, true, "Whether the generator is `built`, `new`, `unbuilt`, or `unretrofitted`. All generators marked `new` when the gen file is read in will be changed to `built`.  Can also be changed to `retired_exog` or `retired_endog` after the simulation is run. See [`update_build_status!`](@ref).  Note that `unretrofitted` means it is a [`Retrofit`](@ref) option based on a `built` generator."),
        (:build_type, AbstractString, NA, true, "Whether the generator is 'real', 'exog' (exogenously built), or 'endog' (endogenously built)"),
        (:build_id, AbstractString, NA, true, "Identifier of the build row.  For pre-existing generators not specified in the build file, this is usually left empty"),
        (:year_on, YearString, Year, true, "The first year of operation for the generator. (For new gens this is also the year it was built)"),
        (:year_unbuilt,YearString, Year, false, "The latest year the generator was known not to be built.  Defaults to year_on - 1.  Used for past capex accounting."),
        (:econ_life, Float64, NumYears, true, "The number of years in the economic lifetime of the generator."),
        (:year_off, YearString, Year, true, "The first year that the generator is no longer operating in the simulation, computed from the simulation.  Leave as y9999 if an existing generator that has not been retired in the simulation yet."),
        (:year_shutdown, YearString, Year, true, "The forced (exogenous) shutdown year for the generator.  Often equal to the year_on plus the econ_life"),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses"),
        (:gentype, String, NA, true, "The generation technology type that the generator uses"),
        (:pcap_inv, Float64, MWCapacity, true, "Original invested nameplate power generation capacity for the generator.  This is the original invested capacity of exogenously built generators (even if there have been retirements ), and the original invested capacity in year_on for endogenously built generators."),
        (:pcap0, Float64, MWCapacity, true, "Nameplate power generation capacity for the generator at the start of the simulation"),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of generation"),
        (:fuel_price, Float64, DollarsPerMMBtu, false, "Fuel cost per MMBtu of fuel used.  `heat_rate` column also necessary when supplying `fuel_price`"),
        (:heat_rate, Float64, MMBtuPerMWhGenerated, false, "Heat rate,  or MMBtu of fuel consumed per MWh electricity generated (0 for generators that don't use combustion)"),
        (:fom, Float64, DollarsPerMWCapacityPerHour, true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for a MW of generation capacity.  For already-built generators, this is not accounted for in the optimization or accounting.  For accounting for investment costs and subsidies in built generators, use `past_invest_cost` and `past_invest_subsidy`"),
        (:transmission_capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for the transmission supporting a MW of generation capacity"),
        (:routine_capex, Float64, DollarsPerMWCapacityPerHour, true, "Routine capital expenditures for a MW of discharge capacity"),
        (:past_invest_cost, Float64, DollarsPerMWCapacityPerHour, false, "Investment costs per MW of initial capacity per hour, for past investments"),
        (:past_invest_subsidy, Float64, DollarsPerMWCapacityPerHour, false, "Investment subsidies from govt. per MW of initial capacity per hour, for past investments"),
        (:cf_min, Float64, MWhGeneratedPerMWhCapacity, false, "The minimum capacity factor, or operable ratio of power generation to capacity for the generator to operate.  Take care to ensure this is not above the hourly availability factor in any of the hours, or else the model may be infeasible.  Set to zero by default."),
        (:cf_max, Float64, MWhGeneratedPerMWhCapacity, false, "The maximum capacity factor, or operable ratio of power generation to capacity for the generator to operate"),
        (:cf_hist, Float64, MWhGeneratedPerMWhCapacity, false, "The historical capacity factor for the generator, or the gentype if no previous data is available. Primarily used to calculate estimate policy value (PTC and EmissionPrice capex_adj)"),
        (:af, Float64, MWhGeneratedPerMWhCapacity, false, "The availability factor, or maximum available ratio of pewer generation to nameplate capacity for the generator."),
        (:emis_co2, Float64, ShortTonsPerMWhGenerated, false, "The emission rate per MWh of CO2"),
        (:capt_co2_percent, Float64, NA, false, "The percentage of co2 emissions captured, to be sequestered."),
        (:heat_rate, Float64, MMBtuPerMWhGenerated, false, "Heat rate, or MMBtu of fuel consumed per MWh electricity generated (0 for generators that don't use combustion)"),
        (:chp_co2_multi,Float64,NA,false,"The percentage of CO2 emissions from CHP attributed to the power generation. Used to calculate CO2e"),
        (:reg_factor, Float64, NA, true, "The percentage of generation that dispatches to a cost-of-service regulated market"),
    )
    return df
end


@doc """
    summarize_table(::Val{:bus})

$(table2markdown(summarize_table(Val(:bus))))
"""
function summarize_table(::Val{:bus})
    df = TableSummary()
    push!(df, 
        (:ref_bus, Bool, NA, true, "Whether or not the bus is a reference bus.  There should be a single reference bus for each island."),
        (:reg_factor, Float64, NA, true, "The percentage of generation that dispatches to a cost-of-service regulated market"),
    )
    return df
end

@doc """
    summarize_table(::Val{:branch})

$(table2markdown(summarize_table(Val(:branch))))
"""
function summarize_table(::Val{:branch})
    df = TableSummary()
    push!(df, 
        (:f_bus_idx, Int64, NA, true, "The index of the `bus` table that the branch originates **f**rom"),
        (:t_bus_idx, Int64, NA, true, "The index of the `bus` table that the branch goes **t**o"),
        (:status, Bool, NA, false, "Whether or not the branch is in service"),
        (:x, Float64, PU, true, "Per-unit reactance of the line (resistance assumed to be 0 for DC-OPF)"),
        (:pflow_max, Float64, MWFlow, true, "Maximum power flowing through the branch")
    )
    return df
end

@doc """
    summarize_table(::Val{:hours})

$(table2markdown(summarize_table(Val(:hours))))
"""
function summarize_table(::Val{:hours})
    df = TableSummary()
    push!(df, 
        (:hours, Float64, Hours, true, "The number of hours spent in each representative hour over the course of a year (must sum to 8760)"),
    )
    return df
end

@doc """
    summarize_table(::Val{:af_table})

$(table2markdown(summarize_table(Val(:af_table))))
"""
function summarize_table(::Val{:af_table})
    df = TableSummary()
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses. Leave blank to not filter by genfuel."),
        (:gentype, String, NA, true, "The generation technology type that the generator uses. Leave blank to not filter by gentype."),
        (:year, YearString, Year, false, "The year to apply the AF's to, expressed as a year string prepended with a \"y\".  I.e. \"y2022\""),
        (:status, Bool, NA, false, "Whether or not to use this AF adjustment"),
        (:h_, Float64, MWhGeneratedPerMWhCapacity, true, "Availability factor of hour _.  Include 1 column for each hour in the hours table.  I.e. `:h1`, `:h2`, ... `:hn`"),
    )
    return df
end


@doc """
    summarize_table(::Val{:build_gen})

$(table2markdown(summarize_table(Val(:build_gen))))
"""
function summarize_table(::Val{:build_gen})
    df = TableSummary()
    push!(df, 
        (:area, AbstractString, NA, true, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, true, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),
        (:build_status, String15, NA, true, "Whether the generator is `built`, `new`, `unbuilt`, or `unretrofitted`. All generators marked `new` when the gen file is read in will be changed to `built`.  Can also be changed to `retired_exog` or `retired_endog` after the simulation is run. See [`update_build_status!`](@ref).  Note that `unretrofitted` means it is a [`Retrofit`](@ref) option based on a `built` generator."),
        (:build_type, AbstractString, NA, true, "Whether the generator is 'real', 'exog' (exogenously built), or 'endog' (endogenously built). Should either be exog or endog for buil_gen."),
        (:build_id, AbstractString, NA, true, "Identifier of the build row.  Each generator made using this build spec will inherit this `build_id`"),
        (:genfuel, AbstractString, NA, true, "The fuel type that the generator uses. Leave blank to not filter by genfuel."),
        (:gentype, String, NA, true, "The generation technology type that the generator uses. Leave blank to not filter by gentype."),
        (:status, Bool, NA, false, "Whether or not to use this set of characteristics/specs"),
        (:pcap0, Float64, MWCapacity, true, "Starting nameplate power generation capacity for the generator. Should be 0 for endog new gens."),
        (:pcap_min, Float64, MWCapacity, true, "Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement)"),
        (:pcap_max, Float64, MWCapacity, true, "Maximum nameplate power generation capacity of the generator"),
        (:vom, Float64, DollarsPerMWhGenerated, true, "Variable operation and maintenance cost per MWh of generation"),
        (:fuel_price, Float64, DollarsPerMMBtu, false, "Fuel cost per MMBtu of fuel used.  `heat_rate` column also necessary when supplying `fuel_price`"),
        (:fom, Float64, DollarsPerMWCapacityPerHour, true, "Hourly fixed operation and maintenance cost for a MW of generation capacity"),
        (:capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for a MW of generation capacity"),
        (:transmission_capex, Float64, DollarsPerMWBuiltCapacityPerHour, true, "Hourly capital expenditures for the transmission supporting a MW of generation capacity"),
        (:routine_capex, Float64, DollarsPerMWCapacityPerHour, true, "Routing capital expenditures for a MW of discharge capacity"),
        (:cf_min, Float64, MWhGeneratedPerMWhCapacity, false, "The minimum capacity factor, or operable ratio of power generation to capacity for the generator to operate.  Take care to ensure this is not above the hourly availability factor in any of the hours, or else the model may be infeasible.  Set to zero by default."),
        (:cf_max, Float64, MWhGeneratedPerMWhCapacity, false, "The maximum capacity factor, or operable ratio of power generation to capacity for the generator to operate"),
        (:cf_hist, Float64, MWhGeneratedPerMWhCapacity, false, "The historical capacity factor for the generator or the gentype. Primarily used to calculate estimate policy value (PTC and EmissionPrice capex_adj)"),
        (:year_on, YearString, Year, true, "The first year of operation for the generator. (For new gens this is also the year it was built). Endogenous unbuilt generators will be left blank"),
        (:econ_life, Float64, NumYears, true, "The number of years in the economic lifetime of the generator."),
        (:age_shutdown, Float64, NumYears, true, "The age at which the generator is no longer operating.  I.e. if `year_on` = `y2030` and `age_shutdown` = `20`, then capacity will be 0 in `y2040`."),
        (:year_on_min, YearString, Year, true, "The first year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
        (:year_on_max, YearString, Year, true, "The last year in which a generator can be built/come online (inclusive). Generators with no restriction and exogenously built gens will be left blank"),
        (:emis_co2, Float64, ShortTonsPerMWhGenerated, false, "The CO2 emission rate of the generator, in short tons per MWh generated.  This is the net emissions. (i.e. not including captured CO2 that gets captured)"),
        (:capt_co2_percent, Float64, NA, false, "The percentage of co2 emissions captured, to be sequestered."),
    )
    return df
end

@doc """
    summarize_table(::Val{:genfuel})

$(table2markdown(summarize_table(Val(:genfuel))))
"""
function summarize_table(::Val{:genfuel})
    df = TableSummary()
    push!(df, 
        (:gentype, String, NA, true, "The generator type (ie. ngcc, dist_solar, os_wind)"),
        (:genfuel, AbstractString, NA, true, "The corresponding generator fuel or renewable type (ie. ng, solar, wind)"),
    )
    return df
end

# Data Accessor Functions
################################################################################

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
export get_table
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
function add_table_col!(data, table_name, column_name, col::AbstractVector, unit, description; warn_overwrite = true)
    # Add col to table
    table = get_table(data, table_name)
    hasproperty(table, column_name) && warn_overwrite == true && @warn "Table data[$table_name] already has column $column_name, overwriting"
    table[!, column_name] = col

    # Document in the summary table
    summary_table = get_table(data, :summary_table)
    data_type = _eltype(col)
    row = (;table_name, column_name, data_type, unit, required=false, description)
    push!(summary_table, row)
    data[:unit_lookup][(table_name, column_name)] = unit
    data[:desc_lookup][(table_name, column_name)] = description
end
function add_table_col!(data, table_name, column_name, ar::AbstractArray{<:Real, 3}, unit, description; warn_overwrite = true)
    v = [view(ar, i, :, :) for i in 1:size(ar, 1)]
    return add_table_col!(data, table_name, column_name, v, unit, description; warn_overwrite)
end
function add_table_col!(data, table_name, column_name, ar::AbstractMatrix{<:Real}, unit, description; warn_overwrite = true)
    # Might need to make this into a container.
    v = [view(ar, i, :) for i in 1:size(ar, 1)]
    return add_table_col!(data, table_name, column_name, v, unit, description; warn_overwrite)
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
            haskey(ul, (table_name, :y_)) && return ul[(table_name, :y_)]
        end
        return NA
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
            haskey(ul, (table_name, :y_)) && return ul[(table_name, :y_)]
        end
        return ""
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
function get_table_num(data, table_name, col_name, row_idx::Int64, yr_idx::Int64, hr_idx)
    table = get_table(data, table_name)
    container = table[row_idx, col_name]
    return container[yr_idx, hr_idx]::Float64
end
function get_table_num(data, table_name, col_name, row_idx::Int64, yr_idx::AbstractString, hr_idx)
    return get_table_num(data, table_name, col_name, row_idx, get_year_idxs(data, yr_idx), hr_idx)
end
export get_table_num

"""
    get_num(data, variable_name, yr_idx, hr_idx) -> num::Float64

    get_num(table, col_name, row_idx, yr_idx, hr_idx) -> num::Float64

Retrieves a `Float64` from `data[variable_name]`, indexing by year and hour.  Works for [`Container`](@ref)s and `Number`s.

Related functions:
* [`get_table_val(data, table_name, col_name, row_idx)`](@ref): retrieves the raw value from the table (without indexing by year/hour).
* [`get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)`](@ref): retrieves the `Float64` from `data[variable_name]`, indexing by year and hour.
* [`get_val(data, variable_name)`](@ref): retrieves the value from data[variable_name] regardless of type, not indexed by row, year or hour. 
"""
function get_num(data, variable_name::Symbol, yr_idx, hr_idx)
    c = data[variable_name]
    return c[yr_idx, hr_idx]::Float64
end
function get_num(table::DataFrame, col_name::Symbol, row_idx::Int64, yr_idx::Int64, hr_idx)
    container = table[row_idx, col_name]
    return container[yr_idx, hr_idx]::Float64
end
export get_num

"""
    get_val(data, variable_name::Symbol) -> 

Retrieves the value from data[variable_name], not indexed by row, hour, or year and regardless of type. (ex: could work for retrieving a ByYear container of yearly data)

Related functions:
* [`get_table_val(data, table_name, col_name, row_idx)`](@ref): retrieves the raw value from the table (without indexing by year/hour).
* [`get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)`](@ref): retrieves the `Float64` from `data[variable_name]`, indexing by year and hour.
* [`get_num(data, name, yr_idx, hr_idx)`](@ref): retrieves a `Float64` from `data`, indexing by year and hour.
"""
function get_val(data, variable_name::Symbol)
    c = data[variable_name]
    return c
end

"""
    get_table_val(data, table_name, col_name, row_idx) -> val

Returns the value of the table at column `col_name` and row `row_idx`

Related functions:
* [`get_table_num(data, table_name, col_name, row_idx, yr_idx, hr_idx)`](@ref): retrieves the `Float64` from `data[variable_name]`, indexing by year and hour.
* [`get_num(data, name, yr_idx, hr_idx)`](@ref): retrieves a `Float64` from `data`, indexing by year and hour.
* [`get_val(data, variable_name)`](@ref): retrieves the value from data[variable_name] regardless of type, not indexed by row, year or hour.
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
    get_table_summary(data, table_name) -> summary::SubDataFrame

Returns a summary of `table_name`, read in from [`summarize_table`](@ref) and [`read_summary_table!`](@ref).
"""
function get_table_summary(data, table_name)
    st = get_table(data, :summary_table)
    return filter(:table_name => ==(table_name), st; view=true)
end
export get_table_summary

"""
    get_load_array(data)

Returns the load array, a 3d array of load indexed by [load_idx, yr_idx, hr_idx]
"""
function get_load_array(data)
    return data[:load_array]::Array{Float64,3}
end
export get_load_array

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

"""
    get_af(data, gen_idx, year_idx, hour_idx) -> af

Retrieves the availability factor for a generator at a year and a time.
"""
function get_af(data, gen_idx, year_idx, hour_idx)
    return get_table_num(data, :gen, :af, gen_idx, year_idx, hour_idx)
end

export get_af

"""
    get_plnom(data, bus_idx, year_idx, hour_idx) -> plnom

Retrieves the load power for a bus at a year and a time.
"""
function get_plnom(data, bus_idx, year_idx, hour_idx)
    return get_table_num(data, :bus, :plnom, bus_idx, year_idx, hour_idx)
end
export get_plnom

"""
    get_elnom(data, bus_idx, year_idx, hour_idx) -> ed::Float64 (MWh)

    get_elnom(data, bus_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

Retrieve the total energy load for a bus at a given year and hour(s).
"""
function get_elnom(data, bus_idx::Int64, year_idx::Int64, hour_idx::Int64)
    return get_hour_weight(data, hour_idx) * get_plnom(data, bus_idx, year_idx, hour_idx)
end
function get_elnom(data, bus_idx::Int64, year_idx::Int64, hour_idxs)
    return sum(get_hour_weight(data, hour_idx) * get_plnom(data, bus_idx, year_idx, hour_idx) for hour_idx in hour_idxs)
end
function get_elnom(data, bus_idx::Int64, year_idx::Int64, hour_idxs::Colon)
    hour_weights = get_hour_weights(data)
    return sum(hour_weights[hour_idx] * get_plnom(data, bus_idx, year_idx, hour_idx) for hour_idx in eachindex(hour_weights))
end
function get_elnom(data, bus_idx=(:), year_idx=(:), hour_idx=(:))
    _bus_idxs = get_table_row_idxs(data, :bus, bus_idx)
    _year_idxs = get_year_idxs(data, year_idx)
    _hour_idxs = get_hour_idxs(data, hour_idx)
    hour_weights = get_hour_weights(data)
    return sum(hour_weights[h] * get_plnom(data, b, y, h) for h in _hour_idxs, y in _year_idxs, b in _bus_idxs)
end

"""
    get_elnom_load(data, load_idx, year_idx, hour_idxs) -> ed::Float64 (MWh)

    get_elnom_load(data, load_idxs, year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

    get_elnom_load(data, pair(s), year_idx, hour_idxs) -> ed::Float64 (MWh) (sum)

Return the energy load by load elements corresponding to `load_idx` or `load_idxs`, for `year_idx` and `hour_idx`.  Note `year_idx` can be the index or the year string (i.e. "y2030").

If pair(s) are given, filters the load elements by pair.  i.e. pairs = ("nation"=>"narnia", "read_type"=>"residential").
"""
function get_elnom_load(data, load_idxs::AbstractVector{Int64}, year_idx::Int64, hour_idxs)
    load_arr = get_load_array(data)
    load_mat = view(load_arr, load_idxs, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(load_mat, hour_weights)
end
function get_elnom_load(data, ::Colon, year_idx::Int64, hour_idxs)
    load_arr = get_load_array(data)
    load_mat = view(load_arr, :, year_idx, hour_idxs)
    hour_weights = get_hour_weights(data, hour_idxs)
    return _sum_product(load_mat, hour_weights)
end

function get_elnom_load(data, pairs, year_idx::Int64, hour_idxs)
    nominal_load = get_table(data, :nominal_load, pairs...)
    return get_elnom_load(data, getfield(nominal_load, :rows), year_idx, hour_idxs)
end

function get_elnom_load(data, pair::Pair, year_idx::Int64, hour_idxs)
    nominal_load = get_table(data, :nominal_load, pair)
    return get_elnom_load(data, getfield(nominal_load, :rows), year_idx, hour_idxs)
end
function get_elnom_load(data, load_idxs, y::String, hr_idx)
    year_idx = findfirst(==(y), get_years(data))
    return get_elnom_load(data, load_idxs, year_idx, hr_idx)
end
export get_elnom, get_elnom_load


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
    get_bus_gens(data, bus_idx)

Returns an array of the gen_idx of all the gens at the bus.
"""
function get_bus_gens(data, bus_idx) 
    gen = get_table(data, :gen)
    return findall(==(bus_idx), gen.bus_idx)
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
    # If we want voll to be by bus_idx this could be modified and read_voll() will need to be changed
    return data[:voll]
end
export get_voll


