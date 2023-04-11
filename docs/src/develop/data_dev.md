## E4ST Data Processing for Development

### Adding another standard data file
If you'd like to add in another standard data file to be loaded into E4ST (ex: data that is required for a new standard feature of E4ST), you will need to modify the `data.jl` file. 

In the `data.jl` file:

1. Add the `read_table!(config, data, :new_table_file=>:new_table)` to `read_data_files!` (in the documentation and called in the function). 

2. Create a `summarize_table(::Val{:new_table})` method that mirrors the other summarize functions. This should list the columns, their type, their unit, whether they are required, and a decription of the column. This is called in `read_table!`

3. Create a `setup_table!(config, data, ::Val{:new_table})` function. This is where you can make any changes to your data to get it into the structure needed for the DCOPF. This could include added calculated columns, putting things into containers, etc. This is not for Modifications, only standard processes that will need to happen whenever you load in that data from the csv. This can be an empty function if no setup is required. 

4. Add the `setup_table!(config, data, :new_table)` function to `setup_data! ` (in the documentation and called in the function).  This may be order-specific, so be careful with that.

### A note on adding a column to a data table
The summary table contains important information about each column of each table.  There is nothing enforcing that every column must have a summary, but it is strongly advised.  It is particularly important for aggregating results, where different units get added/averaged in different ways.  To add a column to a data table, it is best to use the function `add_table_col!(data, table_name, column_name, column, unit, description)`.