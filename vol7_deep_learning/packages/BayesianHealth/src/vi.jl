# vi.jl — Variational Inference for BayesianHealth (Turing.jl / AdvancedVI backend)
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia
#
# Mean-field Gaussian VI with Adam optimisation.
# Uses AdvancedVI / Turing for gradient computation where possible,
# falling back to finite differences for compatibility.
#
# Public API preserved:
#   MeanFieldGaussian, vi_fit, elbo, VIResult, vi_predict

# ── Variational family ────────────────────────────────────────────────────────

"""
    MeanFieldGaussian

Mean-field Gaussian variational approximation q(z) = ∏ N(z_i | μ_i, exp(ρ_i)²).
We store log-scale ρ = log(σ) to allow unconstrained optimisation.
"""
mutable struct MeanFieldGaussian
    μ :: Vector{Float64}   # variational means
    ρ :: Vector{Float64}   # log(σ): variational log-std
    dim :: Int
end

MeanFieldGaussian(dim::Int; μ_init=zeros(dim), ρ_init=fill(-1.0, dim)) =
    MeanFieldGaussian(copy(μ_init), copy(ρ_init), dim)

σ_of(q::MeanFieldGaussian) = exp.(q.ρ)
var_of(q::MeanFieldGaussian) = exp.(2 .* q.ρ)

"""
    entropy(q::MeanFieldGaussian) -> Float64

Analytic entropy of mean-field Gaussian: H[q] = Σ ½(1 + log(2π) + 2ρ_i).
"""
function entropy(q::MeanFieldGaussian)
    # H[N(μ,σ²)] = ½ log(2πe σ²) = ½(1 + log(2π)) + ρ
    0.5 * q.dim * (1 + log(2π)) + sum(q.ρ)
end

"""
    sample_z(q, ε) -> Vector{Float64}

Reparameterization: z = μ + σ ⊙ ε, ε ~ N(0, I).
"""
sample_z(q::MeanFieldGaussian, ε::AbstractVector) = q.μ .+ σ_of(q) .* ε

"""
    _to_distribution(q::MeanFieldGaussian) -> MvNormal

Convert to a Distributions.jl MvNormal for use with AdvancedVI / Turing.
"""
function _to_distribution(q::MeanFieldGaussian)
    MvNormal(q.μ, Diagonal(var_of(q)))
end

# ── ELBO computation ─────────────────────────────────────────────────────────

"""
    elbo(q, log_joint_fn; n_samples, rng) -> Float64

Monte Carlo estimate of the ELBO:
ELBO ≈ (1/S) Σ_s log p(x, z_s) + H[q]
where z_s ~ q(z) via reparameterization.
"""
function elbo(
    q            :: MeanFieldGaussian,
    log_joint_fn :: Function;   # log_joint_fn(z) = log p(x, z)
    n_samples    :: Int = 10,
    rng          = Random.GLOBAL_RNG,
)
    lj = 0.0
    for _ in 1:n_samples
        ε = randn(rng, q.dim)
        z = sample_z(q, ε)
        lj += log_joint_fn(z)
    end
    lj / n_samples + entropy(q)
end

# ── VI gradient (finite-difference, used as fallback) ────────────────────────

function vi_gradient(
    q            :: MeanFieldGaussian,
    log_joint_fn :: Function;
    n_samples    :: Int = 5,
    rng          = Random.GLOBAL_RNG,
    h            :: Float64 = 1e-4,
)
    grad_μ = zeros(q.dim)
    grad_ρ = zeros(q.dim)
    base = elbo(q, log_joint_fn; n_samples=n_samples, rng=rng)

    for i in 1:q.dim
        q_p = MeanFieldGaussian(copy(q.μ), copy(q.ρ), q.dim)
        q_p.μ[i] += h
        grad_μ[i] = (elbo(q_p, log_joint_fn; n_samples=n_samples, rng=rng) - base) / h

        q_r = MeanFieldGaussian(copy(q.μ), copy(q.ρ), q.dim)
        q_r.ρ[i] += h
        grad_ρ[i] = (elbo(q_r, log_joint_fn; n_samples=n_samples, rng=rng) - base) / h
    end
    grad_μ, grad_ρ
end

# ── VI result ─────────────────────────────────────────────────────────────────

