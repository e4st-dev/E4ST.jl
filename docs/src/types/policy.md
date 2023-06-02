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
```

## PTC
```@docs
PTC
modify_setup_data!(pol::PTC, config, data)
modify_model!(pol::PTC, config, data, model)
```

**Derivation of the PTC capex adjustment**
First, find the adjusted PTC value $x if it were a constant cash flow over entire econ lifetime $e. 
Start by setting the NPV of the actual PTC (per MW capacity) $p and the adjusted PTC (per MW capacity) $x
$m is the minimum age of the generator to qualify for the PTC
$n is the maximum age of the generator to qualify for the PTC

$$\sum_{i=1}^e x / \left(1+r \right)^i = \sum_{i=m}^n p / \left(1+r \right)^i$$

#TODO: finish this, based on the proof in the PTC_Crediting_Structure spreadsheet, but instead of the right hand side going from  1 to n it goes from gen_age_min to gen_age_max


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
