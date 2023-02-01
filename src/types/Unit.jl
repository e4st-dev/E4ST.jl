"""
    abstract type E4ST.Unit

Represents possible units for table columns in E4ST.
"""
abstract type Unit end

export Unit

function (Type{<:Unit})(s::AbstractString)
    get_type(s)
end

function Unit(s::AbstractString)
    get_type(s)()
end

struct DollarsPerMWhServed <: Unit end; export DollarsPerMWhServed
struct Dollars <: Unit end; export Dollars
struct ShortTonsPerMWhGenerated <: Unit end; export ShortTonsPerMWhGenerated
struct DollarsPerMWCapacity <: Unit end; export DollarsPerMWCapacity
struct DollarsPerMWBuiltCapacity <: Unit end; export DollarsPerMWBuiltCapacity
struct DollarsPerMWhGenerated <: Unit end; export DollarsPerMWhGenerated
struct MWhGeneratedPerMWhCapacity <: Unit end; export MWhGeneratedPerMWhCapacity
struct NA <: Unit end; export NA
struct PU <: Unit end; export PU
struct MWFlow <: Unit end; export MWFlow
struct MWCapacity <: Unit end; export MWCapacity
struct MWDemanded <: Unit end; export MWDemanded

struct MWhDemanded <: Unit end; export MWhDemanded

struct Hours <: Unit end; export Hours
struct Year <: Unit end; export Year
struct Ratio <: Unit end; export Ratio # For general purpose ratios that don't need a fancy Unit
