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

    
    filter_cols = setdiff(propertynames(retail_price), [:table_name, :result_name])
   
    ref_price_table = read_table(mod.file)
    stack_cols = intersect(names(ref_price_table), years)
    # retail_price.ref_price .= 0
    
    for i in 1:nrow(ref_price_table)
        println("in the rows")
        row = ref_price_table[i, :]

        get(row, :status, true) || continue
        # shape = Float64[row[i_yr] for i_yr in yr_idx:(yr_idx + nyr - 1)]

        filters = parse_comparisons(row)
        # ref_price_table.filter

        tmp_retail_price = deepcopy(retail_price)
        for filter in filters
            filter!(row -> any(c -> row[c] == filter, filter_cols), tmp_retail_price)
        end
        println(filters)
        println(tmp_retail_price)
        stacked_row = stack(DataFrame(row), stack_cols, variable_name=:filter_years,value_name=:ref_price)
   
        stacked_row.filter_years .= "years=>" .* string.(stacked_row.filter_years)
      
        tmp_retail_price = innerjoin(tmp_retail_price, stacked_row, on = :filter_years)
        # println(tmp_retail_price)
       
    end

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
