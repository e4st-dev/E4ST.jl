CO₂ Capture, Utilization & Storage
==================================

```@docs
CCUS
modify_raw_data!(::CCUS, config, data)
modify_setup_data!(::CCUS, config, data)
modify_model!(::CCUS, config, data, model)
modify_results!(::CCUS, config, data)
```

#### Column Summary for `ccus_paths` Table
```@example
using E4ST # hide
summarize_table(:ccus_paths) # hide
```