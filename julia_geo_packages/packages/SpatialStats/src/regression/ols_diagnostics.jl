# regression/ols_diagnostics.jl — OLS with spatial diagnostics (LM tests)

using LinearAlgebra
using Statistics

"""
    SpatialRegResult

Unified result struct for OLS, SLM, SEM, and SDM.

# Fields
- `model_type`      : `:OLS`, `:SLM`, `:SEM`, `:SDM`
- `coefficients`    : named vector of β estimates
- `coef_names`      : coefficient names
- `rho_or_lambda`   : ρ (SLM/SDM) or λ (SEM); 0.0 for OLS
- `log_likelihood`  : maximised log-likelihood
- `AIC`             : Akaike Information Criterion
- `BIC`             : Bayesian Information Criterion
- `lm_lag`          : LM-lag test statistic (only for OLS)
- `lm_lag_p`        : p-value for LM-lag
- `lm_error`        : LM-error test statistic (only for OLS)
- `lm_error_p`      : p-value for LM-error
- `residuals`       : residual vector
- `fitted`          : fitted values
- `n`               : number of observations
- `k`               : number of predictors (incl. intercept)
- `r_squared`       : R² (OLS / pseudo-R² for spatial models)
"""
struct SpatialRegResult
    model_type    :: Symbol
    coefficients  :: Vector{Float64}
    coef_names    :: Vector{String}
    rho_or_lambda :: Float64
    log_likelihood :: Float64
    AIC           :: Float64
    BIC           :: Float64
    lm_lag        :: Float64
    lm_lag_p      :: Float64
    lm_error      :: Float64
    lm_error_p    :: Float64
    residuals     :: Vector{Float64}
    fitted        :: Vector{Float64}
    n             :: Int
    k             :: Int
    r_squared     :: Float64
end

function Base.show(io::IO, r::SpatialRegResult)
    println(io, "$(r.model_type) Regression (n=$(r.n), k=$(r.k))")
    println(io, "  R²     = $(round(r.r_squared; digits=4))")
    println(io, "  AIC    = $(round(r.AIC; digits=2))")
    println(io, "  Log-L  = $(round(r.log_likelihood; digits=2))")
    if r.model_type == :OLS
        println(io, "  LM-lag   = $(round(r.lm_lag; digits=3)) (p=$(round(r.lm_lag_p; digits=3)))")
        println(io, "  LM-error = $(round(r.lm_error; digits=3)) (p=$(round(r.lm_error_p; digits=3)))")
    else
        ρλ_name = r.model_type == :SEM ? "λ" : "ρ"
        println(io, "  $(ρλ_name) = $(round(r.rho_or_lambda; digits=4))")
    end
    println(io, "  Coefficients:")
    for (nm, c) in zip(r.coef_names, r.coefficients)
        println(io, "    $(rpad(nm, 20)) $(round(c; digits=4))")
    end
end

# ────────────────────────────────────────────────────────────────────────────

"""
    lm_spatial(y, X, w; coef_names) -> SpatialRegResult

OLS regression with spatial diagnostics: LM-lag and LM-error tests
(Anselin 1988, Burridge 1980).

# Arguments
- `y`          : response vector (n,)
- `X`          : design matrix (n × k); include intercept column if desired
- `w`          : `SpatialWeights`
- `coef_names` : optional coefficient names (default: "x1", "x2", …)
"""
function lm_spatial(y::AbstractVector{<:Real},
                     X::AbstractMatrix{<:Real},
                     w::AbstractSpatialWeights;
                     coef_names::Union{Nothing, Vector{String}} = nothing)::SpatialRegResult

    n, k = size(X)
    yf = Float64.(y)
    Xf = Float64.(X)
    W  = w.W

    # OLS
    β  = Xf \ yf
    ŷ  = Xf * β
    e  = yf - ŷ
    σ² = dot(e, e) / n
    names = coef_names === nothing ? ["x$(i)" for i in 1:k] : coef_names

    # Log-likelihood
    ll = -n/2 * log(2π * σ²) - n/2

    # R²
    ss_res = dot(e, e)
    ss_tot = dot(yf .- mean(yf), yf .- mean(yf))
    r2 = 1.0 - ss_res / max(ss_tot, 1e-15)

    aic = -2ll + 2k
    bic = -2ll + k * log(n)

    # LM tests
    lm_lag_stat, lm_lag_p, lm_err_stat, lm_err_p = lm_tests(yf, Xf, w)

    SpatialRegResult(:OLS, β, names, 0.0, ll, aic, bic,
                     lm_lag_stat, lm_lag_p, lm_err_stat, lm_err_p,
                     e, ŷ, n, k, r2)
