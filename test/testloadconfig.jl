Base.@kwdef struct ExamplePolicyType <: Policy
    value::Float64 = 1.0    # defaults to 1.0
    some_parameter::Vector  # no default, so it must be specified, can be a Vector of any kind
    other_parameter         # no default, and no type specification
end

Base.@kwdef struct OtherModificationType <: Modification
    value::Float64 = 1.0    # defaults to 1.0
    custom_parameter        # no default, and no type specification
end

filename = joinpath(@__DIR__, "cases/case_dac1.yml")

@test load_config(filename) isa AbstractDict
config = load_config(filename)

@test isabspath(config[:out_path])
@test isabspath(config[:gen_file])
@test isabspath(config[:bus_file])
@test isabspath(config[:branch_file])

@test config[:mods] isa Vector{<:Modification}