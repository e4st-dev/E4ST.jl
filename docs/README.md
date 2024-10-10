E4ST Documentation
==================
The E4ST.jl documentation is hosted at [this site](https://e4st-dev.github.io/E4ST.jl/dev/), and is produced with `Documenter.jl`.  This folder contains Markdown documents used for building the website.

If you would like to build a local version, it can be created by:

```julia
cd("docs") # from with the E4ST folder
include("make.jl") # You may need to comment out the `deploy_docs` function call
```

The above will create a `docs/build` folder, in which you can find `docs/build/index.html`.  Open that from file explorer and it should open in your default web browser for you to peruse at your leisure.