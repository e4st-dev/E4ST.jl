Reserve Requirements
=========

```@docs
ReserveRequirement
```

** Expressions for Reserve Requirement **

The reserve requirement mod includes an input file that indicates how much reserves each region (e.g. baa, state, nerc) needs by year. Simply, the modification sets up a constraint that says the amount of reservers avaialble in each region, year, and hour combination must be greater than what is specified by the the reserve margin.

To set up this equation, we use the reserve margin to calculate how much power needs to be available. First, mind the maximum hourly load at each bus. 

$$
\[
\text{MaxLoad}_{b,y} = \max_{h} \text{Load}_{b,y,h}
\]
$$

In every bus, year, hour, the reserve requirement (ResReq) is equal to the nominal load at the bus in that year, hour plus the maximum load multiplied by the reserve margin:

$$
\text{ResReq}_{b,y,h} = \text{Load}_{b,y,h} + \text{MaxLoad}_{b,y} \times \text{ReserveMargin}_{r}
$$

Then, we find the reserve requirement for each region in every year, hour combination by summing the reserve requirement across all the busses in the region:

$$
\text{ResReq}_{r,y,h} = \sum_{b \in b_r} \text{ResReq}_{b,y,h}
$$

Next, we find the available power. At each bus, the reserve power for a year, hour is the sum of the capacity of all associated generators multipled by each generators crediting in that year, hour. For reserve requirements, the crediting is equivalent to the availability factor in that hour. 

$$
\text{Res}_{b,y,h} = \sum_{g \in g_b} \text{PCap}_{g,y} \times \text{Credit}_{g,y,h}
$$

Additionally, there is an option to allow the reserve requirement to be met with imports from neighboring regions.If that is allowed, the net imports are added to the reserve power equation.

$$
\[
\text{Res}_{r,y,h} =
\sum_{b \in b_r} \text{Res}_{b,y,h}
+ 
\sum_{b \in b_r} \text{NetImports}_{b,y,h}
\]
$$

Then, the available reserve power across each busses in a region is summed to find the regions available reserve power.

$$
\text{Res}_{r,y,h} = \sum_{b \in b_r} \text{Res}_{b,y,h}
$$


** Reserve Requirement Constraint **
The reserve requirement consraint requires that the available reserve power for each region, year, and hour is greater than the calculation reserve requirement.

$$
\text{Res}_{r,y,h} \ge \text{ResReq}_{r,y,h}
$$