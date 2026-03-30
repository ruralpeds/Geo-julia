# split_conformal.jl — Split conformal prediction for ConformalHealth
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia
#
# Split Conformal Prediction (Papadopoulos et al. 2002; Lei et al. 2018):
# 1. Split data into training set I₁ and calibration set I₂
# 2. Train model on I₁
# 3. Compute nonconformity scores s_i = |y_i - ŷ_i| on I₂
# 4. q̂ = ⌈(|I₂|+1)(1-α)⌉/|I₂|-quantile of {s_i}
# 5. Prediction interval: [ŷ(x) - q̂, ŷ(x) + q̂]
#
# Finite-sample guarantee: P(y_{n+1} ∈ C(x)) ≥ 1 - α

# ── Nonconformity scores ──────────────────────────────────────────────────────

"""
    abs_residual_score(ŷ, y) -> Vector{Float64}

Standard regression nonconformity score: |y - ŷ|.
"""
abs_residual_score(ŷ::AbstractVector, y::AbstractVector) = abs.(y .- ŷ)

"""
    normalized_residual_score(ŷ, y, σ̂) -> Vector{Float64}

Normalized nonconformity score: |y - ŷ| / σ̂(x).
Produces locally adaptive intervals (wider in high-uncertainty regions).
"""
function normalized_residual_score(ŷ::AbstractVector, y::AbstractVector,
                                    σ̂::AbstractVector)
    abs.(y .- ŷ) ./ max.(σ̂, 1e-8)
end

# ── ConformalRegressor ────────────────────────────────────────────────────────

"""
    ConformalRegressor

Split conformal prediction wrapper around any regression model.
"""
struct ConformalRegressor
    predict_fn  :: Function    # predict_fn(X) -> ŷ
    q̂           :: Float64     # calibration quantile
    α           :: Float64     # miscoverage level
    n_calib     :: Int
    score_type  :: Symbol      # :absolute or :normalized
    σ̂_fn        :: Union{Function, Nothing}  # for normalized scores
end

"""
    conformal_fit(predict_fn, X_calib, y_calib; α, score_type, σ̂_fn) -> ConformalRegressor

Calibrate a conformal regressor on held-out calibration data.
"""
function conformal_fit(
    predict_fn  :: Function,
    X_calib     :: AbstractMatrix,
    y_calib     :: AbstractVector;
    α           :: Float64  = 0.1,
    score_type  :: Symbol   = :absolute,
    σ̂_fn        :: Union{Function, Nothing} = nothing,
)
    n = length(y_calib)
    ŷ_calib = predict_fn(X_calib)

    scores = if score_type == :normalized && !isnothing(σ̂_fn)
        σ̂_calib = σ̂_fn(X_calib)
        normalized_residual_score(ŷ_calib, y_calib, σ̂_calib)
    else
        abs_residual_score(ŷ_calib, y_calib)
    end

    # Conformal quantile: ⌈(n+1)(1-α)⌉/n quantile
    level = ceil((n + 1) * (1 - α)) / n
    level = min(level, 1.0)
    q̂ = quantile(scores, level)

    ConformalRegressor(predict_fn, q̂, α, n, score_type, σ̂_fn)
end

# ── ConformalResult ───────────────────────────────────────────────────────────

"""
    ConformalResult

Prediction intervals from a calibrated conformal regressor.
"""
struct ConformalResult
    point_pred  :: Vector{Float64}
    lower       :: Vector{Float64}
    upper       :: Vector{Float64}
    width       :: Vector{Float64}
    α           :: Float64
    q̂           :: Float64
    n_calib     :: Int
end

"""
    conformal_predict(cr, X_new) -> ConformalResult

Produce prediction intervals for new data.
C(x) = [ŷ(x) - q̂, ŷ(x) + q̂]  (absolute scores)
C(x) = [ŷ(x) - q̂·σ̂(x), ŷ(x) + q̂·σ̂(x)]  (normalized scores)
"""
function conformal_predict(cr::ConformalRegressor, X_new::AbstractMatrix)
    ŷ = cr.predict_fn(X_new)

    if cr.score_type == :normalized && !isnothing(cr.σ̂_fn)
        σ̂ = cr.σ̂_fn(X_new)
        margin = cr.q̂ .* max.(σ̂, 1e-8)
    else
        margin = fill(cr.q̂, length(ŷ))
    end

    ConformalResult(
        ŷ, ŷ .- margin, ŷ .+ margin, 2 .* margin,
        cr.α, cr.q̂, cr.n_calib
    )
end

"""
    conformal_coverage(result, y_test) -> NamedTuple

Empirical coverage: fraction of test observations within the prediction interval.
Should be ≥ 1-α by the conformal guarantee.
"""
function conformal_coverage(r::ConformalResult, y_test::AbstractVector)
    covered = (y_test .>= r.lower) .& (y_test .<= r.upper)
    (coverage   = mean(covered),
     target     = 1 - r.α,
     mean_width = mean(r.width),
     efficient  = mean(covered) <= 1 - r.α + 0.1)
end

function Base.show(io::IO, r::ConformalResult)
    n = length(r.point_pred)
    println(io, "ConformalResult (n=$(n), α=$(r.α))")
    println(io, "  Calibration q̂: $(round(r.q̂; digits=4))")
    println(io, "  Mean width:    $(round(mean(r.width); digits=4))")
    println(io, "  Coverage ≥ $(1-r.α) guaranteed by construction")
end
