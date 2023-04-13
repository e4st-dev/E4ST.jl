Storage
=======

```@docs
Storage
modify_raw_data!(::Storage, config, data)
modify_setup_data!(::Storage, config, data)
modify_model!(::Storage, config, data, model)
modify_results!(::Storage, config, data)
```

#### Column Summary for `storage` Table
```@example stor
using E4ST # hide
summarize_table(:storage) # hide
```

#### Column Summary for `build_storage` Table
```@example stor
summarize_table(:build_storage) # hide
```