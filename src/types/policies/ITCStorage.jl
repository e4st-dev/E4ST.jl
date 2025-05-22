
"""
    struct ITCStorage <: Policy

Investment Tax Credit - A tax incentive that is a percentage of capital cost given to storage units that meet the qualifications. 

### Keyword Arguments
* `name`: policy name
* `values`: the credit level, stored as an OrderedDict with year and value `(:y2020=>0.3)`.  Credit level refers to the percentage of the capex that will be rebated to the investor
* `storage_filters`: filters for qualifying storage, stored as an OrderedDict with gen table columns and values

### Table Columns Added 
* `(:storage, <name>)` - investment tax credit value for the policy 

### Model Modification 
* Expressions 
    * `pcap_stor_inv_sim[stor_idx]` - storage power discharge capacity invested in the sim.

### Results Formulas 
* `(:storage, :<name>_cost_obj)` - the cost of the policy, as seen by the objective, not used for government spending welfare
"""
Base.@kwdef struct ITCStorage <: Policy
    name::Symbol
    values::OrderedDict
    storage_filters::OrderedDict = OrderedDict{Symbol, Any}()
end
export ITCStorage

"""
    E4ST.modify_setup_data!(pol::ITCStorage, config, data)

Creates a column in the gen table with the ITCStorage value in each simulation year for the qualifying generators.
 
ITCStorage values are calculated based on `capex_obj` so ITCStorage values only apply in `year_on` for a generator.
"""
function E4ST.modify_setup_data!(pol::ITCStorage, config, data)
    if ~haskey(data, :storage)
        @warn "ITCStorage policy given, yet no storage defined.  Consider adding a Storage modification."
        return
    end

    storage = get_table(data, :storage)
    stor_idxs = get_row_idxs(storage, parse_comparisons(pol.storage_filters))

    @info "Applying ITCStorage $(pol.name) to $(length(stor_idxs)) storage units"

    years = get_years(data)

    #create column of annualized ITCStorage values
    add_table_col!(data, :storage, pol.name, Container[ByNothing(0.0) for i in 1:nrow(storage)], DollarsPerMWBuiltCapacityPerHour,
        "Investment tax credit value for $(pol.name)")

    #update column for gen_idx 
    credit_yearly = [get(pol.values, Symbol(year), 0.0) for year in years] #values for the years in the sim

    for stor_idx in stor_idxs
        stor = storage[stor_idx, :]

        # credit yearly * capex using the same filtering as capex_obj will
        # only non-zero for new builds, in an after their year_on and until end of econ life
        if stor.build_status == "unbuilt"
            vals_tmp = vec([(years[i] >= stor.year_on && years[i] < add_to_year(stor.year_on, stor.econ_life)) ? credit_yearly[i]*stor.capex[i,:] : 0.0 for i in 1:length(years)])
        else 
            vals_tmp = fill(0.0, length(years))
        end
        stor[pol.name] = ByYear(vals_tmp)
    end
end

"""
    function E4ST.modify_model!(pol::ITCStorage, config, data, model)
    
Subtracts the ITCStorage price * Capacity in that year from the objective function using [`add_obj_term!(data, model, PerMWCap(), pol.name, oper = -)`](@ref)
"""
function E4ST.modify_model!(pol::ITCStorage, config, data, model)
    if ~haskey(data, :storage)
        @warn "ITCStorage policy given, yet no storage defined.  Consider adding a Storage modification."
        return
    end

    nyr = get_num_years(data)
    storage = get_table(data, :storage)

    #name = Symbol("$(pol.name)_obj")
    name = pol.name
    pcap_stor_inv_sim = model[:pcap_stor_inv_sim]::Vector{AffExpr}
    model[name] = @expression(model,
        [stor_idx in axes(storage, 1), yr_idx in 1:nyr],
        sum(
            pcap_stor_inv_sim[stor_idx] * get_table_num(data, :storage, pol.name, stor_idx, yr_idx, :)
        )
    )

    add_obj_exp!(data, model, PerMWCapInv(), name, oper = -) 

    # Add things to results here so it gets saved in the right places
    total_result_name = "$(pol.name)_cost_obj"
    total_result_sym = Symbol(total_result_name)


    # calculate objective policy cost (based on capacity in each sim year)
    add_results_formula!(data, :storage, total_result_sym, "SumYearly($(pol.name),ecap_inv_sim)", Dollars, "The cost of $(pol.name) as seen by the objective, not used for gov spending welfare")
    #add_results_formula!(data, :gen, Symbol("$(pol.name)_cost_obj"), "SumHourly($(pol.name),ecap)", Dollars, "The cost of $(pol.name) as seen by the objective, not necessarily used for gov spending welfare")

    # calculate welfare policy cost (obj policy cost spread over all years of investment represented by the sim years)
    # if using pol_cost_obj, update the description provided in add_results_forumla above

    add_to_results_formula!(data, :storage, :invest_subsidy, total_result_name)
end


"""
    E4ST.modify_results!(pol::ITCStorage, config, data) -> 

Calculates ITCStorage cost as seen by the objective (cost_obj) which is ITCStorage value * capacity (where ITCStorage value is credit level as a % multiplied by capital cost)
"""
function E4ST.modify_results!(pol::ITCStorage, config, data)
    if ~haskey(data, :storage)
        @warn "ITCStorage policy given, yet no storage defined.  Consider adding a Storage modification."
        return
    end
end