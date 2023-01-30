"""
    abstract type E4ST.Unit

Represents possible units for table columns in E4ST.
"""
abstract type Unit end

function Unit(s::String)
    get_type(s)
end

struct DollarsPerMWhServed <: Unit end
struct Dollars <: Unit end
struct ShortTonsPerMWhGenerated <: Unit end
struct DollarsPerMWCapacity <: Unit end
struct DollarsPerMWBuiltCapacity <: Unit end
struct DollarsPerMWhGenerated <: Unit end
struct MWhGeneratedPerMWhCapacity <: Unit end
struct NA <: Unit end
struct PU <: Unit end
struct MWFlow <: Unit end
struct MWCapacity <: Unit end
struct MWDemanded <: Unit end

struct MWhDemanded <: Unit end

struct Hours <: Unit end
struct Year <: Unit end
struct Ratio <: Unit end # For general purpose ratios that don't need a fancy Unit
