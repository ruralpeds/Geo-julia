# bym.jl — Besag-York-Mollié (BYM) Bayesian Disease Mapping
# ICAR spatial prior + uncorrelated heterogeneity; Gibbs sampler

using Statistics, LinearAlgebra, Random

# ── Spatial adjacency and ICAR precision ─────────────────────────────────────

"""
    build_adjacency(coords; threshold) -> (W, Q)

Build binary adjacency matrix from spatial coordinates using
distance threshold, and ICAR precision matrix Q = D - W.
"""
function build_adjacency(coords::AbstractMatrix; threshold::Float64=0.0)
    n = size(coords, 1)
    # Auto threshold: kth-nearest distance
    if threshold <= 0.0
        D = [sqrt(sum((coords[i,:] .- coords[j,:]).^2)) for i in 1:n, j in 1:n]
        k = min(4, n-1)  # 4 nearest neighbours
        threshold = mean(sort(D[i,:])[2:k+1] |> mean for i in 1:n)
    end
    W = zeros(n, n)
    for i in 1:n, j in i+1:n
        d = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
        if d <= threshold
            W[i,j] = 1.0; W[j,i] = 1.0
        end
    end
    m_i = vec(sum(W, dims=2))
    Q   = diagm(m_i) - W   # ICAR precision (improper)
    W, Q, m_i
end

# ── BYM log posteriors ────────────────────────────────────────────────────────

function _log_likelihood_poisson(O, E, η)
    ll = 0.0
    for i in eachindex(O)
        λ = max(E[i] * exp(η[i]), 1e-300)
        ll += O[i] * log(λ) - λ
    end
    ll
end

