# priors.jl — Domain-informed prior distributions for healthcare data
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia

"""
    HealthPrior

Container for a named prior distribution used in healthcare Bayesian models.
Encapsulates domain knowledge (expected range, scale, units).
"""
struct HealthPrior
    name        :: String
    dist        :: Distribution
    domain_note :: String   # brief justification for this choice
end

Base.show(io::IO, p::HealthPrior) =
    print(io, "HealthPrior($(p.name): $(p.dist))")

# ── Healthcare-specific prior constructors ────────────────────────────────────

"""
    rate_prior(; mean_rate, max_rate) -> HealthPrior

Beta prior for a rate or proportion (mortality, readmission, coverage rate).
Parameterised from desired prior mean and effective sample size.
"""
function rate_prior(; mean_rate::Float64=0.1, effective_n::Float64=10.0, name::String="rate")
    α = mean_rate * effective_n
    β = (1.0 - mean_rate) * effective_n
    HealthPrior(name, Beta(α, β),
        "Beta($(round(α;digits=2)), $(round(β;digits=2))): mean=$(mean_rate), ESS=$(effective_n)")
end

"""
    cost_prior(; median_cost, cv) -> HealthPrior

LogNormal prior for healthcare costs (always positive, right-skewed).
Parameterised from prior median and coefficient of variation.
"""
function cost_prior(; median_cost::Float64=5000.0, cv::Float64=1.5, name::String="cost")
    μ_ln = log(median_cost)
    σ_ln = sqrt(log(1 + cv^2))
    HealthPrior(name, LogNormal(μ_ln, σ_ln),
        "LogNormal(μ=$(round(μ_ln;digits=2)), σ=$(round(σ_ln;digits=2))): median=\$$(median_cost)")
end

"""
    proportion_prior(k; concentration) -> HealthPrior

Symmetric Dirichlet prior for k-category proportions.
concentration < 1: sparse; = 1: uniform; > 1: concentrated.
"""
function proportion_prior(k::Int; concentration::Float64=1.0, name::String="proportion")
    HealthPrior(name, Dirichlet(fill(concentration, k)),
        "Dirichlet($(concentration) × $(k)): $(concentration<1 ? "sparse" : concentration>1 ? "concentrated" : "uniform")")
end

"""
    access_score_prior(; mean_access, sd_access) -> HealthPrior

Normal prior for E2SFCA-style access scores (can be negative in log-space,
but typically centred near 0.003–0.01 for rural ND counties).
Uses truncated Normal to enforce positivity.
"""
function access_score_prior(; mean_access::Float64=0.005, sd_access::Float64=0.003,
                              name::String="access_score")
    HealthPrior(name, truncated(Normal(mean_access, sd_access); lower=0.0),
        "TruncatedNormal(μ=$(mean_access), σ=$(sd_access), lower=0): healthcare access score")
end

"""
    regression_coef_prior(; scale) -> HealthPrior

Weakly-informative Normal prior for regression coefficients (standardised inputs).
Gelman et al. (2008): N(0, 2.5) for standardised predictors.
"""
function regression_coef_prior(; scale::Float64=2.5, name::String="coef")
    HealthPrior(name, Normal(0.0, scale),
        "N(0, $(scale)): weakly-informative for standardised predictor")
end

"""
    noise_prior(; scale) -> HealthPrior

Half-Normal prior for noise/scale parameters (Gelman 2006).
"""
function noise_prior(; scale::Float64=1.0, name::String="noise")
    HealthPrior(name, truncated(Normal(0.0, scale); lower=0.0),
        "HalfNormal($(scale)): noise standard deviation")
end

# ── Prior predictive check ────────────────────────────────────────────────────

"""
    prior_predictive_check(priors, model_fn, n_draws; rng) -> DataFrame

Draw parameters from priors and generate data via `model_fn`.
Useful for assessing whether priors encode plausible data-generating processes.

model_fn(params_dict) -> Vector of simulated outcomes.
"""
function prior_predictive_check(
    priors   :: Dict{String, HealthPrior},
    model_fn :: Function,
    n_draws  :: Int;
    rng      = Random.GLOBAL_RNG,
)
    results = DataFrame[]

    for d in 1:n_draws
        params = Dict(k => rand(rng, p.dist) for (k, p) in priors)
        outcomes = model_fn(params)
        push!(results, DataFrame(
            draw     = fill(d, length(outcomes)),
            outcome  = outcomes,
        ))
    end

    vcat(results...)
end

# ── Log probability helpers ───────────────────────────────────────────────────

"""
    log_prior(θ, priors_list) -> Float64

Sum of log-prior probabilities: log p(θ) = Σ log p(θ_i).
"""
function log_prior(θ::AbstractVector, priors_list::Vector{<:Distribution})
    lp = 0.0
    for (i, prior) in enumerate(priors_list)
        lp += logpdf(prior, θ[i])
    end
    lp
end

"""
    log_likelihood_normal(y, μ, σ²) -> Float64

Log-likelihood for Gaussian observations: Σ log N(y_i | μ_i, σ²).
"""
function log_likelihood_normal(y::AbstractVector, μ::AbstractVector, σ²::Float64)
    n = length(y)
    -0.5n * log(2π * σ²) - 0.5 / σ² * sum((y .- μ).^2)
end

"""
    log_likelihood_bernoulli(y, p) -> Float64

Log-likelihood for Bernoulli observations.
"""
function log_likelihood_bernoulli(y::AbstractVector, p::AbstractVector)
    ε = 1e-9
    sum(yi * log(pi + ε) + (1 - yi) * log(1 - pi + ε)
        for (yi, pi) in zip(y, p))
end
