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
ITCStorage
modify_setup_data!(pol::ITCStorage, config, data)
modify_model!(pol::ITCStorage, config, data, model)
```

## PTC
```@docs
PTC
modify_setup_data!(pol::PTC, config, data)
modify_model!(pol::PTC, config, data, model)
```

**Derivation of the PTC capex adjustment**
First, find the adjusted PTC value $x$ if it were a constant cash flow over entire econ lifetime $l$. \
Start by setting the NPV of the actual PTC (per MW capacity) $p$ and the adjusted PTC (per MW capacity) $x$. \
$m$ is the minimum age of the generator to qualify for the PTC. This will be 0 if they generator can recieve the PTC from the start of its life. This is why we use m+1 in the following formula. \
$n$ is the maximum age of the generator to qualify for the PTC \
We adjust this calculation to account for the fact that the simulation represents half way through the year. This means adding 0.5 to the year values to adjust the NPV for half way through the year.

$$\sum_{i=1}^l x / \left(1+r \right)^{i+0.5} = \sum_{j=m+1}^n p / \left(1+r \right)^{j+0.5}$$

$$ x \left( \frac{1- \left(\frac{1}{1+r}\right)^{l+0.5}}{1 - \left(\frac{1}{1+r}\right)^{1.5}}\right) = p \left( \frac{1- \left(\frac{1}{1+r}\right)^{n+0.5}}{1 - \left(\frac{1}{1+r}\right)^{m+1.5}}\right) $$

$$ x = p \frac{\left(1- \left(\frac{1}{1+r}\right)^{n+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{1.5}\right)}{\left(1- \left(\frac{1}{1+r}\right)^{l+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{m+1.5}\right)} $$

To get the adjustement to capex $capex\_ adj$ we can start with  

$$ capex + capex\_ adj + p = capex + x $$ 
so 
$$ capex\_ adj = p - x $$

$$ capex\_ adj = p \left(1 - \left(\frac{\left(1- \left(\frac{1}{1+r}\right)^{n+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{1.5}\right)}{\left(1- \left(\frac{1}{1+r}\right)^{l+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{m+1.5}\right)}\right)\right) $$

The value of the PTC per MW capacity $p$ is equal to the PTC in per MWh terms $PTC$ * capacity factor $cf$. We can substitute this in to get the final formula

$$ capex\_ adjust = PTC*cf\left(1 - \left(\frac{\left(1- \left(\frac{1}{1+r}\right)^{n+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{1.5}\right)}{\left(1- \left(\frac{1}{1+r}\right)^{l+0.5}\right)\left(1 - \left(\frac{1}{1+r}\right)^{m+1.5}\right)}\right)\right) $$


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
AvailabilityFactorCrediting
StandardStorageReserveCrediting
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
