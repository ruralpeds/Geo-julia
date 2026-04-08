# cqr.jl — Conformalized Quantile Regression
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia
#
# Romano, Patterson & Candès (2019) — Conformalized Quantile Regression.
# CQR produces locally adaptive intervals by:
# 1. Fit quantile regressors q̂_lo(x) and q̂_hi(x) at levels α/2 and 1-α/2
# 2. Compute calibration scores: s_i = max(q̂_lo(x_i) - y_i, y_i - q̂_hi(x_i))
# 3. q̂_conf = ⌈(n+1)(1-α)⌉/n quantile of {s_i}
# 4. Interval: [q̂_lo(x) - q̂_conf, q̂_hi(x) + q̂_conf]
#
# Unlike standard conformal, CQR produces intervals that are wider
# in high-variance regions and narrower in low-variance regions.

# ── Linear quantile regression ────────────────────────────────────────────────

"""
    linear_quantile_reg(X, y; τ, max_iter, tol) -> Vector{Float64}

Fit linear quantile regression at quantile level τ via iteratively reweighted
least squares (IRLS) / smoothed pinball loss minimisation.
"""
function linear_quantile_reg(
    X       :: AbstractMatrix,
    y       :: AbstractVector;
    τ       :: Float64  = 0.1,
    max_iter :: Int     = 200,
    lr      :: Float64  = 0.01,
    tol     :: Float64  = 1e-6,
    λ       :: Float64  = 1e-4,  # ridge penalty
)
    n, p = size(X)
    X_aug = hcat(ones(n), X)
    k = p + 1
    β = zeros(k)

    # Gradient descent on smooth pinball loss
    # L_τ(u) ≈ τu·I(u>0) + (τ-1)u·I(u<0)
    # Smooth approximation: huber-like
    ε = 1e-4  # smoothing

    for iter in 1:max_iter
        r = y .- X_aug * β
        # Smooth gradient of pinball loss
        w = map(ri -> ri > ε ? τ : ri < -ε ? τ - 1 : (τ - 0.5 + ri/(2ε)) , r)
        grad = -X_aug' * w ./ n .+ λ .* β
        β_new = β .- lr .* grad
        if norm(β_new .- β) < tol
            β = β_new; break
        end
        β = β_new
    end
    β
end

# ── CQR Model ─────────────────────────────────────────────────────────────────

"""
    CQRModel

Conformalized Quantile Regression model.
"""
struct CQRModel
    β_lo    :: Vector{Float64}   # lower quantile coefficients
    β_hi    :: Vector{Float64}   # upper quantile coefficients
    q̂       :: Float64           # conformal adjustment
    α       :: Float64
    n_calib :: Int
    τ_lo    :: Float64
    τ_hi    :: Float64
end

"""
    cqr_fit(X_train, y_train, X_calib, y_calib; α) -> CQRModel

Fit and calibrate a CQR model.
"""
function cqr_fit(
    X_train :: AbstractMatrix,
    y_train :: AbstractVector,
    X_calib :: AbstractMatrix,
    y_calib :: AbstractVector;
    α       :: Float64 = 0.1,
    lr      :: Float64 = 0.005,
    max_iter :: Int    = 300,
)
    τ_lo = α / 2
    τ_hi = 1 - α / 2

    # Fit lower and upper quantile regressors on training set
    β_lo = linear_quantile_reg(X_train, y_train; τ=τ_lo, lr=lr, max_iter=max_iter)
    β_hi = linear_quantile_reg(X_train, y_train; τ=τ_hi, lr=lr, max_iter=max_iter)

    n_calib = length(y_calib)
    X_calib_aug = hcat(ones(n_calib), X_calib)

    q̂_lo_calib = X_calib_aug * β_lo
    q̂_hi_calib = X_calib_aug * β_hi

    # CQR nonconformity scores: s_i = max(q̂_lo(x_i) - y_i, y_i - q̂_hi(x_i))
    scores = max.(q̂_lo_calib .- y_calib, y_calib .- q̂_hi_calib)

    # Conformal quantile
    level = ceil((n_calib + 1) * (1 - α)) / n_calib
    q̂ = quantile(scores, clamp(level, 0.0, 1.0))

    CQRModel(β_lo, β_hi, q̂, α, n_calib, τ_lo, τ_hi)
end

"""
    cqr_predict(model, X_new) -> DataFrame

Produce CQR prediction intervals.
C(x) = [q̂_lo(x) - q̂, q̂_hi(x) + q̂]
"""
function cqr_predict(model::CQRModel, X_new::AbstractMatrix)
    n = size(X_new, 1)
    X_aug = hcat(ones(n), X_new)

    q̂_lo = X_aug * model.β_lo
    q̂_hi = X_aug * model.β_hi

    lower = q̂_lo .- model.q̂
    upper = q̂_hi .+ model.q̂

    # Ensure lower ≤ upper (may break for misspecified models)
    lower = min.(lower, upper)

    DataFrame(
        lower = lower,
        upper = upper,
        width = upper .- lower,
        q_lo  = q̂_lo,
        q_hi  = q̂_hi,
    )
end
