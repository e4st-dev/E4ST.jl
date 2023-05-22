Results Formulas
================
E4ST.jl produces a lot of data to comb through.  There are often some complex calculations for welfare that we may want to compute in different ways over different regions without necessarily storing every possible combination of every calculation.  The goal of the results formula is to give E4ST a way to calculate different results so that they can be calculated quickly on demand rather than always be calculated for every run.  It also provides a way to specify custom result calculations that might not be standard to E4ST.

```@docs
add_results_formula!
get_results_formulas
get_results_formula
compute_result
ResultsFormula
Base.sum(data, table::DataFrame, col1::Symbol, idxs, yr_idxs, hr_idxs)
sum_yearly
sum_hourly
min_hourly
average_yearly
```