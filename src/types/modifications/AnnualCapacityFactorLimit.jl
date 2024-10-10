
"""
    struct AnnualCapacityFactorLimit <: Modification

    AnnualCapacityFactorLimit(;name, file)

Sets annual capacity factor limits for generators.  Annual capacity factor is defined as the total energy generated in a year divided by the total amount of energy capacity (power capacity times the number of hours in a year).

* `modify_raw_data!` - Loads in a table from `file`, stores it into `data[<name>]`.  See summarize_table(::Val{:annual_cf_lim})
* `modify_model!` - sets up the following constraints and expressions
  * Sets up expression `model[:egen_gen_annual]` (ngen x nhr) for annual energy generation for each generator
  * Creates constraint `model[:cons_<name>_min]` for each generator covered by each row of the table specified in `file`, if the `annual_cf_min` column is given.
  * Creates constraint `model[:cons_<name>_max]` for each generator covered by each row of the table specified in `file`, if the `annual_cf_max` column is given.
"""
Base.@kwdef struct AnnualCapacityFactorLimit <: Modification
    name::Symbol
    file::String
end
export AnnualCapacityFactorLimit

@doc """
    summarize_table(::Val{:annual_cf_lim})

$(table2markdown(summarize_table(Val(:annual_cf_lim))))
"""
function summarize_table(::Val{:annual_cf_lim})
    df = TableSummary()
    push!(df,
        (:genfuel, AbstractString, NA, false, "The fuel type that the generator uses.  Leave blank to not filter by genfuel."),
        (:gentype, String, NA, false, "The generation technology type that the generator uses.  Leave blank to not filter by gentype."),
        (:area, AbstractString, NA, false, "The area with which to filter by. I.e. \"state\". Leave blank to not filter by area."),
        (:subarea, AbstractString, NA, false, "The subarea to include in the filter.  I.e. \"maryland\".  Leave blank to not filter by area."),    
        (:filter_, String, NA, false, "There can be multiple filter conditions - `filter1`, `filter2`, etc.  It denotes a comparison used for selecting the table rows to apply the adjustment to.  See `parse_comparison` for examples"),
        (:status, Bool, NA, false, "Whether or not to use this limit"),
        (:annual_cf_min, Float64, MWhGeneratedPerMWhCapacity, false, "The minimum annual capacity factor ∈ (0,1].  If outside these bounds, not set.  Be very careful - easy to make model infeasible if contradictory to availability factors."),
        (:annual_cf_max, Float64, MWhGeneratedPerMWhCapacity, false, "The maximum annual capacity factor ∈ [0,1).  If outside these bounds, not set."),
    )
    return df
end

function modify_raw_data!(m::AnnualCapacityFactorLimit, config, data)
    file = m.file
    name = m.name
    table = read_table(data, file, :annual_cf_lim)
    data[name] = table
end

function modify_model!(m::AnnualCapacityFactorLimit, config, data, model)
    table = get_table(data, m.name)
    hasproperty(table, :status) && filter!(:status=> ==(true), table)
    gen = get_table(data, :gen)
    pcap = model[:pcap_gen]::Array{VariableRef,2} # ngen x nyr
    pgen = model[:pgen_gen]::Array{VariableRef,3} # ngen x nyr x nhr
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hour_weights = get_hour_weights(data)
    hrs_per_yr = sum(hour_weights)

    # Find gen indexes to apply the constraint to
    gen_idx_sets = map(eachrow(table)) do row
        get_row_idxs(gen, parse_comparisons(row))
    end
    table.gen_idx_sets = gen_idx_sets

    if haskey(model, :egen_gen_annual)
        egen_gen_annual = model[:egen_gen_annual]::Matrix{AffExpr}
    else
        @expression(
            model,
            egen_gen_annual[
                gen_idx in axes(gen,1),
                yr_idx in 1:nyr
            ],
            AffExpr(0.0)
        )
        for g in axes(gen, 1), y in 1:nyr
            cur_egen_gen_annual = egen_gen_annual[g, y]
            for h in 1:nhr
                add_to_expression!(cur_egen_gen_annual, pgen[g, y, h], hour_weights[h])
            end
        end
    end


    # Set the min annual capacity limit, if applicable.
    if hasproperty(table, :annual_cf_min)
        annual_cf_min = table.annual_cf_min::Vector{Float64}
        model[Symbol("cons_$(m.name)_min")] = @constraint(
            model,
            [
                row_idx in axes(table,1),
                gen_idx in gen_idx_sets[row_idx],
                yr_idx in 1:nyr;
                annual_cf_min[row_idx] > 0 && annual_cf_min[row_idx] <= 1
            ],
            egen_gen_annual[gen_idx, yr_idx] >= pcap[gen_idx] * hrs_per_yr * annual_cf_min[row_idx]
        )
    end

    # Set the max annual capacity limit, if applicable.
    if hasproperty(table, :annual_cf_max)
        annual_cf_max = table.annual_cf_max::Vector{Float64}
        model[Symbol("cons_$(m.name)_max")] = @constraint(
            model,
            [
                row_idx in axes(table,1),
                gen_idx in gen_idx_sets[row_idx],
                yr_idx in 1:nyr;
                annual_cf_max[row_idx] >= 0 && annual_cf_max[row_idx] < 1
            ],
            egen_gen_annual[gen_idx, yr_idx] <= pcap[gen_idx] * hrs_per_yr * annual_cf_max[row_idx]
        )
    end
end