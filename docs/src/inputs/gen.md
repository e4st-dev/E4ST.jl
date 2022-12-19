Generator Table
===============
Table representing all existing generators to be modeled.

Note that the generator table does **not** contain Direct Air Capture, or Storage facilities.

```@docs
load_gen_table!
summarize_gen_table
```

#### Column Summary

```@example
using E4ST # hide
summarize_gen_table() # hide
```


## Optional Columns: 
| `cf_min` | `Float64` | decimal % | The minimum capacity factor, aka minimum electricity output % for a generator |
| `cf_max` | `Float64` | decimal % | The maximum capacity factor, aka maximum electricity output % for a generator |

