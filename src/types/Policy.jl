"""
    abstract type Policy <: Modification

This is a subtype of Modification that represents a policy to be modeled.

Basic Policy Types are used when defining standard policies in E4ST. They are specified as mods in the config file with a `type` field. 

There are currently six basic policy types. Novel policy types can also be added as needed. 

## Policies (Policy subtypes)
* [`ITC`](@ref)
* [`PTC`](@ref)
* [`EmissionCap`](@ref)
* [`EmissionPrice`](@ref)
* [`RPS`](@ref)
* [`CES`](@ref)
"""
abstract type Policy <: Modification end


### Loading in Policies -----------------------------------


# Outdated:Policies specified in CSVs should grouped by Type, meaning one CSV would only have one policy Type 
# Instead we decided to load in everything from a config file and will create scripts to write those config files for policies. 

# struct PolicySet <: Modification
#     file_path::AbstractString
# end
# export PolicySet

# mod_rank(::Type{PolicySet}) <: 0 #I want this to get called before other policies but not necessarily all mods so not sure what to set yet. 

# function modify_raw_data!(s::PolicySet, config, data)
#     pol_table = read_table(s.file_path)

#         for row in eachrow(pol_table)
#             T = get_type(row[:type])
#             get_field_values(config, data, T, row)

#             # mods[row[:name]] = Modificaiton() with all the info taken from get_field_values. Possibly T()
#         end
# end

# """
#     get_field_values(config, data, type, row::DataFrameRow) -> OrderedDict

# Creates an OrderedDict of the fields and their values for the given type from the row. 

# """
# function get_field_values(config, data, type, row::DataFrameRow)
#     fieldnames = fieldnames(type) # string names of fields for that policy type
#     row_cols = names(row) #string names of row column names

#     value_name = row[:value_name] #gets the name for the field in the policy that contains yearly or hourly values

#     fields = OrderedDict{Symbol, Any}()

#     # get informtion like filters, crediting type, etc from the row 
#     for fieldname in fieldnames
#         col_idxs = findall(row_col -> intersection(fieldname, row_col), row_cols)
        
#         if length(col_idxs) == 1
#             field = row[col_idxs]
#         elseif length(col_idxs) > 1
#             # field = OrderedDict of all column values where intersection(field, col_name) is true
#         end
    
#         fields[Symbol(fieldname)] = field
#     end

#     # Get yearly values from columns with "y" (and possibly hourly values from columns with "h")
#     # Convert them to an ordered dict and assign it to a variable with name of value_name
#     # add that ordered dict to the fields ordered dict
#     # TODO: It's possibly simpler to just name all those field 'value' again instead of having more descriptive names

#     return fields
# end

### Helper functions




