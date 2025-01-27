#=
Copyright (c) 2018-2022 Chris Coey, Lea Kapelevich, and contributors

This Julia package Hypatia.jl is released under the MIT license; see LICENSE
file in the root directory or at https://github.com/chriscoey/Hypatia.jl
=#

insts = OrderedDict()
insts["minimal"] = [
    ((5, 1, 2, true, true, true),),
    ((5, 1, 2, false, true, true),),
    ((5, 2, 1, false, true, true),),
    ((5, 1, 2, true, false, true), (default_tol_relax = 100,)),
    ((5, 1, 2, true, true, false),),
    ((:iris, 2, true, true, true),),
]
insts["fast"] = [
    ((50, 1, 4, true, true, true),),
    ((50, 1, 10, true, true, true),),
    ((50, 1, 50, true, true, true),),
    ((100, 1, 250, true, true, true),),
    ((50, 2, 2, true, true, true),),
    ((200, 2, 20, true, true, true),),
    ((50, 2, 2, false, true, true),),
    ((50, 2, 2, true, false, true),),
    ((50, 2, 2, true, true, false),),
    ((500, 3, 14, true, true, true),),
    ((20, 4, 3, false, true, false),),
    ((20, 4, 3, true, true, true),),
    ((100, 8, 2, true, true, true),),
    ((100, 8, 2, false, true, true),),
    ((100, 8, 2, true, false, true),),
    ((100, 8, 2, true, true, false),),
    ((250, 4, 6, true, true, true),),
    ((250, 4, 6, false, true, true),),
    ((250, 4, 6, true, false, true),),
    ((200, 32, 2, true, true, true),),
    ((:iris, 4, true, true, true),),
    ((:iris, 5, true, true, true),),
    ((:iris, 6, true, true, true),),
    ((:iris, 4, false, true, true),),
    ((:iris, 4, true, false, true),),
    ((:iris, 4, true, true, false),),
    ((:cancer, 4, true, true, true),),
    ((:cancer, 4, false, true, true),),
    ((:cancer, 4, true, false, true),),
]
return (DensityEstNative, insts)
