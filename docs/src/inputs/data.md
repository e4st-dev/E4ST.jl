Data
====
## Loading Data
```@docs
read_data
read_data_files!(config, data)
modify_raw_data!(config, data)
setup_data!
modify_setup_data!(config, data)
read_summary_table!
setup_table!(config, data, ::Symbol)
```

## Accessor Functions
```@docs
get_table_summary
get_table_names
get_table
get_table_row_idxs
get_table_val
get_table_num
get_table_col
get_table_col_type
get_table_col_unit
get_table_col_description
get_row_idxs
get_year_idxs
get_hour_idxs
has_table
get_num
parse_comparison
parse_comparisons
parse_year_idxs
parse_hour_idxs
comparison
```