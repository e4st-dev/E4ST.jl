Bus Table
=========

```@docs
load_bus_table!
summarize_bus_table
```

#### Column Summary

```@example
using E4ST # hide
summarize_bus_table() # hide
```

#### Additional Columns:

Depending on what you are doing with the model, you may require additional fields associated with buses.  These could be things like:
* `latitude` and `longitude`
* The area that a bus is in such as `state`
* The grid that the bus dispatches to