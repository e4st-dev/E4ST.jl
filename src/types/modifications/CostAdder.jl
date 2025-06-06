"""
    struct CostAdder <: Modification

This adds to the cost of some subset of generators or storage facilities as seen by the optimization, but does not add to any of the other results formulas or welfare terms.

# Keyword Arguments:
* `name::Symbol` - the name of the Modification
* `cost_type::Symbol` - the type of cost to add to, either `variable` or `fixed`.
* `table_name::Symbol` - the name of the table to add costs for, either `gen` or `storage`
* `values::OrderedDict{Symbol}` - the cost to add, in DollarsPerMWh for `variable` costs, or DollarsPerMWCapacityPerHour for `fixed` costs.  If `col_name` is provided, that may change the unit of the `values`.  For example, if `col_name` is `"capt_co2"`, which has a unit of ShortTonsPerMWhGenerated, the `values` should have a unit of `DollarsPerShortTonCO2Captured`. 
* `filters::OrderedDict{Symbol} = OrderedDict()` - filters for qualifying generators / storage, stored as an OrderedDict with gen table columns and values (`:emis_co2=>"<=0.1"` for co2 emission rate less than or equal to 0.1).  Defaults to empty `OrderedDict`, affecting the whole table.
* `col_name::String = ""` - which column to multiply the cost by, if any.  For example `capt_co2` for an adder for every unit of CO2
* `add_to_production_cost::Bool = false` - whether or not you want the cost adder to be reflected in the production cost
"""
struct CostAdder <: Modification
    name::Symbol
    cost_type::Symbol
    table_name::Symbol
    values::OrderedDict{Symbol, Float64}
    filters::OrderedDict{Symbol}
    col_name::String
    add_to_production_cost::Bool

    function CostAdder(;
            name,
            cost_type,
            table_name,
            values,
            filters = OrderedDict{Symbol,Any}(),
            col_name="",
            add_to_production_cost = false,
        )
        n = Symbol(name)
        ct = Symbol(cost_type)
        tn = Symbol(table_name)
        v = convert(OrderedDict{Symbol, Float64}, values)
        if ct ∉ (:variable, :fixed)
            error("cost_type must be either variable or fixed for Modification CostAdder $name, but $ct given")
        end

        if tn ∉ (:gen, :storage)
            error("table_name must be either gen or storage for Modification CostAdder $name, but $tn given")
        end

        return new(n,ct,tn, v, filters, col_name, convert(Bool, add_to_production_cost))
    end
end
export CostAdder

E4ST.mod_rank(::Type{CostAdder}) = 0.0

function E4ST.modify_raw_data!(m::CostAdder, config, data)
end

function E4ST.modify_setup_data!(m::CostAdder, config, data)

    table = get_table(data, m.table_name)

    row_idxs = get_row_idxs(table, parse_comparisons(m.filters))

    @info "Applying CostAdder $(m.name) to $(length(row_idxs)) rows of the $(m.table_name) table"

    years = get_years(data)
    unit = m.cost_type == :variable ? DollarsPerMWhGenerated : DollarsPerMWCapacityPerHour

    costs = Container[ByNothing(0.0) for i in 1:nrow(table)]
    add_table_col!(data, m.table_name, m.name, costs,
        unit,
        "The cost of CostAdder $(m.name) added to the objective, but not added to any results or welfare formulas"
    )

    yrs_sym = Symbol.(years)

    for row_idx in row_idxs
        if m.col_name == ""
            cost = ByYear([get(m.values, yr, 0.0) for yr in yrs_sym])
        else
            cost = ByYear([get(m.values, yr, 0.0) for yr in yrs_sym]) .* table[row_idx, m.col_name]
        end
        costs[row_idx] = cost
    end
end

function E4ST.modify_model!(m::CostAdder, config, data, model)
    
    make_cost_adder_exp!(m, data, model)   
    
    term = m.cost_type == :variable ? PerMWhGen() : PerMWCap()


    add_obj_exp!(data, model, term, m.name; oper= (+))
        
end

make_cost_adder_exp!(m, data, model) = make_cost_adder_exp!(m, Val(m.cost_type), Val(m.table_name), get_table(data, m.table_name), data, model)

function make_cost_adder_exp!(m, ::Val{:variable}, ::Val{:gen}, table, data, model)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hour_weights = get_hour_weights(data)
    col = table[!, m.name]::Vector{<:Container}

    var = model[:pgen_gen]::Array{VariableRef, 3}
    model[m.name] = @expression(model,
        [idx in axes(table,1), yr_idx in 1:nyr],
        sum(
            var[idx, yr_idx, hr_idx] * col[idx][yr_idx, hr_idx] * hour_weights[hr_idx] for hr_idx in 1:nhr
        )
    )
end

function make_cost_adder_exp!(m, ::Val{:fixed}, ::Val{:gen}, table, data, model)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hours_per_year = sum(get_hour_weights(data))
    col = table[!, m.name]::Vector{<:Container}

    var = model[:pcap_gen]::Array{VariableRef, 2}
    model[m.name] = @expression(model,
        [idx in axes(table,1), yr_idx in 1:nyr],
        var[idx, yr_idx] * col[idx][yr_idx, :] * hours_per_year
    )
end

function make_cost_adder_exp!(m, ::Val{:variable}, ::Val{:storage}, table, data, model)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hour_weights = get_hour_weights(data)
    col = table[!, m.name]::Vector{<:Container}

    var = model[:pdischarge_stor]::Array{VariableRef, 3}
    model[m.name] = @expression(model,
        [idx in axes(table,1), yr_idx in 1:nyr],
        sum(
            var[idx, yr_idx, hr_idx] * col[idx][yr_idx, hr_idx] * hour_weights[hr_idx] for hr_idx in 1:nhr
        )
    )
end
function make_cost_adder_exp!(m, ::Val{:fixed}, ::Val{:storage}, table, data, model)
    nyr = get_num_years(data)
    nhr = get_num_hours(data)
    hours_per_year = sum(get_hour_weights(data))
    col = table[!, m.name]::Vector{<:Container}

    var = model[:pcap_stor]::Array{VariableRef, 2}
    model[m.name] = @expression(model,
        [idx in axes(table,1), yr_idx in 1:nyr],
        var[idx, yr_idx] * col[idx][yr_idx, :] * hours_per_year
    )
end

function E4ST.modify_results!(m::CostAdder, config, data)
    if m.cost_type == :variable
        ptype = (m.table_name == :gen ? "pgen" : "pdischarge")
    else
        ptype = "pcap"
    end
    result_name = Symbol("$(m.name)_total")
    result_formula = "SumHourlyWeighted($(m.name),$(ptype))"
    add_results_formula!(data, m.table_name, result_name, result_formula, Dollars, "Total cost for $(m.name)")

    if m.add_to_production_cost == true
        cost_result_name = (m.cost_type == :variable ? :variable_cost : :fixed_cost)
        add_to_results_formula!(data, m.table_name, cost_result_name, result_name)
    end
end