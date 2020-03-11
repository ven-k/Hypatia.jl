#=
Copyright 2019, Chris Coey and contributors

run examples tests from the examples folder and display basic benchmarks

TODO when linear operators are working, update linear operators tests in native tests add tests here
=#

using Test
using DataFrames
using Printf
using TimerOutputs
import Hypatia
import Hypatia.Solvers

# options to solvers
T = Float64
timer = TimerOutput()
partial_solver_options = (
    verbose = false,
    iter_limit = 250,
    system_solver = Solvers.QRCholDenseSystemSolver{T}(),
    timer = timer,
    )
native_options(; other_solver_options...) = (
    atol = 10eps(T)^0.25,
    solver = Solvers.Solver{T}(; partial_solver_options..., other_solver_options...),
    )
JuMP_options(; other_solver_options...) = (
    use_dense_model = true,
    test_certificates = false,
    partial_solver_options..., other_solver_options...
    )

# prefixes of instance sets to run and corresponding time limits (seconds)
instance_sets = Dict(
    "fast" => 15,
    # "slow" => 120,
    )

# list of names of native examples to run
native_example_names = [
    "densityest",
    "envelope",
    "expdesign",
    "linearopt",
    "matrixcompletion",
    "matrixregression",
    "maxvolume",
    "polymin",
    "portfolio",
    "sparsepca",
    ]

# list of names of JuMP examples to run
JuMP_example_names = [
    "centralpolymat",
    "conditionnum",
    "contraction",
    "densityest",
    "envelope",
    "expdesign",
    "lotkavolterra",
    "lyapunovstability",
    "matrixcompletion",
    "matrixquadratic",
    "matrixregression",
    "maxvolume",
    "muconvexity",
    "nearestpsd",
    "polymin",
    "polynorm",
    "portfolio",
    "regionofattr",
    "robustgeomprog",
    "secondorderpoly",
    "semidefinitepoly",
    "shapeconregr",
    "signomialmin",
    ]

# types of models to run and corresponding options and example names
model_types = Dict(
    "native" => (native_options, native_example_names),
    "JuMP" => (JuMP_options, JuMP_example_names),
    )

# start the tests
@info("starting examples tests")
for (key, val) in instance_sets
    @info("each $key instance should take <$val seconds")
end

examples_dir = joinpath(@__DIR__, "../examples")
for mod_type in keys(model_types), ex in eval(Symbol(mod_type, "_example_names"))
    include(joinpath(examples_dir, ex, mod_type * ".jl"))
end

perf = DataFrame(
    model = String[],
    example = String[],
    inst = Int[],
    inst_data = String[],
    test_time = Float64[],
    solve_time = Float64[],
    iters = Int[],
    status = Symbol[],
    prim_obj = T[],
    dual_obj = T[],
    )

all_tests_time = time()

@testset "examples tests" begin
    for (mod_type, (options_func, example_names)) in model_types
        println("\nstarting $(length(example_names)) examples for $mod_type")
        for ex_name in example_names, (inst_set, time_limit) in instance_sets
            options = options_func(time_limit = time_limit)
            instances = eval(Symbol(ex_name, "_", mod_type, "_", inst_set))
            println("\nstarting $(length(instances)) instances for $mod_type $ex_name $inst_set\n")
            test_function = eval(Symbol("test_", ex_name, "_", mod_type))
            for (inst_num, inst_data) in enumerate(instances)
                test_info = "$mod_type $ex_name $inst_set $inst_num: $inst_data"
                @testset "$test_info" begin
                    println(test_info, "...")
                    test_time = @elapsed r = test_function(inst_data, T = T, options = options)
                    push!(perf, (mod_type, ex_name, inst_num, string(inst_data), test_time, r.solve_time, r.num_iters, r.status, r.primal_obj, r.dual_obj))
                    @printf("... %8.2e seconds\n", test_time)
                end
            end
        end
    end

    @printf("\nexamples tests total time: %8.2e seconds\n\n", time() - all_tests_time)
    show(perf, allrows = true, allcols = true)
    println("\n")
    show(timer)
    println("\n")
end
;

# TODO use these options then delete:
# @testset "JuMP examples" begin
#     @testset "centralpolymat" begin test_centralpolymatJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-6, tol_feas = 1e-7, options...) end
#     @testset "conditionnum" begin test_conditionnum_JuMP(; tol_rel_opt = 1e-7, tol_abs_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "contraction" begin test_contractionJuMP(; tol_rel_opt = 1e-4, tol_abs_opt = 1e-4, tol_feas = 1e-4, options...) end
#     @testset "densityest" begin test_densityestJuMP(; tol_rel_opt = 1e-5, tol_abs_opt = 1e-5, tol_feas = 1e-6, options...) end
#     @testset "envelope" begin test_envelopeJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "expdesign" begin test_expdesignJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "lotkavolterra" begin test_lotkavolterraJuMP(; tol_rel_opt = 1e-5, tol_abs_opt = 1e-6, tol_feas = 1e-6, options...) end
#     @testset "lyapunovstability" begin test_lyapunovstabilityJuMP(; tol_rel_opt = 1e-5, tol_abs_opt = 1e-5, tol_feas = 1e-5, options...) end
#     @testset "matrixcompletion" begin test_matrixcompletionJuMP(; options...) end
#     @testset "matrixquadratic" begin test_matrixquadraticJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "matrixcompletion" begin test_matrixregressionJuMP(; options...) end
#     @testset "maxvolume" begin test_maxvolumeJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "muconvexity" begin test_muconvexityJuMP(; options...) end
#     @testset "nearestpsd" begin test_nearestpsdJuMP(; options...) end
#     @testset "polymin" begin test_polyminJuMP(; tol_rel_opt = 1e-7, tol_abs_opt = 1e-8, tol_feas = 1e-8, options...) end
#     @testset "polynorm" begin test_polynormJuMP(; options...) end
#     @testset "portfolio" begin test_portfolioJuMP(; options...) end
#     @testset "regionofattr" begin test_regionofattrJuMP(; tol_abs_opt = 1e-6, tol_rel_opt = 1e-6, tol_feas = 1e-6, options...) end
#     @testset "robustgeomprog" begin test_robustgeomprogJuMP(; tol_abs_opt = 1e-7, tol_rel_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "secondorderpoly" begin test_secondorderpolyJuMP(; options...) end
#     @testset "semidefinitepoly" begin test_semidefinitepolyJuMP(; tol_abs_opt = 1e-7, tol_rel_opt = 1e-7, tol_feas = 1e-7, options...) end
#     @testset "shapeconregr" begin test_shapeconregrJuMP(; tol_rel_opt = 1e-6, tol_abs_opt = 1e-5, tol_feas = 1e-5, options...) end
#     @testset "signomialmin" begin test_signomialminJuMP(; tol_rel_opt = 1e-7, tol_abs_opt = 1e-6, tol_feas = 1e-7, options...) end
# end