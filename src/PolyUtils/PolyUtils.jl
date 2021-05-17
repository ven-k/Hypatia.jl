#=
utilities for constructing polynomial sum-of-squares models
=#

module PolyUtils

using LinearAlgebra
import Combinatorics
import SpecialFunctions: gamma_inc
include("realdomains.jl")
include("realinterp.jl")
include("complex.jl")

end