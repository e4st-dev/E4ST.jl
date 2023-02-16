# Demanded Power

## Demand Table

```@docs
setup_table!(config, data, ::Val{:demand_table})
summarize_table(::Val{:demand_table})
```

#### Column Summary
```@example demand
using E4ST # hide
summarize_table(:demand_table) # hide
```

## Shaping Hourly Demand

```@docs
shape_demand!(config, data)
summarize_table(::Val{:demand_shape})
```

#### Column Summary
```@example demand
summarize_table(:demand_shape) # hide
```

## Matching Yearly Demand
```@docs
match_demand!(config, data)
summarize_table(::Val{:demand_match})
```

#### Column Summary
```@example demand
summarize_table(:demand_match) # hide
```

## Adding Hourly Demand
```@docs
add_demand!(config, data)
summarize_table(::Val{:demand_add})
```

#### Column Summary
```@example demand
summarize_table(::Val{:demand_add}) # hide
```


