Post Processing
===============

Often, it is necessary to perform post-processing and combine the results from multiple simulations into one.  `e4st_post` attempts to do that in a streamlined way, only deserializing `data` a single time for each of the runs, and only storing one full `data` dictionary in memory at a time.

```@docs
e4st_post
read_post_config
summarize_post_config
extract_results
combine_results
join_sim_tables
```