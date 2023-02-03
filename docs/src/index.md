# E4ST.jl

This is the Julia rewrite of the Engineering, Economic, and Environmental Electricity Simulation Tool (E4ST).  The MATLAB-based model built on top of MATPOWER can be found [here](https://github.com/e4st-dev/e4st-mp).

# Installation

## Install From the REPL (preferred)

In the Julia REPL, run the following command:

```julia
]
dev git@github.com:e4st-dev/E4ST.jl.git
```
This will clone E4ST into `<path to julia depot (usually ~/.julia)>/dev/E4ST`

```julia
using E4ST
```

## Install via Git Bash

If the REPL installation doesn't work (due to git credentials or something) you can always install via Git Bash.

First navigate to the .julia/dev folder (make the dev folder if it's not already there).  Then run:

```
git clone git@github.com:e4st-dev/E4ST.jl.git E4ST
```

Then, in a Julia REPL run (note that the bracket opens the package manager):
```
]
dev E4ST
```