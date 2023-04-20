Bus Table
=========

```@docs
setup_table!(config, data, ::Val{:bus})
summarize_table(::Val{:bus})
```

#### Additional Columns:

Depending on what you are doing with the model, you may require additional fields associated with buses.  These could be things like:
* `latitude` and `longitude`
* The area that a bus is in such as `state`
* The grid that the bus dispatches to