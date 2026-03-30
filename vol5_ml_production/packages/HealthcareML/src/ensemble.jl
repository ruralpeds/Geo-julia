# ensemble.jl — Random Forest and Gradient Boosting for healthcare access
# Chapter 35.3

using Random

# ── Random Forest ─────────────────────────────────────────────────────────────

"""
    RandomForestAccess(; n_trees=100, max_depth=6, max_features=:sqrt,
                         min_samples_split=5, subsample=1.0)

Breiman (2001) Random Forest for access score prediction.

- Bootstrap resampling of training rows
- `max_features`: `:sqrt` (√p), `:log2` (log₂p), or Int
- Out-of-bag (OOB) error computed automatically
"""
mutable struct RandomForestAccess <: AccessModel
    n_trees          ::Int
    max_depth        ::Int
    max_features     ::Union{Symbol,Int}
    min_samples_split::Int
    subsample        ::Float64
    trees            ::Vector{DecisionTreeAccess}
    oob_predictions  ::Vector{Float64}
    oob_score_       ::Float64
    feature_importances_::Vector{Float64}
    n_features_      ::Int
    fitted           ::Bool
    function RandomForestAccess(; n_trees=100, max_depth=6, max_features=:sqrt,
                                  min_samples_split=5, subsample=1.0)
        new(n_trees, max_depth, max_features, min_samples_split, subsample,
            DecisionTreeAccess[], Float64[], NaN, Float64[], 0, false)
    end
end

function fit!(m::RandomForestAccess, X::AbstractMatrix, y::AbstractVector;
              rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    m.n_features_        = p
    m.oob_predictions    = fill(NaN, n)
    oob_sums             = zeros(n)
    oob_counts           = zeros(Int, n)
    m.feature_importances_ = zeros(p)
    m.trees = Vector{DecisionTreeAccess}(undef, m.n_trees)

    n_features = _resolve_max_features(m.max_features, p)
    n_subsample = round(Int, n * m.subsample)

    for t in 1:m.n_trees
        # Bootstrap sample
        boot_idx = rand(rng, 1:n, n_subsample)
        oob_idx  = setdiff(1:n, unique(boot_idx))

        # Random feature subspace
        feat_idx = sort(randperm(rng, p)[1:n_features])
        X_sub    = X[boot_idx, feat_idx]
        y_sub    = y[boot_idx]

        tree = DecisionTreeAccess(; max_depth=m.max_depth,
                                    min_samples_split=m.min_samples_split)
        fit!(tree, X_sub, y_sub)
        # Store full-feature importance proxy (zero for unselected features)
        full_imp = zeros(p)
        full_imp[feat_idx] .= tree.feature_importances_
        m.feature_importances_ .+= full_imp

        # OOB prediction (using full feature set)
        # Re-fit on all features for OOB scoring
        tree_full = DecisionTreeAccess(; max_depth=m.max_depth,
                                         min_samples_split=m.min_samples_split)
        fit!(tree_full, X[boot_idx, :], y_sub)
        m.trees[t] = tree_full

        if !isempty(oob_idx)
            ŷ_oob = predict(tree_full, X[oob_idx, :])
            for (ii, orig_i) in enumerate(oob_idx)
                oob_sums[orig_i]   += ŷ_oob[ii]
                oob_counts[orig_i] += 1
            end
        end
    end

    # OOB score
    valid = oob_counts .> 0
    m.oob_predictions[valid] = oob_sums[valid] ./ oob_counts[valid]
    if sum(valid) > 0
        resid = y[valid] .- m.oob_predictions[valid]
        ss_res = sum(resid.^2)
        ss_tot = sum((y[valid] .- mean(y[valid])).^2)
        m.oob_score_ = 1.0 - ss_res / max(ss_tot, 1e-9)
    end

    # Normalise importances
    total = sum(m.feature_importances_)
    total > 0 && (m.feature_importances_ ./= total)
    m.fitted = true
    m
end

function predict(m::RandomForestAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    preds = [predict(tree, X) for tree in m.trees]
    mean(preds)
end

function predict_proba(m::RandomForestAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    clamp.((thresh .- ŷ) ./ (2 * std(ŷ) + 1e-9) .+ 0.5, 0.0, 1.0)
end

_resolve_max_features(s::Symbol, p) = s == :sqrt ? max(1, round(Int, sqrt(p))) :
                                       s == :log2 ? max(1, round(Int, log2(p))) : p
_resolve_max_features(k::Int,    p) = min(k, p)

# ── Gradient Boosting ─────────────────────────────────────────────────────────

"""
    GradientBoostAccess(; n_estimators=100, learning_rate=0.1, max_depth=3,
                          subsample=0.8, min_samples_split=5)

Friedman (2001) gradient boosting for healthcare access prediction.

Algorithm (squared-error loss):
1. F₀(x) = ȳ
2. For m = 1..M:
   a. rᵢ = yᵢ - Fₘ₋₁(xᵢ)          [pseudo-residuals]
   b. Fit tree hₘ on residuals
   c. Fₘ(x) = Fₘ₋₁(x) + η·hₘ(x)
"""
mutable struct GradientBoostAccess <: AccessModel
    n_estimators     ::Int
    learning_rate    ::Float64
    max_depth        ::Int
    subsample        ::Float64
    min_samples_split::Int
    trees            ::Vector{DecisionTreeAccess}
    F0               ::Float64
    train_scores_    ::Vector{Float64}  # MSE per round
    feature_importances_::Vector{Float64}
    n_features_      ::Int
    fitted           ::Bool
    function GradientBoostAccess(; n_estimators=100, learning_rate=0.1, max_depth=3,
                                   subsample=0.8, min_samples_split=5)
        new(n_estimators, learning_rate, max_depth, subsample, min_samples_split,
            DecisionTreeAccess[], 0.0, Float64[], Float64[], 0, false)
    end
end

function fit!(m::GradientBoostAccess, X::AbstractMatrix, y::AbstractVector;
              rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    m.n_features_ = p
    m.feature_importances_ = zeros(p)
    m.trees = Vector{DecisionTreeAccess}(undef, m.n_estimators)
    m.train_scores_ = zeros(m.n_estimators)

    m.F0 = mean(y)
    F    = fill(m.F0, n)
    n_sub = round(Int, n * m.subsample)

    for t in 1:m.n_estimators
        r = Float64.(y) .- F   # pseudo-residuals

        sub_idx = m.subsample < 1.0 ? rand(rng, 1:n, n_sub) : 1:n
        tree = DecisionTreeAccess(; max_depth=m.max_depth,
                                    min_samples_split=m.min_samples_split)
        fit!(tree, X[sub_idx, :], r[sub_idx])
        m.trees[t] = tree
        m.feature_importances_ .+= tree.feature_importances_

        # Update predictions
        h = predict(tree, X)
        F .+= m.learning_rate .* h
        m.train_scores_[t] = mean((Float64.(y) .- F).^2)
    end

    total = sum(m.feature_importances_)
    total > 0 && (m.feature_importances_ ./= total)
    m.fitted = true
    m
end

function predict(m::GradientBoostAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    F = fill(m.F0, size(X, 1))
    for tree in m.trees
        F .+= m.learning_rate .* predict(tree, X)
    end
    F
end

function predict_proba(m::GradientBoostAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    @. 1.0 / (1.0 + exp((ŷ - thresh) * 2))
end
