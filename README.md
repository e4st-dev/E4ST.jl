# E4ST.jl

![GitHub contributors](https://img.shields.io/github/contributors/e4st-dev/E4ST.jl?logo=GitHub)
![GitHub last commit](https://img.shields.io/github/last-commit/e4st-dev/E4ST.jl/main?logo=GitHub)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![CI](https://github.com/e4st-dev/E4ST.jl/workflows/CI/badge.svg)](https://github.com/e4st-dev/E4ST.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/e4st-dev/E4ST.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/e4st-dev/E4ST.jl)

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

## Connection Refused Error
If you are trying to clone from an RFF computer, you may need to do a [small fix](https://gist.github.com/Tamal/1cc77f88ef3e900aeae65f0e5e504794).
Make a file: `touch ~/.ssh/config`, insert the following:
```
Host github.com
  Hostname ssh.github.com
  Port 443
```