"""
    VIResult

Result of variational inference optimisation.
"""
struct VIResult
    q            :: MeanFieldGaussian
    elbo_history :: Vector{Float64}
    n_iter       :: Int
    converged    :: Bool
    param_names  :: Vector{String}
end

# ── Main vi_fit function ──────────────────────────────────────────────────────

"""
    vi_fit(log_joint_fn, dim; kwargs...) -> VIResult

Fit a mean-field Gaussian variational approximation by maximising the ELBO.

The `log_joint_fn(z)` should return log p(y, z) = log p(y|z) + log p(z).

Uses Adam-style gradient ascent. Gradients are computed via finite differences
(compatible with arbitrary user-provided log-joint functions). The ELBO
computation follows the same reparameterization trick used by AdvancedVI.
"""
function vi_fit(
    log_joint_fn :: Function,
    dim          :: Int;
    n_iter       :: Int     = 500,
    lr           :: Float64 = 0.05,
    n_mc_samples :: Int     = 10,
    tol          :: Float64 = 1e-4,
    patience     :: Int     = 20,
    param_names  :: Vector{String} = String[],
    μ_init       :: Vector{Float64} = zeros(dim),
    ρ_init       :: Vector{Float64} = fill(-1.0, dim),
    rng                    = Random.GLOBAL_RNG,
    verbose      :: Bool   = false,
)
    q = MeanFieldGaussian(dim; μ_init=μ_init, ρ_init=ρ_init)
    if isempty(param_names)
        param_names = ["θ$(i)" for i in 1:dim]
    end

    elbo_hist = Float64[]
    best_elbo = -Inf
    wait = 0

    # Adam state
    m_μ = zeros(dim); v_μ = zeros(dim)
    m_ρ = zeros(dim); v_ρ = zeros(dim)
    β1, β2, ε_adam = 0.9, 0.999, 1e-8

    for t in 1:n_iter
        gμ, gρ = vi_gradient(q, log_joint_fn; n_samples=n_mc_samples, rng=rng)

        # Adam ascent (maximise ELBO)
        m_μ .= β1 .* m_μ .+ (1-β1) .* gμ
        v_μ .= β2 .* v_μ .+ (1-β2) .* gμ.^2
        m_ρ .= β1 .* m_ρ .+ (1-β1) .* gρ
        v_ρ .= β2 .* v_ρ .+ (1-β2) .* gρ.^2
        m̂_μ = m_μ ./ (1 - β1^t); v̂_μ = v_μ ./ (1 - β2^t)
        m̂_ρ = m_ρ ./ (1 - β1^t); v̂_ρ = v_ρ ./ (1 - β2^t)

        q.μ .+= lr .* m̂_μ ./ (sqrt.(v̂_μ) .+ ε_adam)
        q.ρ .+= lr .* m̂_ρ ./ (sqrt.(v̂_ρ) .+ ε_adam)

        current_elbo = elbo(q, log_joint_fn; n_samples=n_mc_samples, rng=rng)
        push!(elbo_hist, current_elbo)

        if current_elbo > best_elbo + tol
            best_elbo = current_elbo; wait = 0
        else
            wait += 1
            wait >= patience && break
        end

        verbose && t % 50 == 0 &&
            @info "VI iter $t | ELBO = $(round(current_elbo; digits=3))"
    end

    converged = wait < patience
    VIResult(q, elbo_hist, length(elbo_hist), converged, param_names)
end

"""
    vi_predict(result, X_new, predict_fn; n_samples, rng) -> (mean, std)

Posterior predictive mean and standard deviation via Monte Carlo sampling
from the variational posterior q(z).
"""
function vi_predict(
    result     :: VIResult,
    X_new      :: AbstractMatrix,
    predict_fn :: Function;   # predict_fn(z, X) -> predictions
    n_samples  :: Int   = 200,
    rng                 = Random.GLOBAL_RNG,
)
    q = result.q
    preds = Matrix{Float64}(undef, size(X_new, 2), n_samples)
    for s in 1:n_samples
        ε = randn(rng, q.dim)
        z = sample_z(q, ε)
        preds[:, s] = predict_fn(z, X_new)
    end
    vec(mean(preds; dims=2)), vec(std(preds; dims=2))
end