function _log_prior_icar(u, Q, τ_u)
    # log p(u|τ_u) ∝ (n-1)/2 log τ_u - τ_u/2 u'Qu
    n = length(u)
    -τ_u / 2 * (u' * Q * u)
end

function _log_prior_iid(v, τ_v)
    n = length(v)
    -τ_v / 2 * sum(v.^2)
end

# ── Gibbs sampler for BYM ─────────────────────────────────────────────────────

"""
    BYMResult

Fitted BYM model.

Fields: u_mean, u_var (spatial effect); v_mean, v_var (uncorrelated);
        η_mean (log relative risk); smr (raw SMR); rr (posterior mean RR);
        dic, pd (deviance information criterion, effective parameters);
        posterior samples (if keep_samples=true).
"""
struct BYMResult
    u_mean   ::Vector{Float64}
    u_var    ::Vector{Float64}
    v_mean   ::Vector{Float64}
    v_var    ::Vector{Float64}
    η_mean   ::Vector{Float64}
    rr       ::Vector{Float64}   # exp(μ + u + v)
    rr_lower ::Vector{Float64}
    rr_upper ::Vector{Float64}
    τ_u_mean ::Float64
    τ_v_mean ::Float64
    dic      ::Float64
    pd       ::Float64
    n_iter   ::Int
    n_areas  ::Int
end

"""
    bym_fit(O, E, W, Q; μ_init, n_iter, n_warmup, rng,
            a_τ, b_τ, proposal_sd) -> BYMResult

Fit the BYM2 model (Riebler et al. 2016) by Gibbs/MH sampling.

Model:
  O_i | u_i, v_i ~ Poisson(E_i · exp(μ + u_i + v_i))
  u | τ_u ~ ICAR(Q, τ_u);  τ_u ~ Gamma(a, b)
  v_i | τ_v ~ N(0, 1/τ_v); τ_v ~ Gamma(a, b)
  μ ~ flat

Individual u_i updates via Metropolis-Hastings with Gaussian proposal.
τ_u, τ_v updated via Gibbs (conjugate Gamma).
μ updated via Gibbs (conjugate normal).
"""
function bym_fit(O::AbstractVector, E::AbstractVector,
                  W::AbstractMatrix, Q::AbstractMatrix;
                  n_iter::Int=2000,
                  n_warmup::Int=500,
                  rng::AbstractRNG=Random.GLOBAL_RNG,
                  a_τ::Float64=1.0, b_τ::Float64=0.01,
                  proposal_sd::Float64=0.2)
    n     = length(O)
    O_f   = Float64.(O); E_f = Float64.(E)

    # Initialise
    μ     = log(sum(O_f) / max(sum(E_f), 1e-10))
    u     = zeros(n)
    v     = zeros(n)
    τ_u   = 1.0; τ_v = 1.0

    # Storage
    n_keep   = n_iter - n_warmup
    u_samps  = zeros(n_keep, n); v_samps = zeros(n_keep, n)
    τu_samps = zeros(n_keep);   τv_samps = zeros(n_keep)
    η_samps  = zeros(n_keep, n)

    accept_u = zeros(n)

    for iter in 1:(n_iter)
        # ── Update each u_i via MH ──
        for i in 1:n
            u_prop = u[i] + proposal_sd * randn(rng)
            η_old  = μ .+ u .+ v
            η_prop = copy(η_old); η_prop[i] += u_prop - u[i]

            ll_diff = O_f[i] * (η_prop[i] - η_old[i]) -
                      E_f[i] * (exp(η_prop[i]) - exp(η_old[i]))
            u_all_prop      = copy(u); u_all_prop[i] = u_prop
            lp_diff = -τ_u/2 * (u_all_prop' * Q * u_all_prop - u' * Q * u)

            log_accept = ll_diff + lp_diff
            if log(rand(rng)) < log_accept
                u[i] = u_prop
                iter > n_warmup && (accept_u[i] += 1)
            end
        end
        # Centre u (improper prior — need centering)
        u .-= mean(u)

        # ── Update each v_i via Gibbs ──
        η_no_v = μ .+ u
        for i in 1:n
            # Posterior: N( post_mean, post_var )
            # p(v_i | rest) ∝ Poisson(E_i exp(η_no_v_i + v_i)) * N(v_i; 0, 1/τ_v)
            # MH step for v_i
            v_prop   = v[i] + 0.15 * randn(rng)
            ll_diff  = O_f[i]*(v_prop - v[i]) - E_f[i]*(exp(η_no_v[i]+v_prop) - exp(η_no_v[i]+v[i]))
            lp_diff  = -τ_v/2 * (v_prop^2 - v[i]^2)
            if log(rand(rng)) < ll_diff + lp_diff
                v[i] = v_prop
            end
        end

        # ── Update μ via random walk MH ──
        μ_prop = μ + 0.05 * randn(rng)
        η_cur  = μ  .+ u .+ v
        η_prop_μ = μ_prop .+ u .+ v
        ll_diff_μ = sum(O_f .* (η_prop_μ .- η_cur) .- E_f .* (exp.(η_prop_μ) .- exp.(η_cur)))
        if log(rand(rng)) < ll_diff_μ
            μ = μ_prop
        end

        # ── Update τ_u via Gibbs (Gamma conjugate) ──
        a_post = a_τ + (n - 1) / 2.0
        b_post = b_τ + 0.5 * (u' * Q * u)
        τ_u    = rand_gamma(rng, a_post, 1.0/b_post)

        # ── Update τ_v via Gibbs ──
        a_v = a_τ + n / 2.0
        b_v = b_τ + 0.5 * sum(v.^2)
        τ_v = rand_gamma(rng, a_v, 1.0/b_v)

        # ── Store ──
        if iter > n_warmup
            k = iter - n_warmup
            u_samps[k,:] = u; v_samps[k,:] = v
            τu_samps[k]  = τ_u; τv_samps[k] = τ_v
            η_samps[k,:] = μ .+ u .+ v
        end
    end

    # Posterior summaries
    u_mean = vec(mean(u_samps, dims=1))
    u_var  = vec(var(u_samps,  dims=1))
    v_mean = vec(mean(v_samps, dims=1))
    v_var  = vec(var(v_samps,  dims=1))
    η_mean = vec(mean(η_samps, dims=1))
    rr     = exp.(η_mean)

    rr_lo  = [quantile(exp.(η_samps[:,i]), 0.025) for i in 1:n]
    rr_hi  = [quantile(exp.(η_samps[:,i]), 0.975) for i in 1:n]

    # DIC: D̄ - 2pD where pD = D̄ - D(θ̄)
    D_bar = mean([-2*_log_likelihood_poisson(O_f, E_f, η_samps[s,:])
                  for s in 1:n_keep])
    D_at_mean = -2 * _log_likelihood_poisson(O_f, E_f, η_mean)
    pd  = D_bar - D_at_mean
    dic = D_bar + pd

    BYMResult(u_mean, u_var, v_mean, v_var, η_mean, rr, rr_lo, rr_hi,
              mean(τu_samps), mean(τv_samps), dic, pd, n_iter, n)
end

# ── Gamma random variate (Marsaglia-Tsang) ────────────────────────────────────

function rand_gamma(rng::AbstractRNG, α::Float64, θ::Float64)
    α <= 0 && error("α must be positive")
    if α < 1.0
        u = rand(rng)
        return rand_gamma(rng, α + 1.0, θ) * u^(1.0/α)
    end
    # Marsaglia & Tsang (2000)
    d = α - 1.0/3.0; c = 1.0/sqrt(9d)
    while true
        x = randn(rng); v = (1 + c*x)^3
        if v > 0
            u = rand(rng)
            if log(u) < 0.5*x^2 + d - d*v + d*log(v)
                return d * v * θ
            end
        end
    end
end
