
""" 
    abstract type Crediting

Crediting is used to set the credit levels of generators for policies. It is primarily used for [`GenerationStandard`](@ref)s and [`ReserveRequirement`](@ref)s (RPS, CES, carveouts, etc). 

## Setup inside config yaml
Crediting is specified in the yaml file. A type key must be specified, along with the approriate keys for the credit type you specified. Two examples are shown in the config below.

```yaml
$(read(joinpath(@__DIR__,"../../test/config/config_3bus_rps.yml"), String))
```

## Standard Crediting subtypes include:
* [`CreditByBenchmark`](@ref)
* [`CreditByGentype`](@ref)

## Interfaces Implements
* [`get_credit(c::Crediting, data, gen_row::DataFrameRow)`](@ref) - gets the appropriate credit level for the generator row for the given Crediting subtype.
"""
abstract type Crediting end 

"""
    Crediting(d::OrderedDict) -> crediting

Constructs a Crediting structure from `d`, an OrderedDict read in from the config file inside of a mod.  The Crediting structure is of type `d[:type]` with keyword arguments for all the other key value pairs in `d`.
"""
function Crediting(d::OrderedDict)
    T = get_type(d[:type])
    crediting = _discard_type(T; d...)
    return crediting
end
function Crediting(c::Crediting)
    c
end
export Crediting

"""
    fieldnames_for_yaml(::Type{C}) where {C<:Crediting}

returns the fieldnames in a yaml, used for printing, modified for different types of crediting 
"""
function fieldnames_for_yaml(::Type{C}) where {C<:Crediting}
    return setdiff(fieldnames(C), (:name,))
end
export fieldnames_for_yaml

"""
    function YAML._print(io::IO, c::C, level::Int=0, ignore_level::Bool=false) where {C<:Crediting}

Prints the field determined in fieldnames_for_yaml from the Crediting. 
"""
function YAML._print(io::IO, c::C, level::Int=0, ignore_level::Bool=false) where {C<:Crediting}
    println(io)
    cdict = OrderedDict(:type => string(typeof(c)), (k=>getproperty(c, k) for k in fieldnames_for_yaml(C))...)
    YAML._print(io::IO, cdict, level, ignore_level)
end

"""
    get_credit(c::Crediting, data, gen_row::DataFrame) -> 

Return the credit value for the given generator and crediting type. 
"""
function get_credit(c::Crediting, data, gen_row::DataFrame)
    error("No get_credit() defined for crediting type $(typeof(c)), no credits will be applied for this policy.")
end
export get_credit


"""
    CreditByGentype(;credits::OrderedDict{String, Float64})

Crediting method where credit levels are specified by gentypes. 
"""
struct CreditByGentype <: Crediting
    credits::OrderedDict{String,Float64}

    function CreditByGentype(credits)
        if !(credits isa OrderedDict{String, Float64})
            credits = OrderedDict{String, Float64}(string(k)=>v for (k,v) in credits)
        end
        return new(credits)
    end
end

CreditByGentype(;credits) = CreditByGentype(credits)
export CreditByGentype

"""
    get_credit(c::CreditByGentype, data, gen_row::DataFrameRow)

Returns the credit level specified for the gentype in c.credits. If no credit is specified for that gentype, it defaults to 0. 
"""
function get_credit(c::CreditByGentype, data,  gen_row::DataFrameRow)
    credit = get(c.credits, gen_row.gentype, 0.0)
    return ByNothing(credit)
end

"""
    CreditByBenchmark(;gen_col, benchmark)

Awards credit of each generator based on how that generator's `gen_col` compares to `benchmark`, using the following formula.

    max(1.0 - (gen_row[gen_col] / benchmark), 0.0)

* `gen_col::Symbol` - the column of the `gen` table to compare against
* `benchmark::Float64` - the benchmark rate to compare with, in the same units as the `gen_col`.
"""
struct CreditByBenchmark <: Crediting
    gen_col::Symbol
    benchmark::Float64

    function CreditByBenchmark(gen_col, benchmark)
        return new(Symbol(gen_col), Float64(benchmark))
    end
end
export CreditByBenchmark

CreditByBenchmark(;gen_col = :emis_co2e, benchmark) = CreditByBenchmark(gen_col, benchmark)


"""
    get_credit(c::CreditByBenchmark, data, gen_row::DataFrameRow) -> 

Returns the credit level based on the formula `max(1.0 - (gen_row[gen_col] / c.benchmark), 0.0)`. 
"""
function get_credit(c::CreditByBenchmark, data, gen_row::DataFrameRow)
    gen_emis_rate = gen_row[c.gen_col]
    credit = min.(1.0, max.( 1.0 .- gen_emis_rate ./ c.benchmark, 0.0))
    return credit
end

"""
    UnitCredit <: Crediting

Always gives credit value of 1.0
"""
struct UnitCredit <: Crediting end
export UnitCredit

function get_credit(::UnitCredit, data, gen_row)
    return 1.0
end


"""
    AvailabilityFactorCrediting <: Crediting

Returns the availability factor of the generator.
"""
struct AvailabilityFactorCrediting <: Crediting end
export AvailabilityFactorCrediting

function get_credit(::AvailabilityFactorCrediting, data, gen_row)
    return gen_row.af
end


"""
    struct StandardStorageReserveCrediting <: Crediting

Awards crediting to storage facilities based on their discharge duration and capacity.  The values were retrieved from NYISO at the following website, page 31:

[`https://www.nyiso.com/documents/20142/23590734/20210805%20NYISO%20-%20Capacity%20Accreditation%20Current%20Rules%20Final.pdf`](https://www.nyiso.com/documents/20142/23590734/20210805%20NYISO%20-%20Capacity%20Accreditation%20Current%20Rules%20Final.pdf)
"""
struct StandardStorageReserveCrediting <: Crediting
    itp1::LinearInterpolator{Float64, NoBoundaries}
    itp2::LinearInterpolator{Float64, NoBoundaries}
    function StandardStorageReserveCrediting()
        itp1 = LinearInterpolator([2., 4., 6., 8.], [0.45,  0.90, 1.00, 1.00], NoBoundaries())
        itp2 = LinearInterpolator([2., 4., 6., 8.], [0.375, 0.75, 0.90, 1.00], NoBoundaries())
        return new(itp1, itp2)
    end
end
export StandardStorageReserveCrediting

fieldnames_for_yaml(::Type{StandardStorageReserveCrediting}) = ()

function get_credit(c::StandardStorageReserveCrediting, data, stor_row)
    itp = c.itp1 # TODO: decide which interpolator to use and when.
    duration = stor_row.duration_discharge::Float64
    return max(0.0, min(1.0, itp(duration)))
end