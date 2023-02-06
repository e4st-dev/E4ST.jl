Availability Factor Table
=========================

```@docs
setup_table!(config, data, ::Val{:af_table})
summarize_table(::Val{:af_table})
```

#### Column Summary
```@example
using E4ST # hide
summarize_table(:af_table) # hide
```