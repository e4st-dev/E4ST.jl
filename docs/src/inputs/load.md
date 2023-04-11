# Load Power

## Load Table

```@docs
setup_table!(config, data, ::Val{:nominal_load})
summarize_table(::Val{:nominal_load})
```

#### Column Summary
```@example load
using E4ST # hide
summarize_table(:nominal_load) # hide
```

## Shaping Hourly Load

```@docs
shape_nominal_load!(config, data)
summarize_table(::Val{:load_shape})
```

#### Column Summary
```@example load
summarize_table(:load_shape) # hide
```

## Matching Yearly Load
```@docs
match_nominal_load!(config, data)
summarize_table(::Val{:load_match})
```

#### Column Summary
```@example load
summarize_table(:load_match) # hide
```

## Adding Hourly Load
```@docs
add_nominal_load!(config, data)
summarize_table(::Val{:load_add})
```

#### Column Summary
```@example load
summarize_table(:load_add) # hide
```


