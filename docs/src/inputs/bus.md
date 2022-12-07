Bus Table
=========

Table representing all existing buses (also sometimes referred to as nodes or subs/substations) to be modeled.  


## Columns:

```@example
using E4ST # hide
summarize_bus_table()
```

## Additional Fields:

Depending on what you are doing with the model, you may require additional fields associated with buses.  These could be things like:
* `latitude` and `longitude`
* The area that a bus is in such as `state`
* The grid that the bus dispatches to