end

# ────────────────────────────────────────────────────────────────────────────

"""
    lm_tests(y, X, w) -> (LM_lag, p_lag, LM_error, p_error)

Compute Lagrange Multiplier tests for spatial dependence (Anselin 1988).
Both test statistics follow χ²(1) under H₀.

Returns:
- `LM_lag`   : LM statistic for omitted spatial lag (ρ=0)
- `p_lag`    : p-value from χ²(1)
- `LM_error` : LM statistic for spatial error (λ=0)
- `p_error`  : p-value from χ²(1)
"""
function lm_tests(y::AbstractVector{<:Real},
                   X::AbstractMatrix{<:Real},
                   w::AbstractSpatialWeights)

    n = length(y)
    yf = Float64.(y)
    Xf = Float64.(X)
    W  = w.W

    β  = Xf \ yf
    e  = yf - Xf * β
    σ² = dot(e, e) / n

    We   = W * e
    Wy   = W * yf
    eWe  = dot(e, We)

    # J matrix: tr(W'W + W²) = tr((W + W')W) using sparse operations
    J = (sum(W .^ 2) + sum((W * W); dims=2) |> sum) # scalar approximation
    # More precisely: tr(W'W + W²)
    WtW = W' * W
    W2  = W * W
    T = tr(WtW) + tr(W2)

    # Fitted lag of X
    Xf_aug = hcat(Xf, Wy)
    β_aug  = Xf_aug \ yf
    e_aug  = yf - Xf_aug * β_aug
    eWe_aug = dot(e_aug, W * e_aug)

    # LM-error (Burridge 1980): LM_λ = (e'We/σ²)² / T
    LM_err = (eWe / σ²)^2 / max(T, 1e-15)

    # LM-lag (Anselin 1988): requires R = T + (Wy)' M (Wy) / σ²
    # where M = I - X(X'X)⁻¹X'
    P     = Xf * (Xf' * Xf \ Xf')  # projection matrix (dense, small k)
    M_Wy  = Wy - P * Wy
    R     = T + dot(M_Wy, M_Wy) / max(σ², 1e-15)
    LM_lag = (dot(e, W * yf) / σ²)^2 / max(R, 1e-15)

    p_err = _chi2_p(LM_err, 1)
    p_lag = _chi2_p(LM_lag, 1)

    (LM_lag, p_lag, LM_err, p_err)
end

# χ²(df) p-value via Wilson-Hilferty normal approximation
function _chi2_p(x::Float64, df::Int)::Float64
    x < 0 && return 1.0
    μ = Float64(df)
    σ = sqrt(2μ)
    # W-H: z ≈ ((x/μ)^(1/3) - (1 - 2/(9μ))) / sqrt(2/(9μ))
    z = ((x/μ)^(1/3) - (1 - 2/(9μ))) / sqrt(2/(9μ))
    1.0 - _norm_cdf(z)
end

function _norm_cdf(z::Float64)::Float64
    t = 1.0 / (1.0 + 0.2316419 * abs(z))
    d = 0.3989423 * exp(-0.5 * z^2)
    p = 1.0 - d * t * @evalpoly(t, 1.330274429, -1.821255978, 1.781477937, -0.356563782, 0.319381530)
    z >= 0 ? p : 1.0 - p
end
