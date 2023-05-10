Policy
======

```@docs
Policy
```

# Tax Credits 

## ITC
```@docs
ITC
modify_setup_data!(pol::ITC, config, data)
modify_model!(pol::ITC, config, data, model)

HydFuelITC
modify_setup_data!(pol::HydFuelITC, config, data)
modify_model!(pol::HydFuelITC, config, data, model)
```

## PTC
```@docs
PTC
modify_setup_data!(pol::PTC, config, data)
modify_model!(pol::PTC, config, data, model)
```

# GenerationStandard
GenerationStandard is a type used for policies that give some generators certain credits and constrain generation to a certain target. The primary examples are CESs, RPSs, and state carveouts. 
```@docs
GenerationStandard
modify_setup_data!(pol::GenerationStandard, config, data)
modify_model!(pol::GenerationStandard, config, data, model)
```

## Crediting
```@docs
Crediting
get_credit
StandardRPSCrediting
CreditByGentype
CreditByBenchmark
```

## CES
CES is an alias for GenerationStandard. Modifying functions called on a CES will use the GenerationStandard method. 
```@docs
CES
```

## RPS 
RPS is an alias for GenerationStandard. Modifying functions called on an RPS will use the GenerationStandard method.
```@docs
RPS
```

# GenerationConstraint
GenerationConstraint is a type used for constraining generation from some generators to a certain max or min amount. The max and min can also be defined in terms of another column in the gen table such as emissions. A GenerationConstraint is defined when creating an EmissionCap but can be used for more general modifications beyond policies as well. 
```@docs
GenerationConstraint
modify_model!(cons::GenerationConstraint, config, data, model)
```

## EmissionCap
```@docs
EmissionCap
modify_model!(pol::EmissionCap, config, data, model)
```

## EmissionPrice
```@docs
EmissionPrice
modify_model!(pol::EmissionPrice, config, data, model)
```
