DC OPF Setup
=============

The E4ST.jl DC OPF is set up as a cost minimization problem. Costs are added to the objective function and benefits are subtracted. setup_dcopf!() adds VOM, Fuel Cost, FOM, Capex, and Curtialment Cost to the objective function. Other terms can be added to the objective in Modifications before the model is optimized. A dictionary of the terms added to the objective function can be found in data[:obj_vars]. 

Constraints and expressions can also be defined outside of setup_dcopf!() before the model is optimized. This will also be done in Modifications. 

```@docs
setup_dcopf!
```
### Get Model Variable Function
These functions get or use model variables. To get the value after optimizing the model they must be wrapped in value.(). 
```@docs
get_pgen_bus
get_pflow_bus
get_pflow_branch
```
### Constriant/Expression Info Function
These functions are used in defining the model constraints. 
```@docs
get_pgen_min
get_pgen_max
get_egen_gen
```

### Model Mutation Functions
These functions are used to modify the model, specifically creating and adding terms to the objective expression. The Term abstract type is used to determine how the term (cost or benefit) should be added to the objective function.

```@docs
Term
PerMWhGen
PerMWCap
PerMWhCurtailed
add_obj_term!
add_obj_exp!
```