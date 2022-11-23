Bus Table
=========

Table representing all existing buses (also sometimes referred to as nodes or subs/substations) to be modeled.


## Required Columns:

| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `ref_bus` | `Bool` | n/a | Whether or not the bus is a reference bus.  There should be a single reference bus for each island. |
| `pd` | `Float64` | MW | The demanded load power at the bus |

## Optional Columns:
| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `<area>` | `String` | n/a | Which `subarea` of `area` that the bus is in.  An example `area` might be `state`, and a subarea might be `maryland`.  Generally, we like to write all lowercase with underscore separators. |
