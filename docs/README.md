E4ST Documentation
==================
Currently, since E4ST.jl is a private repository, the documentation is not hosted publicly.  That being said, `Documenter.jl` can still produce a local version of the documentation that is useful for viewing and exploring.  The local version can be created by:
```julia
cd("docs") # from with the E4ST folder
include("make.jl")
```

The above will create a `docs/build` folder, in which you can find `docs/build/index.html`.  Open that from file explorer and it should open in your default web browser for you to peruse at your leisure.

## Preparing Documentation For Release

* There are 2 TODO's in the `make.jl` file - follow those instructions, but hopefully in a way that `make.jl` still works for local only (i.e. somehow checking if we are inside of Github CI)
* Add a Documenter.jl workflow within `.github/workflows`.