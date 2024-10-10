Results Overview
================
After optimizing the model, the following things happen:
* [`parse_results!`](@ref) is called, gathering all values and shadow prices from the JuMP Model into `data[:raw]`.  The model is then emptied to free up memory.  After running this, raw results can be accessed with:
    * [`get_raw_result`](@ref) and [`get_raw_results`](@ref)
    * results can now be computed using [`compute_result`](@ref)
* [`process_results!`](@ref) is called, which in turn calls [`modify_results!(mod, config, data)`] for each [`Modification`](@ref) in the config.  Here are a couple of [`Modification`](@ref)s that write some handy results:
    * [`YearlyTable`](@ref)
    * [`ResultsTemplate`](@ref)


```@docs
parse_results!
process_results!
parse_lmp_results!
parse_power_results!
get_raw_results
get_raw_result
get_results
get_result
add_result!
save_updated_gen_table
update_build_status!
read_parsed_results
read_processed_results
```