# src/analysis/regression.jl
# Spatial regression: spatial lag model, spatial error model, GWR.

using LinearAlgebra, Statistics, DataFrames

# ──────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────────────────

"""OLS coefficient vector β = (X'X)⁻¹ X'y."""
_ols(X, y) = (X' * X) \ (X' * y)

"""Log-likelihood of a normal regression with residuals `e` and n observations."""
function _log_likelihood(e::Vector{Float64})
    n   = length(e)
    s2  = sum(e .^ 2) / n
    s2 > 0 || return -Inf
    -n / 2 * (log(2π) + log(s2) + 1.0)
end

"""AIC = -2 * log_likelihood + 2 * k."""
_aic(ll, k) = -2ll + 2k

# ──────────────────────────────────────────────────────────────────────────────
# Spatial Lag Model (SAR)
# ──────────────────────────────────────────────────────────────────────────────

"""
    spatial_lag_model(y, X, W) -> NamedTuple

Estimate a spatial autoregressive (lag) model:

    y = ρ W y + X β + ε

using a grid search over ρ ∈ (-0.99, 0.99) followed by OLS on the filtered
system.  This is a simplified estimator suitable for moderate *n*; for large
datasets a proper maximum-likelihood routine is preferred.

Returns `(coefs, rho, log_likelihood, AIC)`.
"""
function spatial_lag_model(y::Vector{Float64}, X::Matrix{Float64},
                             W::Matrix{Float64})
    n, p = size(X)
    @assert length(y) == n "y length must match X rows"
    @assert size(W)   == (n, n) "W must be n×n"

    best_ll  = -Inf
    best_rho = 0.0
    best_b   = zeros(p)

    # Grid search over ρ
    for ρ in -0.98:0.02:0.98
        y_lag = W * y
        y_star = y .- ρ .* y_lag
        b  = _ols(X, y_star)
        e  = y_star .- X * b
        ll = _log_likelihood(e) + log(abs(det(I - ρ .* W)))
        if ll > best_ll
            best_ll  = ll
            best_rho = ρ
            best_b   = b
        end
    end

    # Residuals at best ρ
    e   = (y .- best_rho .* (W * y)) .- X * best_b
    ll  = _log_likelihood(e)
    aic = _aic(ll, p + 1)   # p slope params + ρ

    return (coefs = best_b, rho = best_rho, log_likelihood = ll, AIC = aic)
end

# ──────────────────────────────────────────────────────────────────────────────
# Spatial Error Model (SEM)
# ──────────────────────────────────────────────────────────────────────────────

"""
    spatial_error_model(y, X, W) -> NamedTuple

Estimate a spatial error model:

    y = X β + u,   u = λ W u + ε

using a grid search over λ ∈ (-0.99, 0.99).

Returns `(coefs, lambda, log_likelihood, AIC)`.
"""
function spatial_error_model(y::Vector{Float64}, X::Matrix{Float64},
                               W::Matrix{Float64})
    n, p = size(X)
    @assert length(y) == n "y length must match X rows"
    @assert size(W)   == (n, n) "W must be n×n"

    best_ll     = -Inf
    best_lambda = 0.0
    best_b      = zeros(p)

    A = I - 0.0 .* W   # will be updated in loop

    for λ in -0.98:0.02:0.98
        A    = I(n) - λ .* W
        yAy  = A * y
        XAX  = A * X
        b    = _ols(XAX, yAy)
        e    = yAy .- XAX * b
        ll   = _log_likelihood(e) + log(abs(det(A)))
        if ll > best_ll
            best_ll     = ll
            best_lambda = λ
            best_b      = b
        end
    end

    A_best = I(n) - best_lambda .* W
    e      = A_best * (y .- X * best_b)
    ll     = _log_likelihood(e)
    aic    = _aic(ll, p + 1)

    return (coefs = best_b, lambda = best_lambda,
            log_likelihood = ll, AIC = aic)
end

# ──────────────────────────────────────────────────────────────────────────────
# Geographically Weighted Regression (GWR)
# ──────────────────────────────────────────────────────────────────────────────

"""
    gwr(y, X, coords; bandwidth_km=50.0, kernel=:bisquare) -> DataFrame

Geographically Weighted Regression.

- `y`            — n-length response vector
- `X`            — n×p design matrix (include a column of ones for intercept)
- `coords`       — n×2 matrix of `[lat, lon]` for each observation
- `bandwidth_km` — spatial bandwidth for the kernel weighting (km)
- `kernel`       — `:bisquare` or `:gaussian`

Returns a `DataFrame` with columns `beta_1, ..., beta_p` (local coefficients)
and `local_r2` (local coefficient of determination) for each observation.
"""
function gwr(y::Vector{Float64}, X::Matrix{Float64},
              coords::Matrix{Float64};
              bandwidth_km::Float64 = 50.0,
              kernel::Symbol        = :bisquare)::DataFrame
    n, p = size(X)

    kernel_fn = if kernel == :bisquare
        (d, bw) -> d < bw ? (1.0 - (d / bw)^2)^2 : 0.0
    elseif kernel == :gaussian
        (d, bw) -> exp(-0.5 * (d / bw)^2)
    else
        error("Unknown kernel: $(kernel). Use :bisquare or :gaussian.")
    end

    coefs    = Matrix{Float64}(undef, n, p)
    local_r2 = Vector{Float64}(undef, n)

    for i in 1:n
        ci = (coords[i, 1], coords[i, 2])
        w  = [kernel_fn(haversine(ci, (coords[k, 1], coords[k, 2])), bandwidth_km)
              for k in 1:n]

        W_diag = Diagonal(w)
        XtW    = X' * W_diag
        AtA    = XtW * X
        b      = size(AtA, 1) == rank(AtA) ?
                     AtA \ (XtW * y) :
                     pinv(AtA) * XtW * y
        coefs[i, :] = b

        # Local R²
        y_hat   = X * b
        y_w_bar = sum(w .* y) / sum(w)
        ss_tot  = sum(w .* (y .- y_w_bar) .^ 2)
        ss_res  = sum(w .* (y .- y_hat)   .^ 2)
        local_r2[i] = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0
    end

    col_names = [Symbol("beta_$(i)") for i in 1:p]
    df = DataFrame(coefs, col_names)
    df.local_r2 = local_r2
    return df
end
