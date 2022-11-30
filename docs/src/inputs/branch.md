Branch Table
============
Table representing all existing branches (AC transmission lines) to be modeled.

Note that the Branch Table does not contain DC transmission lines.

## Required Columns:

| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `f_bus_idx` | `Int64` | n/a | The index of the `bus` table that the branch originates **f**rom |
| `t_bus_idx` | `Int64` | n/a | The index of the `bus` table that the branch goes **t**o |
| `status` | `Bool` | n/a | Whether or not the branch is in service |
| `x` | `Float64` | p.u. | Per-unit reactance of the line (resistance assumed to be 0 for DC-OPF) |
| `pf_max` | `Float64` | $MW$ | Maximum power flowing through the branch |