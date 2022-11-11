Bus Table
=========

Table representing all existing buses (also sometimes referred to as nodes or subs/substations) to be modeled.


## Required Columns:

| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `ref_bus` | `Bool` | n/a | Whether or not the bus is a reference bus.  There should be a single reference bus for each island. |
| `pd` | `Float64` | MW | The demanded load power at the bus |