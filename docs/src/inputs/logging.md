Logging
=======
In general, E4ST piggy-backs off of the [Logging.jl](https://docs.julialang.org/en/v1/stdlib/Logging/) interface.  To make a log statement, simply write:
```julia
@info "Something informative"
@warn "Some sort of warning"
@debug "Debugging information, not printed unless config[:logging] == \"debug\""
```

### Documentation

```@docs
start_logging!(config)
stop_logging!(config)
log_header(s)
log_start
header_string
time_string
date_string
```