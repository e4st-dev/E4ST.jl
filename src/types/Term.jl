"""
    abstract type Term

Abstract type Term is used to add variables (terms) to the objective function or other functions. Subtypes include PerMWhGen, PerMWCap, and PerMWhCurtailed. 
"""        
abstract type Term end

struct PerMWhGen <: Term end
struct PerMWCap <: Term end
struct PerMWhCurtailed <: Term end
