#=
Copyright (c) 2018-2022 Chris Coey, Lea Kapelevich, and contributors

This Julia package Hypatia.jl is released under the MIT license; see LICENSE
file in the root directory or at https://github.com/chriscoey/Hypatia.jl
=#

insts = OrderedDict()
insts["minimal"] = [((1, 2, 2, 2, true),), ((1, 2, 2, 2, false),)]
insts["fast"] = [
    ((2, 2, 3, 2, true),),
    ((2, 2, 3, 2, false),),
    ((3, 3, 3, 3, true),),
    ((3, 3, 3, 3, false),),
    ((3, 3, 5, 4, true),),
    ((5, 2, 5, 3, true),),
    ((1, 30, 2, 30, true),),
    ((1, 30, 2, 30, false),),
    ((10, 1, 3, 1, true),),
    ((10, 1, 3, 1, false),),
]
return (PolyEnvelopeNative, insts)
