Branch Table
============
Table representing all existing branches (AC transmission lines) to be modeled.  See also [`DCLine`](@ref)

Note that the Branch Table does not contain DC transmission lines.

```@docs
setup_table!(config, data, ::Val{:branch})
summarize_table(::Val{:branch})
```

#### Column Summary

```@example
using E4ST # hide
summarize_table(:branch) # hide
```