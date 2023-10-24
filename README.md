# E4ST.jl

![GitHub contributors](https://img.shields.io/github/contributors/e4st-dev/E4ST.jl?logo=GitHub)
![GitHub last commit](https://img.shields.io/github/last-commit/e4st-dev/E4ST.jl/main?logo=GitHub)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![CI](https://github.com/e4st-dev/E4ST.jl/workflows/CI/badge.svg)](https://github.com/e4st-dev/E4ST.jl/actions?query=workflow%3ACI)
[![Code Coverage](https://codecov.io/gh/e4st-dev/E4ST.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/e4st-dev/E4ST.jl)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://e4st-dev.github.io/E4ST.jl/stable/)
[![In Development](https://img.shields.io/badge/docs-dev-blue.svg)](https://e4st-dev.github.io/E4ST.jl/dev/)

This is the Julia rewrite of the Engineering, Economic, and Environmental Electricity Simulation Tool (E4ST), [originally written in MATLAB](https://github.com/e4st-dev/e4st-mp), based on top of MATPOWER.  The idea for E4ST was developed in a joint effort at Cornell University and Resources for the Future by Daniel Shawhan and Ray Zimmerman, with major contributions from Biao Mao, Paul Picciano, Christoph Funke, Steven Whitkin, Ethan Russell, and Sally Robson.

At the heart of E4ST is a detailed engineering representation of the power grid, and an optimization problem that represents the decisions of the system operators, electricity end-users, generators, and generation developers. The model represents these operation, consumption, investment, and retirement decisions by minimizing the sum of generator variable costs, fixed costs, investment costs, and end-user consumer surplus losses. E4ST provides detailed analysis to better inform policymakers, investors, and stakeholders.
The power sector is increasingly complex, with challenging emission reduction aspirations, new energy technologies, an ever-changing policy backdrop, growing demand, and much uncertainty. Some of the challenges of representing the sector include:
* Regional and national markets for clean electricity credits
* Diverse generation mixes with temporal variations
* Markets for various fuel types and captured CO2
* Increasing energy storage requirements

To provide relevant analysis for such a complex and dynamic sector, models must to be fast to adapt and use. The previous version of E4ST was written as a wrapper for MATPOWER, a powerful Matlab-language package for solving steady-state power system simulation and optimization problems. However, as powerful as MATPOWER is, we desired the additional flexibility and speed that Julia can provide.

E4ST.jl was written with maximum flexibility and speed in mind. E4ST.jl is a bring-your-own-solver JuMP-based package. We leverage clever interfaces to inject custom modifications into the data loading, model setup, and results processing steps to allow for extreme configurability and extensibility. We allow for flexible time representations and time-varying inputs with space-and-time-efficient data retrieval.

E4ST.jl uses the speed and extensibility of Julia to enable faster deployment of detailed and adaptable models to inform policy decision-makers and technology developers.

> **Warning**
> As with most models, quality of analysis using E4ST.jl is heavily dependent on the inputs and assumptions.  For this reason, the E4ST team at RFF does not implicitly endorse all analysis done using E4ST.jl. If you have questions about the model inputs and assumptions used for our work at RFF, please contact us.

# Citation
If you use E4ST.jl in your work, we request that you cite the [following paper](https://www.sciencedirect.com/science/article/abs/pii/S0928765513000900): 

```
@article{Shawhan2014,
    author = {Daniel Shawhan, John T. Taber, Di Shi, Ray D. Zimmerman, Jubo Yan, Charles M. Marquet, Yingying Qi, Biao Mao, Richard E. Schuler, William Schulze, D.J. Tylavsky},
    title = {{D}oes a {D}etailed {M}odel of the {E}lectricity {G}rid {M}atter? {E}stimating the {I}mpacts of the {R}egional {G}reenhouse {G}as {I}nitiative},
    journal = {Resource and Energy Economics},
    year = {2014},
    doi = {10.1016/j.reseneeco.2013.11.015}}
```

Alternatively, you can cite the [following paper](https://www.sciencedirect.com/science/article/abs/pii/S0301421518304865): 

```
@article{Shawhan2014,
    author = {Daniel Shawhan, Paul D. Picciano},
    title = {{C}osts and benefits of saving unprofitable generators: {A} simulation case study for {US} coal and nuclear power plants},
    journal = {Energy Policy},
    year = {2019},
    doi = {https://doi.org/10.1016/j.enpol.2018.07.040}}
```
# Installation

In the Julia REPL, run the following command:

```julia
using Pkg
Pkg.add("E4ST") # Or Pkg.develop("E4ST")
```