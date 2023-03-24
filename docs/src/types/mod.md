Modifications
=============
```@docs
Modification
modify_raw_data!(::Modification, config, data)
modify_setup_data!(::Modification, config, data)
modify_model!(::Modification, config, data, model)
modify_results!(::Modification, config, data)
fieldnames_for_yaml(::Type{<:Modification})
```

## DCLine
```@docs
DCLine
modify_raw_data!(mod::DCLine, config, data)
modify_model!(mod::DCLine, config, data, model)
```
#### Column Summary for `dc_line` Table
```@example
using E4ST # hide
summarize_table(:dc_line) # hide
```