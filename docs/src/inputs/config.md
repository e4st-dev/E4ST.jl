# Config File

The Config File is a file that fully specifies all the necessary information.  Note that when filenames are given as a relative path, they are assumed to be relative to the location of the config file.

## Required Fields:
* `out_path` - The path (relative or absolute) to the desired output folder.  This folder doesn't necessarily need to exist.  The code should make it for you if it doesn't exist yet.  If there are already results living in the output path, E4ST will back them up to a folder called `backup_yymmddhhmmss`
* `gen_file` - The filepath (relative or absolute) to the [generator table](gen.md).
* `bus_file` - The filepath (relative or absolute) to the [bus table](gen.md).
* `branch_file` - The filepath (relative or absolute) to the [branch table](gen.md).
* `hours_file` - The filepath (relative or absolute) to the [time representation](time.md).
* `years` - a list of years to run in the simulation specified as a string.  I.e. `"y2030"`
* `optimizer` - The optimizer type and attributes to use in solving the linear program.  The `type` field should be given, as well as each of the solver options you wish to set.  E4ST is a BYOS (Bring Your Own Solver :smile:) library, with default attributes for HiGHS and Gurobi.  For all other solvers, you're on your own to provide a reasonable set of attributes.  To see a full list of solvers with work with JuMP.jl, see [here](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers).
* `mods` - A list of `Modification`s specifying changes for how E4ST runs.  See the [modifications page](../types/mods.md) for information on what they are, how to add them to a config file.

## Optional Fields:
* `af_file` - The filepath (relative or absolute) to the [availability factor table](af.md).



## Example Config File

```yaml
out_path:    "../out/case_dac1"
gen_file:    "../matlab/t_case_e4st_dac1/gen.csv"
bus_file:    "../matlab/t_case_e4st_dac1/bus.csv"
branch_file: "../matlab/t_case_e4st_dac1/branch.csv"
optimizer:
  type: "HiGHS"
  dual_feasibility_tolerance: 1e-5
mods:
  example_policy:
    type: "ExamplePolicyType"
    value: 0
    some_parameter:
      - "This makes an "
      - "array of strings."
      - "Cool, right?"
    other_parameter:
      name: "This makes an OrderedDict"
  other_mod:
    type: "OtherModificationType"
    value: 0
    custom_parameter: "hello!!!"
```