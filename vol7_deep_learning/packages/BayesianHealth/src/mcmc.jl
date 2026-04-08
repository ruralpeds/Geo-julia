# mcmc.jl — MCMC samplers for BayesianHealth
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia
#
# Implements:
# 1. Metropolis-Hastings (random-walk proposal)
# 2. Hamiltonian Monte Carlo (HMC) with leapfrog integrator
# 3. Chains data structure with R-hat and ESS diagnostics

# ── Chains data structure ─────────────────────────────────────────────────────

"""
    Chains

Stores MCMC samples from one or more chains.
Shape: n_iter × n_params × n_chains
"""
struct Chains
    samples      :: Array{Float64, 3}   # iter × params × chains
    log_probs    :: Matrix{Float64}     # iter × chains
    n_warmup     :: Int
    param_names  :: Vector{String}
    accept_rate  :: Vector{Float64}     # per chain
end

function n_iter(c::Chains)    size(c.samples, 1) end
function n_params(c::Chains)  size(c.samples, 2) end
function n_chains(c::Chains)  size(c.samples, 3) end
function post_warmup(c::Chains)
    c.samples[c.n_warmup+1:end, :, :]
end

# ── R-hat convergence diagnostic ─────────────────────────────────────────────

"""
    r_hat(chains) -> Vector{Float64}

Gelman-Rubin R-hat per parameter (Gelman & Rubin 1992).
R-hat ≈ 1 indicates convergence; < 1.1 generally acceptable.

R̂ = √(((N-1)/N · W + B/N) / W)
where B = between-chain variance, W = within-chain variance.
"""
function r_hat(c::Chains)
    draws = post_warmup(c)   # iter × params × chains
    n, p, m = size(draws)

    r̂ = zeros(p)
    for j in 1:p
        chain_means = vec(mean(draws[:, j, :]; dims=1))   # m
        grand_mean  = mean(chain_means)

        B = n / (m - 1) * sum((chain_means .- grand_mean).^2)
        W = mean(var(draws[:, j, :]; dims=1))

        var_hat = (n-1)/n * W + B/n
        r̂[j] = sqrt(var_hat / max(W, 1e-12))
    end
    r̂
end

"""
    ess(chains) -> Vector{Float64}

Effective sample size per parameter via autocorrelation.
ESS = N / (1 + 2·Σ_k ρ_k)   (Geyer 1992)
"""
function ess(c::Chains)
    draws = post_warmup(c)
    n, p, m = size(draws)
    all_draws = reshape(draws, n*m, p)   # pool chains

    ess_vec = zeros(p)
    for j in 1:p
        s = all_draws[:, j]
        n_s = length(s)
        μ  = mean(s)
        c0 = var(s)
        if c0 < 1e-12
            ess_vec[j] = n_s
            continue
        end
        # Sum autocorrelations until negative pair
        rho_sum = 0.0
        for lag in 1:div(n_s, 2)
            rho = sum((s[1:end-lag] .- μ) .* (s[lag+1:end] .- μ)) / (n_s * c0)
            abs(rho) < 0.05 && break
            rho_sum += rho
        end
        ess_vec[j] = n_s / max(1 + 2*rho_sum, 1.0)
    end
    ess_vec
end

"""
    chain_summary(c::Chains) -> DataFrame

Summary statistics for each parameter: mean, std, quantiles, R-hat, ESS.
"""
function chain_summary(c::Chains)
    draws = post_warmup(c)
    n, p, m = size(draws)
    all_draws = reshape(draws, n*m, p)

    rh  = r_hat(c)
    es  = ess(c)

    DataFrame(
        parameter = c.param_names,
        mean      = vec(mean(all_draws; dims=1)),
        std       = vec(std(all_draws; dims=1)),
        q5        = [quantile(all_draws[:, j], 0.05) for j in 1:p],
        q50       = [quantile(all_draws[:, j], 0.50) for j in 1:p],
        q95       = [quantile(all_draws[:, j], 0.95) for j in 1:p],
        r_hat     = rh,
        ess       = es,
        converged = rh .< 1.1,
    )
end

# ── Metropolis-Hastings sampler ───────────────────────────────────────────────

"""
    MetropolisHastings

Random-walk Metropolis-Hastings sampler.
Proposal: θ* ~ N(θ, σ²_prop · I)
Acceptance: α = min(1, p(θ*)q(θ|θ*) / p(θ)q(θ*|θ))
For symmetric Gaussian proposal: α = min(1, exp(log_p(θ*) - log_p(θ)))
"""
struct MetropolisHastings
    step_size    :: Float64
    adapt_steps  :: Int
    target_rate  :: Float64
end

MetropolisHastings(; step_size=0.1, adapt_steps=100, target_rate=0.234) =
    MetropolisHastings(step_size, adapt_steps, target_rate)

function _mh_chain(
    sampler  :: MetropolisHastings,
    log_p    :: Function,
    θ0       :: AbstractVector,
    n_iter   :: Int,
    n_warmup :: Int;
    rng      = Random.GLOBAL_RNG,
)
    dim = length(θ0)
    θ = copy(θ0)
    lp = log_p(θ)
    step = sampler.step_size

    samples  = zeros(n_iter, dim)
    lp_trace = zeros(n_iter)
    n_accept = 0

    for t in 1:n_iter
        # Propose
        θ_prop = θ .+ step .* randn(rng, dim)
        lp_prop = log_p(θ_prop)

        # Accept/reject
        if log(rand(rng)) < lp_prop - lp
            θ = θ_prop
            lp = lp_prop
            n_accept += 1
        end

        samples[t, :] = θ
        lp_trace[t]   = lp

        # Dual-averaging step size adaptation during warmup
        if t <= sampler.adapt_steps
            rate = n_accept / t
            step *= exp(0.05 * (rate - sampler.target_rate))
            step  = clamp(step, 1e-6, 10.0)
        end
    end

    samples, lp_trace, n_accept / n_iter
