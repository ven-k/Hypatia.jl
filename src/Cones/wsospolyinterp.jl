#=
Copyright 2018, Chris Coey and contributors
Copyright 2018, David Papp, Sercan Yildiz

interpolation-based weighted-sum-of-squares (multivariate) polynomial cone parametrized by interpolation points ipwt

definition and dual barrier from "Sum-of-squares optimization without semidefinite programming" by D. Papp and S. Yildiz, available at https://arxiv.org/abs/1712.01792

TODO can perform loop for calculating g and H in parallel
TODO scale the interior direction
=#

mutable struct WSOSPolyInterp <: Cone
    use_dual::Bool
    dim::Int
    ipwt::Vector{Matrix{Float64}}

    point::AbstractVector{Float64}
    g::Vector{Float64}
    H::Matrix{Float64}
    H2::Matrix{Float64}
    Hi::Matrix{Float64}
    F # TODO prealloc
    tmp1::Vector{Matrix{Float64}}
    tmp2::Vector{Matrix{Float64}}
    tmp3::Matrix{Float64}

    function WSOSPolyInterp(dim::Int, ipwt::Vector{Matrix{Float64}}, is_dual::Bool)
        for ipwtj in ipwt
            @assert size(ipwtj, 1) == dim
        end
        cone = new()
        cone.use_dual = !is_dual # using dual barrier
        cone.dim = dim
        cone.ipwt = ipwt
        return cone
    end
end

WSOSPolyInterp(dim::Int, ipwt::Vector{Matrix{Float64}}) = WSOSPolyInterp(dim, ipwt, false)

function setup_data(cone::WSOSPolyInterp)
    dim = cone.dim
    ipwt = cone.ipwt
    cone.g = similar(ipwt[1], dim)
    cone.H = similar(ipwt[1], dim, dim)
    cone.H2 = similar(cone.H)
    cone.Hi = similar(cone.H)
    cone.tmp1 = [similar(ipwt[1], size(ipwtj, 2), size(ipwtj, 2)) for ipwtj in ipwt]
    cone.tmp2 = [similar(ipwt[1], size(ipwtj, 2), dim) for ipwtj in ipwt]
    cone.tmp3 = similar(ipwt[1], dim, dim)
    return
end

get_nu(cone::WSOSPolyInterp) = sum(size(ipwtj, 2) for ipwtj in cone.ipwt)

set_initial_point(arr::AbstractVector{Float64}, cone::WSOSPolyInterp) = (@. arr = 1.0; arr)

function check_in_cone(cone::WSOSPolyInterp)
    ΛFs = Vector{CholeskyPivoted{Float64, Matrix{Float64}}}(undef, length(cone.ipwt))

    for j in eachindex(cone.ipwt) # TODO can be done in parallel
        ipwtj = cone.ipwt[j]
        tmp1j = cone.tmp1[j]
        tmp2j = cone.tmp2[j]

        # tmp1j = ipwtj'*Diagonal(point)*ipwtj
        # mul!(tmp2j, ipwtj', Diagonal(cone.point)) # TODO dispatches to an extremely inefficient method, but should be fixed on master now - check timings for both
        @. tmp2j = ipwtj' * cone.point'
        mul!(tmp1j, tmp2j, ipwtj)

        # pivoted cholesky and triangular solve method
        ΛFj = cholesky!(Symmetric(tmp1j, :L), Val(true), check = false)
        if !isposdef(ΛFj)
            return false
        end
        ΛFs[j] = ΛFj
    end

    @. cone.g = 0.0
    @. cone.H = 0.0
    tmp3 = cone.tmp3

    for j in eachindex(cone.ipwt) # TODO can be done in parallel, but need multiple tmp3s
        ipwtj = cone.ipwt[j]
        tmp2j = cone.tmp2[j]
        ΛFj = ΛFs[j]

        tmp2j .= view(ipwtj', ΛFj.p, :)
        ldiv!(ΛFj.L, tmp2j) # TODO make sure calls best triangular solve
        # mul!(tmp3, tmp2j', tmp2j)
        BLAS.syrk!('U', 'T', 1.0, tmp2j, 0.0, tmp3)

        @inbounds for j in eachindex(cone.g)
            cone.g[j] -= tmp3[j, j]
            @inbounds for i in 1:j
                cone.H[i, j] += abs2(tmp3[i, j])
            end
        end
    end

    return factorize_hess(cone)
end