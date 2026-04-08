#!/usr/bin/env julia
# scripts/spatial_glm.jl
#
# Spatial Generalised Linear Models via Turing.jl MCMC.
# Implements:
#   - Bayesian Spatial Poisson GLM with ICAR random effect
#   - Spatial Negative Binomial GLM for overdispersed counts
#   - Spatial Logistic regression for binary outcomes
#   - Posterior predictive checks
#
# Prerequisites:
#   julia> using Pkg
#   julia> Pkg.add.(["Turing", "LinearAlgebra", "SparseArrays", "Distributions"])
#
# Vol 4 — Advanced Methods, Real Data, and Deployment, Chapter 27

using LinearAlgebra
using SparseArrays
using Statistics
using Distributions

# Conditional imports — avoid hard dependency on Turing for users without it
const _TURING_AVAILABLE = Ref(false)
try
    @eval using Turing
    _TURING_AVAILABLE[] = true
catch
    @warn "Turing.jl not installed. Spatial GLM models require: ] add Turing"
end

# ── ICAR precision matrix construction ───────────────────────────────────────

"""
    build_icar_precision(W; epsilon=1e-6) -> Matrix{Float64}

Build the ICAR precision matrix Q = D - W + εI.
  D = diagonal degree matrix (row sums of W)
  Q is the graph Laplacian, which is improper (rank-deficient by 1).
  Adding εI makes it proper for MCMC sampling.
"""
function build_icar_precision(W::AbstractMatrix{<:Real}; epsilon::Float64 = 1e-6)
    n = size(W, 1)
    D = Diagonal(vec(sum(W; dims=2)))
    Matrix(D - W + epsilon * I(n))
end

"""
    build_icar_cov(W; epsilon=1e-6, sigma=1.0) -> Matrix{Float64}

Covariance matrix Σ = σ² * pinv(Q + εI).
Used for the ICAR spatial random effect prior.
"""
function build_icar_cov(W::AbstractMatrix{<:Real};
                         epsilon::Float64 = 1e-6,
                         sigma::Float64   = 1.0)
    Q = build_icar_precision(W; epsilon)
    sigma^2 * pinv(Symmetric(Q))
end

# ── Spatial Poisson GLM ───────────────────────────────────────────────────────

if _TURING_AVAILABLE[]

"""
    @model spatial_poisson_glm(y, X, E, W)

Bayesian Spatial Poisson GLM with ICAR random effect.

Model: log(μᵢ) = log(Eᵢ) + Xᵢβ + φᵢ
       φ ~ ICAR(W, σ²_φ)
       y ~ Poisson(μ)

# Arguments
- `y`  : observed case counts (Vector{Int})
- `X`  : design matrix with covariates (n × k), include intercept
- `E`  : expected counts for indirect standardisation (Vector{Float64})
- `W`  : binary (0/1) spatial adjacency matrix (queen contiguity)

# Returns
Turing MCMC chain
"""
@model function spatial_poisson_glm(
    y :: Vector{Int},
    X :: Matrix{Float64},
    E :: Vector{Float64},
    W :: Matrix{Float64}
)
    n, k = size(X)

    # ── Regression coefficients ──────────────────────────────────────────
    β ~ MvNormal(zeros(k), 10.0 * I(k))

    # ── Spatial random effect hyperparameter ─────────────────────────────
    σ_φ ~ truncated(Normal(0, 1); lower=0)

    # ── ICAR spatial random effect ────────────────────────────────────────
    # Precision Q = D - W; add εI for numerical stability
    Σ_φ = σ_φ^2 * pinv(Symmetric(Diagonal(vec(sum(W; dims=2))) - W + 1e-6 * I(n)))
    φ  ~ MvNormal(zeros(n), Symmetric(Σ_φ))
    φ_centered = φ .- mean(φ)   # sum-to-zero constraint

    # ── Log-linear predictor ──────────────────────────────────────────────
    η = log.(E) .+ X * β .+ φ_centered
    μ = exp.(η)

    # ── Likelihood ────────────────────────────────────────────────────────
    for i in 1:n
        y[i] ~ Poisson(μ[i])
    end

    return (; μ, φ_centered, excess_risk = μ ./ E)
end

"""
    @model spatial_negbin_glm(y, X, E, W)

Spatial Negative Binomial GLM for overdispersed counts.
Adds dispersion parameter r (NegBin: Var = μ + μ²/r).
r → ∞ converges to Poisson.
"""
@model function spatial_negbin_glm(
    y :: Vector{Int},
    X :: Matrix{Float64},
    E :: Vector{Float64},
    W :: Matrix{Float64}
)
    n, k = size(X)
    β   ~ MvNormal(zeros(k), 10.0 * I(k))
    σ_φ ~ truncated(Normal(0, 1); lower=0)
    r   ~ truncated(Normal(10, 10); lower=0.01)  # dispersion

    Σ_φ = σ_φ^2 * pinv(Symmetric(Diagonal(vec(sum(W; dims=2))) - W + 1e-6 * I(n)))
    φ   ~ MvNormal(zeros(n), Symmetric(Σ_φ))
    φ_c = φ .- mean(φ)

    η   = log.(E) .+ X * β .+ φ_c
    μ   = exp.(η)

    for i in 1:n
        p_i = r / (r + μ[i])
        y[i] ~ NegativeBinomial(r, p_i)
    end

    return (; μ, φ_c, excess_risk = μ ./ E, dispersion = r)
end

