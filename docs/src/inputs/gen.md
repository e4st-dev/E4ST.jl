Generator Table
===============
Table representing all existing generators to be modeled.

Note that the generator table does **not** contain Direct Air Capture, or Storage facilities.

## Required Columns:

| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `bus_idx` | `Int64` | n/a | The index of the `bus` table that the generator corresponds to |
| `status` | `Bool` | n/a | Whether or not the generator is in service |
| `genfuel` | `String` | n/a | The fuel type that the generator uses |
| `gentype` | `String` | n/a | The generation technology type that the generator uses |
| `pcap_min` | `Float64` | $MW$ | Minimum nameplate power generation capacity of the generator (normally set to zero to allow for retirement) |
| `pcap_max` | `Float64` | $MW$ | Maximum nameplate power generation capacity of the generator |
| `vom` | `Float64` | $\$/MWh$ | Variable operation and maintenance cost per $MWh$ of generation |
| `fom` | `Float64` | $\$/MW$ | Hourly fixed operation and maintenance cost for a $MW$ of generation capacity |
| `capex` | `Float64` | $\$/MW$ | Hourly capital expenditures for a $MW$ of generation capacity |