end

# ── HMC sampler ───────────────────────────────────────────────────────────────

"""
    HMCSampler

Hamiltonian Monte Carlo with leapfrog integration (Neal 2011).
Algorithm:
  1. Sample momentum p ~ N(0, M)   (M = mass matrix, default = I)
  2. Leapfrog L steps of size ε
  3. Accept/reject via Metropolis criterion on H = U + K
     where U = -log p(θ), K = ½ p'M⁻¹p
"""
struct HMCSampler
    step_size    :: Float64   # ε
    n_leapfrog   :: Int       # L
    adapt_steps  :: Int
    target_rate  :: Float64
end

HMCSampler(; step_size=0.05, n_leapfrog=10, adapt_steps=100, target_rate=0.65) =
    HMCSampler(step_size, n_leapfrog, adapt_steps, target_rate)

"""
    _grad_U(log_p, θ; h) -> Vector{Float64}

Gradient of potential energy U(θ) = -log p(θ) via central differences.
"""
function _grad_U(log_p::Function, θ::AbstractVector; h::Float64=1e-5)
    dim  = length(θ)
    grad = zeros(dim)
    for i in 1:dim
        θp = copy(θ); θp[i] += h
        θm = copy(θ); θm[i] -= h
        grad[i] = -(log_p(θp) - log_p(θm)) / (2h)
    end
    grad
end

"""
    _leapfrog(log_p, θ, p, ε, L) -> (θ_new, p_new)

L leapfrog steps with step size ε.
"""
function _leapfrog(log_p::Function, θ::AbstractVector, p::AbstractVector,
                   ε::Float64, L::Int)
    θ_new = copy(θ); p_new = copy(p)
    # Half step for momentum
    p_new .-= 0.5 .* ε .* _grad_U(log_p, θ_new)
    for _ in 1:L
        θ_new .+= ε .* p_new
        if _ < L
            p_new .-= ε .* _grad_U(log_p, θ_new)
        end
    end
    # Final half step
    p_new .-= 0.5 .* ε .* _grad_U(log_p, θ_new)
    θ_new, p_new
end

function _hmc_chain(
    sampler  :: HMCSampler,
    log_p    :: Function,
    θ0       :: AbstractVector,
    n_iter   :: Int,
    n_warmup :: Int;
    rng      = Random.GLOBAL_RNG,
)
    dim = length(θ0)
    θ = copy(θ0)
    ε = sampler.step_size

    samples  = zeros(n_iter, dim)
    lp_trace = zeros(n_iter)
    n_accept = 0

    for t in 1:n_iter
        # Sample momentum
        p = randn(rng, dim)

        # Current Hamiltonian: H = U + K
        U_curr = -log_p(θ)
        K_curr = 0.5 * dot(p, p)

        # Leapfrog
        θ_prop, p_prop = _leapfrog(log_p, θ, p, ε, sampler.n_leapfrog)

        U_prop = -log_p(θ_prop)
        K_prop = 0.5 * dot(p_prop, p_prop)

        # Metropolis accept/reject
        ΔH = (U_prop + K_prop) - (U_curr + K_curr)
        if log(rand(rng)) < -ΔH
            θ = θ_prop
            n_accept += 1
        end

        samples[t, :] = θ
        lp_trace[t]   = log_p(θ)

        # Adapt step size during warmup
        if t <= sampler.adapt_steps
            rate = n_accept / t
            ε *= exp(0.1 * (rate - sampler.target_rate))
            ε  = clamp(ε, 1e-6, 1.0)
        end
    end

    samples, lp_trace, n_accept / n_iter
end

# ── sample_chains: run multiple chains ───────────────────────────────────────

"""
    sample_chains(sampler, log_p, θ0; n_iter, n_warmup, n_chains, rng) -> Chains

Run `n_chains` parallel MCMC chains.  Each chain is initialised by adding
small noise to `θ0`.  Returns a `Chains` object with convergence diagnostics.
"""
function sample_chains(
    sampler  :: Union{MetropolisHastings, HMCSampler},
    log_p    :: Function,
    θ0       :: AbstractVector;
    n_iter   :: Int    = 1000,
    n_warmup :: Int    = 200,
    n_chains :: Int    = 4,
    param_names :: Vector{String} = String[],
    rng             = Random.GLOBAL_RNG,
)
    dim = length(θ0)
    if isempty(param_names)
        param_names = ["θ$(i)" for i in 1:dim]
    end

    all_samples  = zeros(n_iter, dim, n_chains)
    all_lp       = zeros(n_iter, n_chains)
    accept_rates = zeros(n_chains)

    for c in 1:n_chains
        # Perturb starting point for each chain
        θ_init = θ0 .+ 0.1 .* randn(rng, dim)

        chain_fn = sampler isa MetropolisHastings ?
            _mh_chain : _hmc_chain

        s, lp, ar = chain_fn(sampler, log_p, θ_init, n_iter, n_warmup; rng=rng)
        all_samples[:, :, c] = s
        all_lp[:, c]         = lp
        accept_rates[c]      = ar
    end

    Chains(all_samples, all_lp, n_warmup, param_names, accept_rates)
end
