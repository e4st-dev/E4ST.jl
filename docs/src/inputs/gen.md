Generator Table
===============
Table representing all existing generators to be modeled.

Note that the generator table does **not** contain Direct Air Capture, or Storage facilities.

```@docs
summarize_table(::Val{:gen})
```

#### Column Summary

```@example gen
using E4ST # hide
summarize_table(:gen) # hide
```

## Buildable Generator Specifications

```@docs
summarize_table(::Val{:build_gen})
```

#### Column Summary
```@example gen
summarize_table(:build_gen) # hide
``` 