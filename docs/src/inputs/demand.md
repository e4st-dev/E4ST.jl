# Demanded Power

## Demand Table

```@docs
setup_demand!
summarize_demand_table
```

#### Column Summary
```@example demand
using E4ST # hide
summarize_demand_table() # hide
```

## Shaping Hourly Demand

```@docs
shape_demand!(config, data)
summarize_demand_shape_table()
```

#### Column Summary
```@example demand
summarize_demand_shape_table() # hide
```

## Matching Yearly Demand
```@docs
match_demand!(config, data)
summarize_demand_match_table()
```

#### Column Summary
```@example demand
summarize_demand_match_table() # hide
```

## Adding Hourly Demand
```@docs
add_demand!(config, data)
summarize_demand_add_table()
```

#### Column Summary
```@example demand
summarize_demand_add_table() # hide
```


