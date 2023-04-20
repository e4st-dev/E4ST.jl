# Load Power

## Load Table

```@docs
setup_table!(config, data, ::Val{:nominal_load})
summarize_table(::Val{:nominal_load})
```

## Shaping Hourly Load

```@docs
shape_nominal_load!(config, data)
summarize_table(::Val{:load_shape})
```

## Matching Yearly Load
```@docs
match_nominal_load!(config, data)
summarize_table(::Val{:load_match})
```

## Adding Hourly Load
```@docs
add_nominal_load!(config, data)
summarize_table(::Val{:load_add})
```


