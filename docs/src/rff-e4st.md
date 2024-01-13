RFF-E4ST
========
Resources for the Future (RFF), the main organization responsible for developing and maintaining E4ST.jl, has a carefully curated a set of inputs and assumptions that we use in our analyses.  With the E4ST.jl writing process, we have tried to make our model straight-forward and easy to pick up and use for other modelers.  However, many of the inputs we use for our analyses are proprietary and require a license.  There are also custom Modifications that are still in development, or project-specific that we have chosen not to release in E4ST.jl.  If you are interested in using our inputs (possibly necessitating a licensing fee paid to the data providers), please contact Dan Shawhan at shawhan@rff.org.  This page provides an overview of the inputs and assumptions we use for our analyses.

```@contents
Pages = ["rff-e4st.md"]
```

# Grid

The model uses a representation of the U.S. electric grid reduced to roughly five thousand nodes and twenty thousand transmission segments. Power flow through the transmission segments is represented using standard linear approximation of the optimal power flow equations, known as a “DC linear approximation” ([Yang et al., 2017](https://ietresearch.onlinelibrary.wiley.com/doi/10.1049/iet-gtd.2017.1078)). These equations assume that the power flow through a transmission segment is a linear function of factors including the phase angle difference at the two ends of the segment.  The data used for our grid representation comes from data provider [Energy Visuals](https://www.energyvisuals.com/), and goes through a modified Ward Reduction ([Di Shi, 2012](https://core.ac.uk/download/pdf/79564835.pdf)).

# Load

The load is first distributed to each bus based on <TODO: add explanation here>.  Then hourly shape by region is applied from <TODO>.  Finally, we scale everything to match the annual load forecasted by the Annual Energy Outlook, or other sources depending on the project.

# Hours Representation

RFF-E4ST typically simulates the operation of the electricity system in a set of 52 representative hours of the year. These hours were carefully selected to mimic the frequency distributions of load, solar resource, and wind resource in the historical period 2008-2010, which is the only period for which detailed location-by-location, hour-by-hour wind, and solar data are available for both the U.S. and Canada. The representative hours are grouped into 16 representative days, which allows for the simulation of diurnal energy storage. Five of these days represent non-extreme conditions and are comprised of six evenly spaced representative hours. The remaining 11 days represent periods of potential extreme scarcity (high load, low sun, low wind, or a combination) in some parts of the U.S. and Canada and consist of only two hours (the most and least extreme hour in that day). These 11 extreme days are a carefully selected set that represents every kind of extreme scarcity condition in every NERC region of the U.S. and Canada. Using these representative periods with appropriate weights, E4ST is able to represent well the load and weather conditions expected in future years.

# Generators

## Existing Generation

The set of existing generators, their operational characteristics, grid connection points, and costs come from [S&P Global Market Intelligence Platform](https://www.spglobal.com/marketintelligence/en/campaigns/energy).  Existing wind and solar resource availablity is documented below.

## New Generation

Unless otherwise noted, all costs for generators come from the National Renewable Laboratory Annual Technology Baseline.

### Thermal generators

Thermal generators are allowed to be built at the sites of buses which are directly connected to existing or retired thermal generators.  This is because we assume that new thermal generators require certain infrastructure and natural resources which may be costly or uncommon outside of the existing locations.

### Solar



### Wind


## Storage

We assume that storage can be built at any bus.  Storage is assumed to be an 8-hour cycle (4 hours for charging, 4 hours for discharging) with 85% round-trip efficiency.  Each storage unit is constrained to have the same charge at the beginning and end of the day.

## Resource Values

## Carbon Sequestration Market
Coming Soon!

# Reserve Requirements

We use a representation for hourly capacity [reserve requirements](@ref ReserveRequirement) by balancing authority area such that the available generation and storage discharge capacity (see note below) in each hour is greater than or equal to the load for that hour plus a percent margin.  The percent margin comes from the assumptions computed for the [NREL ReEDS model](https://github.com/NREL/ReEDS-2.0/blob/main/inputs/reserves/prm_annual.csv).  The balancing authority areas are allowed to trade capacity credits with neighboring areas up to a trade limit calculated based on the load carrying capacity of the grid, given that the offering area still meets its own load with an N-1 contingency.

!!! note

    The available capacity for a given generator is equal to the nameplate capacity times of the generator times its availability factor at each hour.

# Policies
Coming Soon!
# Air Pollution Model
Coming Soon!