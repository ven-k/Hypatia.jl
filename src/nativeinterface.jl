#=
Copyright 2018, David Papp, Sercan Yildiz, and contributors

an implementation of the algorithm for non-symmetric conic optimization Alfonso (https://github.com/dpapp-github/alfonso) and analyzed in the paper:
D. Papp and S. Yildiz. On "A homogeneous interior-point algorithm for nonsymmetric convex conic optimization"
available at https://arxiv.org/abs/1712.00492
=#

# TODO add time limit option and use it in loop
mutable struct AlfonsoOpt
    # options
    verbose::Bool           # if true, prints progress at each iteration
    optimtol::Float64       # optimization tolerance parameter
    maxiter::Int            # maximum number of iterations
    # itrefinethres::Float64  # iterative refinement success threshold
    # maxitrefinesteps::Int   # maximum number of iterative refinement steps in linear system solves
    predlinesearch::Bool    # if false, predictor step uses a fixed step size, else step size is determined via line search
    maxpredsmallsteps::Int  # maximum number of predictor step size reductions allowed with respect to the safe fixed step size
    predlsmulti::Float64    # predictor line search step size multiplier
    corrcheck::Bool         # if false, maxcorrsteps corrector steps are performed at each corrector phase, else the corrector phase can be terminated before maxcorrsteps corrector steps if the iterate is in the eta-neighborhood
    maxcorrsteps::Int       # maximum number of corrector steps (possible values: 1, 2, or 4)
    alphacorr::Float64      # corrector step size
    maxcorrlsiters::Int     # maximum number of line search iterations in each corrector step
    corrlsmulti::Float64    # corrector line search step size multiplier

    # problem data
    A::AbstractMatrix{Float64}  # constraint matrix
    b::Vector{Float64}          # right-hand side vector
    c::Vector{Float64}          # cost vector
    cone::Cone                  # primal cone object

    # algorithmic parameters
    bnu::Float64
    beta::Float64
    eta::Float64
    alphapredthres::Float64
    alphapredinit::Float64
    tol_pres::Float64
    tol_dres::Float64
    tol_compl::Float64

    # results
    status::Symbol          # solver status
    solvetime::Float64      # total solve time
    niters::Int             # total number of iterations
    y::Vector{Float64}      # final value of the dual free variables
    x::Vector{Float64}      # final value of the primal variables
    tau::Float64            # final value of the tau-variable
    s::Vector{Float64}      # final value of the dual slack variables
    kap::Float64            # final value of the kappa-variable
    pobj::Float64           # final primal objective value
    dobj::Float64           # final dual objective value
    dgap::Float64           # final duality gap
    cgap::Float64           # final complementarity gap
    rel_dgap::Float64       # final relative duality gap
    rel_cgap::Float64       # final relative complementarity gap
    pres::Vector{Float64}   # final primal residuals
    dres::Vector{Float64}   # final dual residuals
    pin::Float64            # final primal infeasibility
    din::Float64            # final dual infeasibility
    rel_pin::Float64        # final relative primal infeasibility
    rel_din::Float64        # final relative dual infeasibility

    # TODO match natural order of options listed above
    function AlfonsoOpt(verbose, optimtol, maxiter, predlinesearch, maxpredsmallsteps, maxcorrsteps, corrcheck, maxcorrlsiters, alphacorr, predlsmulti, corrlsmulti)
        alf = new()

        alf.verbose = verbose
        alf.optimtol = optimtol
        alf.maxiter = maxiter
        alf.predlinesearch = predlinesearch
        alf.maxpredsmallsteps = maxpredsmallsteps
        alf.maxcorrsteps = maxcorrsteps
        alf.corrcheck = corrcheck
        alf.maxcorrlsiters = maxcorrlsiters
        alf.alphacorr = alphacorr
        alf.predlsmulti = predlsmulti
        alf.corrlsmulti = corrlsmulti

        alf.status = :NotLoaded

        return alf
    end
end

function AlfonsoOpt(;
    verbose = false,
    optimtol = 1e-6,
    maxiter = 1e3,
    predlinesearch = true,
    maxpredsmallsteps = 8,
    maxcorrsteps = 8, # NOTE doubled in .m code
    corrcheck = true,
    maxcorrlsiters = 8,
    alphacorr = 1.0,
    predlsmulti = 0.7,
    corrlsmulti = 0.5,
    )

    if !(1e-10 <= optimtol <= 1e-2)
        error("optimtol must be from 1e-10 to 1e-2")
    end
    if maxiter < 1
        error("maxiter must be at least 1")
    end
    if maxpredsmallsteps < 1
        error("maxcorrsteps must be at least 1")
    end
    if !(1 <= maxcorrsteps <= 8)
        error("maxcorrsteps must be from 1 to 8")
    end

    return AlfonsoOpt(verbose, optimtol, maxiter, predlinesearch, maxpredsmallsteps, maxcorrsteps, corrcheck, maxcorrlsiters, alphacorr, predlsmulti, corrlsmulti)
end

get_status(alf::AlfonsoOpt) = alf.status
get_solvetime(alf::AlfonsoOpt) = alf.solvetime
get_niters(alf::AlfonsoOpt) = alf.niters
get_y(alf::AlfonsoOpt) = copy(alf.y)
get_x(alf::AlfonsoOpt) = copy(alf.x)
get_tau(alf::AlfonsoOpt) = alf.tau
get_s(alf::AlfonsoOpt) = copy(alf.s)
get_kappa(alf::AlfonsoOpt) = alf.kappa
get_pobj(alf::AlfonsoOpt) = alf.pobj
get_dobj(alf::AlfonsoOpt) = alf.dobj
get_dgap(alf::AlfonsoOpt) = alf.dgap
get_cgap(alf::AlfonsoOpt) = alf.cgap
get_rel_dgap(alf::AlfonsoOpt) = alf.rel_dgap
get_rel_cgap(alf::AlfonsoOpt) = alf.rel_cgap
get_pres(alf::AlfonsoOpt) = copy(alf.pres)
get_dres(alf::AlfonsoOpt) = copy(alf.dres)
get_pin(alf::AlfonsoOpt) = alf.pin
get_din(alf::AlfonsoOpt) = alf.din
get_rel_pin(alf::AlfonsoOpt) = alf.rel_pin
get_rel_din(alf::AlfonsoOpt) = alf.rel_din

# load and verify problem data, calculate algorithmic parameters
function load_data!(
    alf::AlfonsoOpt,
    A::AbstractMatrix{Float64},
    b::Vector{Float64},
    c::Vector{Float64},
    cone::Cone,
    )
    # check data consistency
    (m, n) = size(A)
    if (m == 0) || (n == 0)
        error("input matrix A has trivial dimension $m x $n")
    end
    if m != length(b)
        error("dimension of vector b is $(length(b)), but number of rows in matrix A is $m")
    end
    if n != length(c)
        error("dimension of vector c is $(length(c)), but number of columns in matrix A is $n")
    end
    if issparse(A)
        dropzeros!(A)
    end

    # TODO check cone consistency in cone functions file
    # idxend = 0
    # for k in eachindex(cone)
    #     if dimension(cone[k]) != length(coneidxs[k])
    #         error("dimension of cone type $(cone[k]) does not match length of variable indices")
    #     end
    #     @assert coneidxs[k][1] == idxend + 1
    #     idxend += length(coneidxs[k])
    # end
    # @assert idxend == n

    # calculate complexity parameter nu-bar of the augmented barrier (sum of the primitive cone barrier parameters plus 1)
    bnu = 1 + barrierpar(cone)

    # calculate prediction and correction step parameters
    (beta, eta, cpredfix) = getbetaeta(alf.maxcorrsteps, bnu) # beta: large neighborhood parameter, eta: small neighborhood parameter
    alphapredfix = cpredfix/(eta + sqrt(2*eta^2 + bnu)) # fixed predictor step size
    alphapredthres = (alf.predlsmulti^alf.maxpredsmallsteps)*alphapredfix # minimum predictor step size
    alphapredinit = (alf.predlinesearch ? min(100*alphapredfix, 0.9999) : alphapredfix) # predictor step size

    # calculate termination tolerances: infinity operator norms of submatrices of LHS matrix
    tol_pres = max(1.0, maximum(sum(abs, A[i,:]) + abs(b[i]) for i in 1:m)) # first m rows
    tol_dres = max(1.0, maximum(sum(abs, A[:,j]) + abs(c[j]) + 1.0 for j in 1:n)) # next n rows
    tol_compl = max(1.0, maximum(abs, b), maximum(abs, c)) # row m+n+1

    # save data in solver object
    alf.A = A
    alf.b = b
    alf.c = c
    alf.cone = cone
    alf.bnu = bnu
    alf.beta = beta
    alf.eta = eta
    alf.alphapredthres = alphapredthres
    alf.alphapredinit = alphapredinit
    alf.tol_pres = tol_pres
    alf.tol_dres = tol_dres
    alf.tol_compl = tol_compl

    alf.status = :Loaded

    return alf
end

# calculate initial central primal-dual iterate
function getinitialiterate(alf::AlfonsoOpt)
    (A, b, c) = (alf.A, alf.b, alf.c)
    (m, n) = size(A)
    cone = alf.cone

    # scaling factor for the primal problem
    rp = maximum((1.0 + abs(b[i]))/(1.0 + abs(sum(A[i,:]))) for i in 1:m)
    # scaling factor for the dual problem
    g = ones(n)
    loadpnt!(cone, g)
    @assert incone(cone)
    calcg!(g, cone)
    rd = maximum((1.0 + abs(g[j]))/(1.0 + abs(c[j])) for j in 1:n)

    # central primal-dual iterate
    tx = fill(sqrt(rp*rd), n)
    loadpnt!(cone, tx)
    @assert incone(cone)
    ty = zeros(m)
    tau = 1.0
    ts = calcg!(g, cone)
    ts .*= -1
    kap = 1.0
    mu = (dot(tx, ts) + tau*kap)/alf.bnu

    return (tx, ty, tau, ts, kap, mu)
end

# perform prediction and correction steps in a loop until converged
function solve!(alf::AlfonsoOpt)
    starttime = time()

    (A, b, c) = (alf.A, alf.b, alf.c)
    (m, n) = size(A)
    cone = alf.cone

    # calculate initial central primal-dual iterate
    (tx, ty, tau, ts, kap, mu) = getinitialiterate(alf)

    # preallocate arrays
    rhs_ty = similar(ty)
    rhs_tx = similar(tx)
    dir_ty = similar(ty)
    dir_tx = similar(tx)
    dir_ts = similar(ts)
    sa_tx = copy(tx)
    loadpnt!(cone, sa_tx)
    sa_ts = similar(ts)
    g = similar(tx)
    HiAt = similar(b, n, m) # TODO for very sparse LPs, using sparse here is good (diagonal hessian), but for sparse problems with dense hessians, want dense
    y1 = similar(b)
    x1 = similar(c)
    y2 = similar(b)
    x2 = similar(c)

    # main loop
    if alf.verbose
        @printf("\n%5s %12s %12s %9s %9s %9s %9s %9s %9s\n", "iter", "p_obj", "d_obj", "gap", "p_inf", "d_inf", "tau", "kap", "mu")
        flush(stdout)
    end

    alf.status = :StartedIterating
    alphapred = alf.alphapredinit
    iter = 0
    while true
        # calculate convergence metrics
        ctx = dot(c, tx)
        bty = dot(b, ty)
        p_obj = ctx/tau
        d_obj = bty/tau
        gap = abs(ctx - bty)/(tau + abs(bty))
        rhs_ty .= -A*tx + b*tau
        p_inf = maximum(abs, rhs_ty)/alf.tol_pres
        rhs_tx .= A'*ty - c*tau + ts
        d_inf = maximum(abs, rhs_tx)/alf.tol_dres
        rhs_tau = -bty + ctx + kap
        compl = abs(rhs_tau)/alf.tol_compl

        if alf.verbose
            # print iteration statistics
            @printf("%5d %12.4e %12.4e %9.2e %9.2e %9.2e %9.2e %9.2e %9.2e\n", iter, p_obj, d_obj, gap, p_inf, d_inf, tau, kap, mu)
            flush(stdout)
        end

        # check convergence criteria
        if (p_inf <= alf.optimtol) && (d_inf <= alf.optimtol)
            if gap <= alf.optimtol
                alf.verbose && println("Problem is feasible and an approximate optimal solution was found; terminating")
                alf.status = :Optimal
                break
            elseif (compl <= alf.optimtol) && (tau <= alf.optimtol*1e-02*max(1.0, kap))
                alf.verbose && println("Problem is nearly primal or dual infeasible; terminating")
                alf.status = :NearlyInfeasible
                break
            end
        elseif (tau <= alf.optimtol*1e-02*min(1.0, kap)) && (mu <= alf.optimtol*1e-02)
            alf.verbose && println("Problem is ill-posed; terminating")
            alf.status = :IllPosed
            break
        end

        # check iteration limit
        iter += 1
        if iter >= alf.maxiter
            alf.verbose && println("Reached iteration limit; terminating")
            alf.status = :IterationLimit
            break
        end

        # prediction phase
        # determine prediction direction
        invmu = 1.0/mu
        calcHiprod!(HiAt, A', cone) # TODO may be faster as calcLiprod
        HiAt .*= invmu
        FAW = cholesky(Symmetric(A*HiAt))
        # TODO can parallelize 1 and 2
        y1 .= FAW\(b + HiAt'*c)
        calcHiprod!(x1, invmu*(A'*y1 - c), cone)
        y2 .= FAW\(rhs_ty + HiAt'*(ts - rhs_tx))
        calcHiprod!(x2, invmu*(A'*y2 - ts + rhs_tx), cone)

        dir_tau = (rhs_tau - kap - dot(b, y2) + dot(c, x2))/(mu/tau^2 + dot(b, y1) - dot(c, x1))
        dir_ty .= y2 + dir_tau*y1
        dir_tx .= x2 + dir_tau*x1
        dir_ts .= -rhs_tx - A'*dir_ty + c*dir_tau
        dir_kap = -rhs_tau + dot(b, dir_ty) - dot(c, dir_tx)

        # determine step length alpha by line search
        alpha = alphapred
        nbhd = Inf
        alphaprevok = true
        predfail = false
        nprediters = 0
        while true
            nprediters += 1

            sa_tx .= tx + alpha*dir_tx

            # accept primal iterate if
            # - decreased alpha and it is the first inside the cone and beta-neighborhood or
            # - increased alpha and it is inside the cone and the first to leave beta-neighborhood
            if incone(cone)
                # primal iterate is inside the cone
                sa_ts .= ts + alpha*dir_ts
                sa_tk = (tau + alpha*dir_tau)*(kap + alpha*dir_kap)
                sa_mu = (dot(sa_tx, sa_ts) + sa_tk)/alf.bnu

                calcg!(g, cone)
                sa_ts .+= sa_mu*g
                calcLiprod!(g, sa_ts, cone)
                nbhd = sqrt((sa_tk - sa_mu)^2 + sum(abs2, g))/sa_mu

                if nbhd < alf.beta
                    # iterate is inside the beta-neighborhood
                    if !alphaprevok || (alpha > alf.predlsmulti)
                        # either the previous iterate was outside the beta-neighborhood or increasing alpha again will make it > 1
                        if alf.predlinesearch
                            alphapred = alpha
                        end
                        break
                    end

                    alphaprevok = true
                    alpha = alpha/alf.predlsmulti # increase alpha
                    continue
                end

                # iterate is outside the beta-neighborhood
                if alphaprevok
                    # previous iterate was inside the beta-neighborhood
                    if alf.predlinesearch
                        alphapred = alpha*alf.predlsmulti
                    end
                    break
                end
            end

            # primal iterate is either
            # - outside the cone or
            # - inside the cone and outside the beta-neighborhood and previous iterate was outside the beta-neighborhood
            if alpha < alf.alphapredthres
                # alpha is very small, so predictor has failed
                predfail = true
                alf.verbose && println("Predictor could not improve the solution ($nprediters line search steps); terminating")
                alf.status = :PredictorFail
                break
            end

            alphaprevok = false
            alpha = alf.predlsmulti*alpha # decrease alpha
        end
        # @show nprediters
        if predfail
            break
        end

        # step distance alpha in the direction
        ty .+= alpha*dir_ty
        tx .+= alpha*dir_tx
        tau += alpha*dir_tau
        ts .+= alpha*dir_ts
        kap += alpha*dir_kap
        mu = (dot(tx, ts) + tau*kap)/alf.bnu

        # skip correction phase if allowed and current iterate is in the eta-neighborhood
        if alf.corrcheck && (nbhd <= alf.eta)
            continue
        end

        # correction phase
        corrfail = false
        ncorrsteps = 0
        while true
            ncorrsteps += 1

            # calculate correction direction
            calcg!(g, cone)
            invmu = 1.0/mu
            calcHiprod!(HiAt, A', cone) # TODO may be faster as calcLiprod
            HiAt .*= invmu
            FAW = cholesky(Symmetric(A*HiAt), check=false)
            # TODO can parallelize 1 and 2
            y1 .= FAW\(b + HiAt'*c)
            calcHiprod!(x1, invmu*(A'*y1 - c), cone)
            y2 .= FAW\(HiAt'*(ts + mu*g))
            calcHiprod!(x2, invmu*(A'*y2 - ts) - g, cone)

            dir_tau = (mu/tau - kap - dot(b, y2) + dot(c, x2))/(mu/tau^2 + dot(b, y1) - dot(c, x1))
            dir_ty .= y2 + dir_tau*y1
            dir_tx .= x2 + dir_tau*x1
            dir_ts .= -A'*dir_ty + c*dir_tau
            dir_kap = dot(b, dir_ty) - dot(c, dir_tx)

            # determine step length alpha by line search
            alpha = alf.alphacorr
            ncorrlsiters = 0
            while ncorrlsiters <= alf.maxcorrlsiters
                ncorrlsiters += 1

                sa_tx .= tx + alpha*dir_tx

                if incone(cone)
                    # primal iterate tx is inside the cone, so terminate line search
                    break
                end

                # primal iterate tx is outside the cone
                if ncorrlsiters == alf.maxcorrlsiters
                    # corrector failed
                    corrfail = true
                    alf.verbose && println("Corrector could not improve the solution ($ncorrlsiters line search steps); terminating")
                    alf.status = :CorrectorFail
                    break
                end

                alpha = alf.corrlsmulti*alpha # decrease alpha
            end
            # @show ncorrlsiters
            if corrfail
                break
            end

            # step distance alpha in the direction
            ty .+= alpha*dir_ty
            tx .= sa_tx
            tau += alpha*dir_tau
            ts .+= alpha*dir_ts
            kap += alpha*dir_kap
            mu = (dot(tx, ts) + tau*kap)/alf.bnu

            # finish if allowed and current iterate is in the eta-neighborhood, or if taken max steps
            if (ncorrsteps == alf.maxcorrsteps) || alf.corrcheck
                calcg!(g, cone)
                sa_ts .= ts + mu*g
                calcLiprod!(g, sa_ts, cone)
                nbhd = sqrt((tau*kap - mu)^2 + sum(abs2, g))/mu

                if nbhd <= alf.eta
                    break
                elseif ncorrsteps == alf.maxcorrsteps
                    # nbhd_eta > eta, so corrector failed
                    corrfail = true
                    alf.verbose && println("Corrector phase finished outside the eta-neighborhood ($ncorrsteps correction steps); terminating")
                    alf.status = :CorrectorFail
                    break
                end
            end
        end
        # @show ncorrsteps
        if corrfail
            break
        end
    end

    alf.verbose && println("\nFinished in $iter iterations\nInternal status is $(alf.status)\n")

    # calculate final solution and iteration statistics
    alf.niters = iter

    alf.x = tx./tau
    alf.y = ty./tau
    alf.tau = tau
    alf.s = ts./tau
    alf.kap = kap

    alf.pobj = dot(c, alf.x)
    alf.dobj = dot(b, alf.y)
    alf.dgap = alf.pobj - alf.dobj
    alf.cgap = dot(alf.s, alf.x)
    alf.rel_dgap = alf.dgap/(1.0 + abs(alf.pobj) + abs(alf.dobj))
    alf.rel_cgap = alf.cgap/(1.0 + abs(alf.pobj) + abs(alf.dobj))

    alf.pres = b - A*alf.x
    alf.dres = c - A'*alf.y - alf.s
    alf.pin = norm(alf.pres)
    alf.din = norm(alf.dres)
    alf.rel_pin = alf.pin/(1.0 + norm(b, Inf))
    alf.rel_din = alf.din/(1.0 + norm(c, Inf))

    alf.solvetime = time() - starttime

    return nothing
end

function getbetaeta(maxcorrsteps, bnu)
    if maxcorrsteps <= 2
        if bnu < 10.0
            return (0.1810, 0.0733, 0.0225)
        elseif bnu < 100.0
            return (0.2054, 0.0806, 0.0263)
        else
            return (0.2190, 0.0836, 0.0288)
        end
    elseif maxcorrsteps <= 4
        if bnu < 10.0
            return (0.2084, 0.0502, 0.0328)
        elseif bnu < 100.0
            return (0.2356, 0.0544, 0.0380)
        else
            return (0.2506, 0.0558, 0.0411)
        end
    else
        if bnu < 10.0
            return (0.2387, 0.0305, 0.0429)
        elseif bnu < 100.0
            return (0.2683, 0.0327, 0.0489)
        else
            return (0.2844, 0.0332, 0.0525)
        end
    end
end