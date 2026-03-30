# src/regression/ols_diagnostics.jl
# OLS with spatial dependence diagnostics (LM tests).

using LinearAlgebra, Statistics, Distributions

"""
    SpatialRegResult

Container for spatial regression results.

Fields:
- `model_type`       — `:OLS`, `:SLM`, `:SEM`, or `:SDM`
- `coefficients`     — NamedTuple of named coefficient estimates
- `rho_or_lambda`    — spatial autoregressive parameter (ρ for SLM, λ for SEM)
- `log_likelihood`   — maximised log-likelihood
- `AIC`              — Akaike Information Criterion
- `BIC`              — Bayesian Information Criterion
- `lm_tests`         — NamedTuple with LM-lag, LM-error diagnostic statistics
- `residuals`        — model residuals
- `fitted`           — fitted values
"""
struct SpatialRegResult
    model_type::Symbol
    coefficients::NamedTuple
    rho_or_lambda::Float64
    log_likelihood::Float64
    AIC::Float64
    BIC::Float64
    lm_tests::NamedTuple
    residuals::Vector{Float64}
    fitted::Vector{Float64}
end

function Base.show(io::IO, r::SpatialRegResult)
    println(io, "SpatialRegResult(:$(r.model_type))")
    println(io, "  ρ/λ = $(round(r.rho_or_lambda; digits=4))")
    println(io, "  logL = $(round(r.log_likelihood; digits=3))")
    println(io, "  AIC  = $(round(r.AIC; digits=3))")
    println(io, "  BIC  = $(round(r.BIC; digits=3))")
    coef_names = keys(r.coefficients)
    coef_vals  = values(r.coefficients)
    for (n, v) in zip(coef_names, coef_vals)
        println(io, "  $(n) = $(round(v; digits=5))")
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# OLS helper
# ──────────────────────────────────────────────────────────────────────────────

function _ols_fit(y::Vector{Float64}, X::Matrix{Float64})
    β   = (X' * X) \ (X' * y)
    ŷ   = X * β
    e   = y .- ŷ
    n   = length(y)
    k   = size(X, 2)
    σ2  = sum(e .^ 2) / n
    ll  = -n/2 * (log(2π * σ2) + 1.0)
    (beta = β, fitted = ŷ, residuals = e, sigma2 = σ2, log_lik = ll, n = n, k = k)
end

function _aic(ll, k)  = -2ll + 2k
function _bic(ll, k, n) = -2ll + log(n) * k

# ──────────────────────────────────────────────────────────────────────────────
# Lagrange Multiplier spatial dependence tests (Anselin 1988)
# ──────────────────────────────────────────────────────────────────────────────

"""
    lm_tests(y, X, w::SpatialWeights) -> NamedTuple

Compute Lagrange Multiplier tests for spatial dependence on OLS residuals.
Returns `(LM_lag, p_lag, LM_err, p_err)` with χ²(1) p-values.

Use these to decide between SLM (if LM_lag significant) vs SEM (if LM_err significant).
"""
function lm_tests(y::Vector{Float64}, X::Matrix{Float64},
                   w::SpatialWeights)
    ols = _ols_fit(y, X)
    n   = ols.n
    e   = ols.residuals
    W   = Matrix{Float64}(w.W)
    We  = W * e
    σ2  = ols.sigma2

    WtW = W' * W
    T   = tr(WtW + W * W')   # trace(W'W + WW') = 2*tr(W'W) for symmetric W

    # LM-lag
    WX    = W * X
    M     = I(n) - X * ((X'X) \ X')   # annihilator
    J     = T / σ2 + (WX * ((X'X) \ X') * W * X) |> tr
    J     = T / σ2  # simplified J₁₁ per Anselin (1988) eq 102
    LM_lag = (dot(e, We) / σ2)^2 / J

    # LM-error
    LM_err = (dot(e, We))^2 / (σ2^2 * T)

    χ2     = Chisq(1)
    p_lag  = 1 - cdf(χ2, max(LM_lag, 0.0))
    p_err  = 1 - cdf(χ2, max(LM_err, 0.0))

    return (LM_lag = LM_lag, p_lag = p_lag, LM_err = LM_err, p_err = p_err)
end

# ──────────────────────────────────────────────────────────────────────────────
# OLS with spatial diagnostics
# ──────────────────────────────────────────────────────────────────────────────

"""
    lm_spatial(y, X, w::SpatialWeights; coef_names=nothing) -> SpatialRegResult

Estimate OLS regression with spatial-dependence diagnostics.
Use this as the starting point before deciding between SLM and SEM.

`coef_names` is an optional `Vector{Symbol}` labelling each column of `X`.
"""
function lm_spatial(y::Vector{Float64}, X::Matrix{Float64},
                     w::SpatialWeights;
                     coef_names::Union{Nothing, Vector{Symbol}} = nothing)::SpatialRegResult
    ols   = _ols_fit(y, X)
    lm    = lm_tests(y, X, w)
    n, k  = ols.n, ols.k

    names = isnothing(coef_names) ?
                Tuple(Symbol("β$(i)") for i in 1:k) :
                Tuple(coef_names)
    coefs = NamedTuple{names}(Tuple(ols.beta))

    SpatialRegResult(
        :OLS, coefs, 0.0, ols.log_lik,
        _aic(ols.log_lik, k), _bic(ols.log_lik, k, n),
        lm, ols.residuals, ols.fitted,
    )
end
