# jackknife.jl — Jackknife+ and CV+ conformal prediction
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia
#
# Jackknife+ (Barber, Candès, Tibshirani & Vovk 2021):
# Uses leave-one-out residuals without data splitting.
# Intervals: [-q̂_{1-α}({ŷ_{-i}(x) - |y_i - ŷ_{-i}(x_i)|}), ...]
#
# Finite-sample guarantee: P(y ∈ C_{n,α}(x)) ≥ 1 - 2α  (for ÿ_{-i})
# Improved with CV+: K-fold cross-validation variant

"""
    JackknifeResult

Result from Jackknife+ conformal prediction.
"""
struct JackknifeResult
    lower      :: Vector{Float64}
    upper      :: Vector{Float64}
    width      :: Vector{Float64}
    α          :: Float64
    method     :: Symbol   # :jackknife_plus or :cv_plus
    n_train    :: Int
end

"""
    jackknife_plus(fit_fn, X_train, y_train, X_test; α, max_n_loo) -> JackknifeResult

Jackknife+ conformal prediction.
fit_fn(X_train, y_train) -> predict_fn(X) -> ŷ.

For large datasets, approximate with max_n_loo LOO models.
"""
function jackknife_plus(
    fit_fn    :: Function,    # fit_fn(X, y) -> predict_fn
    X_train   :: AbstractMatrix,
    y_train   :: AbstractVector,
    X_test    :: AbstractMatrix;
    α         :: Float64 = 0.1,
    max_n_loo :: Int     = 50,    # cap LOO to avoid O(n²) fitting
)
    n = length(y_train)
    n_test = size(X_test, 1)
    n_loo = min(n, max_n_loo)

    # Sample LOO indices
    loo_idx = n <= max_n_loo ? (1:n) : sort(randperm(n)[1:n_loo])

    # For each LOO model, get residual at left-out point and predictions at X_test
    # LOO_residuals[i] = |y_i - ŷ_{-i}(x_i)|
    # LOO_preds[i, :] = ŷ_{-i}(X_test)

    loo_residuals = Float64[]
    loo_preds     = zeros(n_loo, n_test)

    for (k, i) in enumerate(loo_idx)
        train_mask = trues(n); train_mask[i] = false
        X_loo = X_train[train_mask, :]
        y_loo = y_train[train_mask]

        try
            pred_fn = fit_fn(X_loo, y_loo)
            ŷ_i   = pred_fn(X_train[i:i, :])
            ŷ_test = pred_fn(X_test)
            push!(loo_residuals, abs(y_train[i] - ŷ_i[1]))
            loo_preds[k, :] = ŷ_test
        catch
            push!(loo_residuals, 0.0)
        end
    end

    # Jackknife+ intervals at level α:
    # For each test point x: collect {ŷ_{-i}(x) - |y_i - ŷ_{-i}(x_i)|} and
    #                                 {ŷ_{-i}(x) + |y_i - ŷ_{-i}(x_i)|}
    # Lower = ⌊α(1+1/n)⌋ quantile of {ŷ_{-i}(x) - R_i}
    # Upper = ⌈(1-α)(1+1/n)⌉ quantile of {ŷ_{-i}(x) + R_i}

    q_lo = floor(α * (1 + 1/n_loo))
    q_hi = ceil((1 - α) * (1 + 1/n_loo))

    lower = zeros(n_test)
    upper = zeros(n_test)

    for j in 1:n_test
        scores_lo = loo_preds[:, j] .- loo_residuals
        scores_hi = loo_preds[:, j] .+ loo_residuals
        lower[j] = quantile(scores_lo, clamp(q_lo, 0.0, 1.0))
        upper[j] = quantile(scores_hi, clamp(q_hi, 0.0, 1.0))
    end

    # Fallback: ensure lower <= upper
    for j in 1:n_test
        if lower[j] > upper[j]
            mid = (lower[j] + upper[j]) / 2
            lower[j] = mid - 1e-8
            upper[j] = mid + 1e-8
        end
    end

    JackknifeResult(lower, upper, upper .- lower, α, :jackknife_plus, n)
end

"""
    cv_plus(fit_fn, X_train, y_train, X_test; α, K) -> JackknifeResult

CV+ conformal: K-fold version of jackknife+ (more stable for large n).
"""
function cv_plus(
    fit_fn  :: Function,
    X_train :: AbstractMatrix,
    y_train :: AbstractVector,
    X_test  :: AbstractMatrix;
    α       :: Float64 = 0.1,
    K       :: Int     = 5,
    rng             = Random.GLOBAL_RNG,
)
    n = length(y_train)
    n_test = size(X_test, 1)
    fold_id = mod.(randperm(rng, n) .- 1, K) .+ 1

    cv_residuals = zeros(n)
    cv_preds     = zeros(n, n_test)

    for k in 1:K
        val_mask  = fold_id .== k
        train_mask = .!val_mask

        try
            pred_fn = fit_fn(X_train[train_mask, :], y_train[train_mask])
            ŷ_val  = pred_fn(X_train[val_mask, :])
            ŷ_test = pred_fn(X_test)
            cv_residuals[val_mask] = abs.(y_train[val_mask] .- ŷ_val)
            cv_preds[val_mask, :] = repeat(ŷ_test', sum(val_mask))
        catch
        end
    end

    q_lo = α / 2; q_hi = 1 - α / 2
    lower = zeros(n_test)
    upper = zeros(n_test)

    for j in 1:n_test
        scores_lo = cv_preds[:, j] .- cv_residuals
        scores_hi = cv_preds[:, j] .+ cv_residuals
        lower[j] = quantile(scores_lo, q_lo)
        upper[j] = quantile(scores_hi, q_hi)
    end

    JackknifeResult(lower, upper, upper .- lower, α, :cv_plus, n)
end
