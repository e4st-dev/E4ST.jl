"""
    struct RetailPriceCalibration <: Modification

Arguments/keyword arguments:
* name::Symbol
* file - file with retail price calibrator values.
"""
struct RetailPriceCalibration <: Modification
    name::Symbol
    res_name::Symbol
    file::String
end
RetailPriceCalibration(; name, res_name, file) = RetailPriceCalibration(name, res_name, file)
export RetailPriceCalibration

mod_rank(::Type{<:RetailPriceCalibration}) = 5.0

"""
    modify_results!(mod::RetailPriceCalibration, config, data)
"""
function modify_results!(mod::RetailPriceCalibration, config, data)
    println("in the modification for retail price calibration")
    results = get_results(data)
    haskey(results, mod.res_name) || (@warn "Missing $(mod.res_name) in data, skipping calibration."; return)
    retail_price = results[mod.res_name]
    nyr = get_num_years(data)
    years = get_years(data)
    bus = get_table(data,:bus)

    
    filter_cols = setdiff(propertynames(retail_price), [:table_name, :result_name, :filter_years, :filter_hours, :value])
    for filter in filter_cols
        if !isempty(retail_price[!,filter])
            println(filter)
            unique_firsts = unique(first.(split.(retail_price[!,filter], "=>")))
            println(unique_firsts)
        end
    end

    println(filter_cols)
    ref_price_table = read_table(mod.file)
    stack_cols = Symbol.(intersect(names(ref_price_table), years))
    # retail_price.ref_price .= 0
    
    # for i in 1:nrow(ref_price_table)
    #     row = ref_price_table[i,:]

    #     get(row, :status, true) || continue
    #     # shape = Float64[row[i_yr] for i_yr in yr_idx:(yr_idx + nyr - 1)]

    #     filters = parse_comparisons(row)
    #     println(filters)
    #     # ref_price_table.filter

    #     tmp_retail_price = deepcopy(retail_price)
    #     for filter in filters
    #         filter = string(first(filter)filter2string(filter)
    #         filter!(row -> any(c -> row[c] == filter, filter_cols), tmp_retail_price)
    #     end
       
    #     stacked_row = DataFrames.stack(ref_price_table[i:i, vcat(:area, :subarea, stack_cols)], 
    #     stack_cols, [:area, :subarea], variable_name=:filter_years,value_name=:ref_price)
   
    #     stacked_row.filter_years .= "years=>" .* string.(stacked_row.filter_years)
      
    #     tmp_retail_price = innerjoin(tmp_retail_price, stacked_row, on = [:filter_years])
    #     println(tmp_retail_price)
       
    # end
    # to do: the price may need to be energy demand/consumption
    # CSV.write(get_out_path(config, string(m.name, ".csv")), table)
end
export modify_results!

# function extract_results(m::WelfareTable, config, data)
#     results = get_results(data)
#     haskey(results, m.name) || modify_results!(m, config, data)
#     return get_result(data, m.name)
# end

# function combine_results(m::WelfareTable, post_config, post_data)
    
#     res = join_sim_tables(post_data, :value)

#     CSV.write(get_out_path(post_config, "$(m.name)_combined.csv"), res)
# end
