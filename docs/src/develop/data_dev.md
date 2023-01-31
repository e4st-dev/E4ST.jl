## E4ST Data Processing for Development

### Adding another standard data file
If you'd like to add in another standard data file to be loaded into E4ST (ex: data that is required for a new standard feature of E4ST), you will need to modify the `data.jl` file. 

In the `data.jl` file:

1. Create a `load_newdata_table!(config, data)` function that mirrors other load functions. 

2. Add the `load_newdata_table!` function to `load_data_files!` (in the documentation and called in the function). 

3. Create a `summarize_newdata_table()` function that mirros the other summarize functions. This should list the columns, their type, their unit, whether they are required, and a decription of the column. This is called in `load_newdata_table!`

4. Create a `setup_newdata_table!(config, data)` function. This is where you can make any changes to your data to get it into the structure needed for the DCOPF. This could include added calculated columns, putting things into containers, etc. This is not for Modifications, only standard processes that will need to happen whenever you load in that data from the csv. This can be an empty function if no setup is required. 

5. Add the `setup_newdata_table!` function to `setup_data! ` (in the documentation and called in the function).

6. Add the file path path to config file and to `make_paths_absolute()` function in `config.jl`


Some nonessential things to do for convenience: 

1. Create a `get_newdata_table(data)` accessor function to easily get that table. 

2. Create accessor functions for commonly used data from that table with the appropriate indices.