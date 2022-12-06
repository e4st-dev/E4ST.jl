# Hours Table

E4ST assumes that each year is broken up into a set of representative hours.  Each representative hour may have different parameters (i.e. load, availability factor, etc.) depending on the time of year, time of day, etc. Thus, we index many of the decision variables by representative hour.  For example, the variable for power generated (`pg`), is indexed by generator, year, and hour, meaning that for each generator, there is a different solved value of generation for each year in each representative hour.  The hours can contain any number of representative hours, but the number of hours spent at each representative hour (the `hours` column) must sum to 8760 (the number of hours in a year).  If it does not, E4ST will throw a warning and scale the hours so that they sum to 8760.

```@example
using E4ST # hide
summarize_hours_table()
```