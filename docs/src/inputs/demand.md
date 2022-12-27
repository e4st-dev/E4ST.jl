# Demanded Power

## Demand Table

```@docs
load_demand_table!
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
load_demand_shape_table!
shape_demand!(config, data)
summarize_demand_shape_table()
```

#### Column Summary
```@example demand
summarize_demand_shape_table() # hide
```

## Matching Yearly Demand
```@docs
load_demand_match_table!
match_demand!(config, data)
summarize_demand_match_table()
```

#### Column Summary
```@example demand
summarize_demand_match_table() # hide
```

## Adding Hourly Demand
```@docs
load_demand_add_table!
add_demand!(config, data)
summarize_demand_add_table()
```

#### Column Summary
```@example demand
summarize_demand_add_table() # hide
```


