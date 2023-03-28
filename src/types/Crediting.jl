
""" 
    abstract type Crediting

Crediting is used to set the credit levels of generators for policies. It is primarily (possibly entirely) used for GenerationStandards (RPS, CES, carveouts, etc). 

## Setup inside config yaml
```yaml
mod:
    name: ...
    ...
    crediting:
        type: CreditType
        type_field: field_value
```

## Standard Crediting subtypes include:
*`CreditByBenchmark`
*`CreditByGentype`

## Interfaces Implements
*[`get_credit(c::Crediting, gen_row::DataFrameRow)`](@ref) - gets the appropriate credit level for the generator row for the given Crediting subtype.
"""
abstract type Crediting end 

"""
    Crediting(p::Pair) -> mod

Constructs a Crediting structure from `p`, a `Pair` of `name=>d`.  The Crediting structure is of type `d[:type]` with keyword arguments for all the other key value pairs in `d`.
"""
function Crediting(p::Pair)
    name, d = p
    T = get_type(d[:type])
    if hasfield(T, :name)
        mod = _discard_type(T; name, d...)
    else
        mod = _discard_type(T; d...)
    end
    return mod
end


"""
    struct CreditByGentype

Crediting method where credit levels are specified by gentypes. 
"""
struct CreditByGentype
    credits::OrderedDict{AbstractString, Float64} #flagging that this might cause some errors if config read in as symbol
end

"""
    get_credit(c::CreditByGentype, gen_row::DataFrameRow) -> Float64

Returns the credit level specified for the gentype in c.credits. If no credit is specified for that gentype, it defaults to 0. 
"""
function get_credit(c::CreditByGentype, gen_row::DataFrameRow)
    haskey(c.credits, gen_row.gentype) ? credit =  c.credits[gen_row.gentype] : credit = 0.0
    return Float64(credit)
end

struct CreditByBenchmark
    gen_col::Symbol
    benchmark::Float64

    function CreditByBenchmark(;benchmark)
        gen_col = :emis_co2
        return CreditByBenchmark(gen_col, benchmark)
    end
end

"""
    get_credit(c::CreditByBenchmark, gen_row::DataFrameRow) -> 

Returns the credit level based on the formula `maximum([1.0 - (gen_emis_rate / c.benchmark), 0.0])`. 
"""
function get_credit(c::CreditByBenchmark, gen_row::DataFrameRow)
    gen_emis_rate = gen_row[c.gen_col]
    credit = maximum([1.0 - (gen_emis_rate / c.benchmark), 0.0]) 
    return credit
end

#TODO: define general method for get_credit that just errors/warms that no method for that type has been defined yet