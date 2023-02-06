# Yearly Adjustments

```@docs
setup_table!(config, data, ::Val{:adjust_yearly})
summarize_table(::Val{:adjust_yearly})
```

#### Column Summary
```@example
using E4ST # hide
summarize_table(:adjust_yearly) # hide
```

# Hourly Adjustments

```@docs
setup_table!(config, data, ::Val{:adjust_hourly})
summarize_table(::Val{:adjust_hourly})
```

#### Column Summary
```@example
using E4ST # hide
summarize_table(:adjust_hourly) # hide
```