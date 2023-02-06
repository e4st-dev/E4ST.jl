Generator Table
===============
Table representing all existing generators to be modeled.

Note that the generator table does **not** contain Direct Air Capture, or Storage facilities.

```@docs
summarize_table(::Val{:gen})
```

#### Column Summary

```@example
using E4ST # hide
summarize_table(:gen) # hide
```