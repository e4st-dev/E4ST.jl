
""" 
    abstract type Crediting

Crediting is used to set the credit levels of generators for policies. It is primarily (possibly entirely) used for GenerationStandards (RPS, CES, carveouts, etc). 

## Setup inside config yaml
Crediting is specified in the yaml file. A type key must be specified, along with the approriate keys for the credit type you specified. Two examples are shown in the config below.
```yaml
$(read(joinpath(@__DIR__,"../../test/config/config_3bus_rps.yml"), String))
```

## Standard Crediting subtypes include:
*`CreditByBenchmark`
*`CreditByGentype`

## Interfaces Implements
*[`get_credit(c::Crediting, data, gen_row::DataFrameRow)`](@ref) - gets the appropriate credit level for the generator row for the given Crediting subtype.
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
    get_credit(c::Crediting, data, gen_row::DataFrame) -> 

Return the credit value for the given generator and crediting type. 
"""
function get_credit(c::Crediting, data, gen_row::DataFrame)
    error("No get_credit() defined for crediting type $(typeof(c)), no credits will be applied for this policy.")
end


"""
    struct CreditByGentype

Crediting method where credit levels are specified by gentypes. 
"""
@Base.kwdef struct CreditByGentype <: Crediting
    credits::OrderedDict
end
export CreditByGentype

"""
    get_credit(c::CreditByGentype, data, gen_row::DataFrameRow)

Returns the credit level specified for the gentype in c.credits. If no credit is specified for that gentype, it defaults to 0. 
"""
function get_credit(c::CreditByGentype, data,  gen_row::DataFrameRow)
    credit = get(c.credits, Symbol(gen_row.gentype), 0.0)
    return ByNothing(credit)
end

@Base.kwdef struct CreditByBenchmark <: Crediting
    gen_col::Symbol = :emis_co2
    benchmark::Float64
end
export CreditByBenchmark

"""
    get_credit(c::CreditByBenchmark, data, gen_row::DataFrameRow) -> 

Returns the credit level based on the formula `maximum([1.0 - (gen_emis_rate / c.benchmark), 0.0])`. 
"""
function get_credit(c::CreditByBenchmark, data, gen_row::DataFrameRow)
    gen_emis_rate = gen_row[c.gen_col]
    credit = maximum([1.0 - (gen_emis_rate / c.benchmark), 0.0]) 
    return ByNothing(credit)
end

