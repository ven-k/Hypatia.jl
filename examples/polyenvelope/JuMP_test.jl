#=
Copyright (c) 2018-2022 Chris Coey, Lea Kapelevich, and contributors

This Julia package Hypatia.jl is released under the MIT license; see LICENSE
file in the root directory or at https://github.com/chriscoey/Hypatia.jl
=#

insts = OrderedDict()
insts["minimal"] = [((1, 2, 2, 2),)]
insts["fast"] = [
    ((2, 2, 3, 2),),
    ((3, 3, 3, 3),),
    ((3, 3, 5, 4),),
    ((5, 2, 5, 3),),
    ((1, 30, 2, 30),),
    ((10, 1, 3, 1),),
]
insts["various"] = [
    ((3, 3, 3, 3),),
    ((3, 3, 5, 4),),
    ((5, 2, 5, 3),),
    ((2, 30, 3, 30),),
    ((2, 15, 6, 15),),
    ((2, 30, 2, 40),),
    ((8, 3, 3, 3),),
]
return (PolyEnvelopeJuMP, insts)