"""
    @model spatial_logistic(y, X, W)

Spatial logistic regression for binary health outcomes.
Example: county-level hospital presence (y=1/0).

Model: logit(P(yᵢ=1)) = Xᵢβ + φᵢ
       φ ~ ICAR(W, σ²)
"""
@model function spatial_logistic(
    y :: Vector{Int},
    X :: Matrix{Float64},
    W :: Matrix{Float64}
)
    n, k = size(X)
    β   ~ MvNormal(zeros(k), 5.0 * I(k))
    σ_φ ~ truncated(Normal(0, 1); lower=0)

    Σ_φ = σ_φ^2 * pinv(Symmetric(Diagonal(vec(sum(W; dims=2))) - W + 1e-6 * I(n)))
    φ   ~ MvNormal(zeros(n), Symmetric(Σ_φ))
    φ_c = φ .- mean(φ)

    for i in 1:n
        p_i = 1.0 / (1.0 + exp(-(dot(X[i, :], β) + φ_c[i])))
        y[i] ~ Bernoulli(p_i)
    end
end

# ── Fitting functions ─────────────────────────────────────────────────────────

"""
    fit_spatial_poisson(y, X, E, W; n_iter=2000, n_chains=4) -> NamedTuple

Fit the Spatial Poisson GLM. Returns (chain, rr_mean, rr_95lo, rr_95hi).
"""
function fit_spatial_poisson(
    y        :: Vector{Int},
    X        :: Matrix{Float64},
    E        :: Vector{Float64},
    W        :: Matrix{Float64};
    n_iter   :: Int = 2000,
    n_chains :: Int = 4
)
    model   = spatial_poisson_glm(y, X, E, W)
    sampler = NUTS(0.8)

    @info "Fitting Spatial Poisson GLM: n=$(length(y)), k=$(size(X,2)), chains=$(n_chains)"
    chain = sample(model, sampler, MCMCThreads(), n_iter, n_chains;
                   discard_initial = n_iter ÷ 4,
                   progress = false)

    # Posterior summaries
    post    = generated_quantities(model, chain)
    rr_post = [q.excess_risk for q in post]
    ni      = length(y)

    rr_mean = mean([rr_post[k] for k in eachindex(rr_post)])
    rr_95lo = [quantile([rr_post[k][i] for k in eachindex(rr_post)], 0.025) for i in 1:ni]
    rr_95hi = [quantile([rr_post[k][i] for k in eachindex(rr_post)], 0.975) for i in 1:ni]

    (; chain, rr_mean, rr_95lo, rr_95hi)
end

# ── Posterior predictive check ────────────────────────────────────────────────

"""
    posterior_predictive_check(y_obs, chain, model; nsim=500) -> NamedTuple

Bayesian posterior predictive check.
Returns Bayesian p-values for mean and variance test statistics.
Good fit: bp_mean and bp_var both near 0.5.
"""
function posterior_predictive_check(
    y_obs :: Vector{Int},
    chain,
    model;
    nsim  :: Int = 500
)
    idx     = rand(1:length(chain), nsim; replace=true)
    y_rep   = [begin
        params = chain[i, :, 1]
        β = [params[Symbol("β[$j]")] for j in 1:size(model.args.X, 2)]
        μ_rep = exp.(log.(model.args.E) .+ model.args.X * β)
        rand.(Poisson.(μ_rep))
    end for i in idx]

    bp_mean = mean([mean(yr) > mean(y_obs) for yr in y_rep])
    bp_var  = mean([var(yr)  > var(y_obs)  for yr in y_rep])

    (bp_mean = bp_mean, bp_var = bp_var,
     y_rep_mean = mean([mean(yr) for yr in y_rep]),
     y_obs_mean = mean(y_obs))
end

end  # _TURING_AVAILABLE[] conditional

# ── Closed-form Poisson GLM (for when Turing not available) ──────────────────

"""
    poisson_glm(y, X, E; max_iter=100, tol=1e-8) -> NamedTuple

Frequentist Poisson GLM with log link and offset log(E).
Uses IRLS (Iteratively Reweighted Least Squares).
No spatial random effect — use as baseline to compare with Bayesian spatial model.
"""
function poisson_glm(
    y        :: AbstractVector{<:Integer},
    X        :: AbstractMatrix{<:Real},
    E        :: AbstractVector{<:Real};
    max_iter :: Int     = 100,
    tol      :: Float64 = 1e-8
)
    n, k = size(X)
    yf = Float64.(y)
    Xf = Float64.(X)
    offset = log.(Float64.(E))

    β = zeros(k)
    ll_prev = -Inf

    for iter in 1:max_iter
        η = Xf * β .+ offset
        μ = exp.(η)

        # Working response and weights (IRLS)
        W_diag = μ
        z      = η .- offset .+ (yf .- μ) ./ μ

        # WLS: β = (X'WX)⁻¹ X'Wz
        sqrtW = sqrt.(W_diag)
        Xw    = sqrtW .* Xf
        zw    = sqrtW .* z
        β_new = (Xw'Xw) \ (Xw' * zw)

        Δ = norm(β_new - β)
        β = β_new

        ll = sum(yf .* (Xf * β .+ offset) .- exp.(Xf * β .+ offset) .- logfactorial.(Int.(yf)))

        Δ < tol && break
        ll_prev = ll
    end

    μ_hat = exp.(Xf * β .+ offset)
    e     = yf - μ_hat
    deviance = 2 * sum(yf .* log.(max.(yf, 1e-15) ./ max.(μ_hat, 1e-15)) .- (yf - μ_hat))
    aic = deviance + 2k

    (; coefficients=β, fitted=μ_hat, residuals=e,
       smr = μ_hat ./ Float64.(E),
       deviance, AIC=aic, n, k)
end

function logfactorial(n::Int)
    n <= 1 && return 0.0
    sum(log(i) for i in 2:n)
end
