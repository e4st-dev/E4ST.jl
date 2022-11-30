Availability Factor Table
=========================

Often, generators are unable to generate energy at their nameplate capacity over the course of any given representative hour.  This could depend on any number of things, such as how windy it is during a given representative hour, the time of year, the age of the generating unit, etc.  The ratio of available generation capacity to nameplate generation capacity is referred to as the availability factor (AF).

The availability factor table includes availability factors for groups of generators specified by any combination of area, genfuel, gentype, year, and hour.

### Required fields:

| Column Name | Data Type | Unit | Description |
| :-- | :-- | :-- | :-- |
| `area` | `String` | n/a | The area with which to filter by. I.e. "state". Leave blank to not filter by area.  |
| `subarea` | `String` | n/a | The subarea to include in the filter.  I.e. "maryland".  Leave blank to not filter by area. |
| `genfuel` | `String` | n/a | The fuel type that the generator uses. Leave blank to not filter by genfuel. |
| `gentype` | `String` | n/a | The generation technology type that the generator uses. Leave blank to not filter by gentype. |
| `year` | `String` | year | The year to apply the AF's to, expressed as a year string prepended with a "y".  I.e. "y2022" |
| `status` | `Bool` | n/a | Whether or not to use this AF adjustment |
| `h1` | `Float64` | ratio | Availability factor of hour 1 |
| `hn` | `Float64` | ratio | Availability factor of hour n |