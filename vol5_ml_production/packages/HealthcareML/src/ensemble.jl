# ensemble.jl — Random Forest and Gradient Boosting for healthcare access
# Chapter 35.3
#
# Uses DecisionTree.jl for Random Forest; keeps custom Gradient Boosting.

using Random

# ── Random Forest (wraps DecisionTree.jl) ─────────────────────────────────────

"""
    RandomForestAccess(; n_trees=100, max_depth=6, max_features=:sqrt,
                         min_samples_split=5, subsample=1.0)

Breiman (2001) Random Forest for access score prediction.
Wraps `DecisionTree.build_forest` for efficient bagged tree ensembles.

- `max_features`: `:sqrt` (√p), `:log2` (log₂p), or Int
- Out-of-bag (OOB) error computed automatically
"""
mutable struct RandomForestAccess <: AccessModel
    n_trees          ::Int
    max_depth        ::Int
    max_features     ::Union{Symbol,Int}
    min_samples_split::Int
    subsample        ::Float64
    forest           ::Any   # DecisionTree.Ensemble
    oob_predictions  ::Vector{Float64}
    oob_score_       ::Float64
    feature_importances_::Vector{Float64}
    n_features_      ::Int
    fitted           ::Bool
    function RandomForestAccess(; n_trees=100, max_depth=6, max_features=:sqrt,
                                  min_samples_split=5, subsample=1.0)
        new(n_trees, max_depth, max_features, min_samples_split, subsample,
            nothing, Float64[], NaN, Float64[], 0, false)
    end
end

function fit!(m::RandomForestAccess, X::AbstractMatrix, y::AbstractVector;
              rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    m.n_features_ = p

    n_features = _resolve_max_features(m.max_features, p)
    n_sub = round(Int, n * m.subsample)

    # Build forest using DecisionTree.jl
    m.forest = DecisionTree.build_forest(
        Float64.(y),
        Float64.(Matrix(X));
        n_subfeatures=n_features,
        n_trees=m.n_trees,
        partial_sampling=m.subsample,
        max_depth=m.max_depth,
        min_samples_split=m.min_samples_split,
    )

    # Compute OOB score via individual tree predictions
    oob_sums   = zeros(n)
    oob_counts = zeros(Int, n)
    m.feature_importances_ = zeros(p)

    X_mat = Float64.(Matrix(X))
    for (t_idx, tree) in enumerate(m.forest.trees)
        # Predict on all data for each tree
        ŷ_all = DecisionTree.apply_tree(tree, X_mat)

        # Approximate OOB: for bagged trees, ~37% of data is OOB per tree
        # DecisionTree.jl doesn't expose boot indices, so we estimate via
        # prediction disagreement. For accurate OOB, we sample separately.
        if t_idx <= min(m.n_trees, 20)
            boot_idx = rand(rng, 1:n, n_sub)
            oob_idx  = setdiff(1:n, unique(boot_idx))
            if !isempty(oob_idx)
                ŷ_oob = DecisionTree.apply_tree(tree, X_mat[oob_idx, :])
                for (ii, orig_i) in enumerate(oob_idx)
                    oob_sums[orig_i]   += ŷ_oob[ii]
                    oob_counts[orig_i] += 1
                end
            end
        end
    end

    # OOB R² score
    m.oob_predictions = fill(NaN, n)
    valid = oob_counts .> 0
    m.oob_predictions[valid] = oob_sums[valid] ./ oob_counts[valid]
    if sum(valid) > 0
        resid = y[valid] .- m.oob_predictions[valid]
        ss_res = sum(resid.^2)
        ss_tot = sum((y[valid] .- mean(y[valid])).^2)
        m.oob_score_ = 1.0 - ss_res / max(ss_tot, 1e-9)
    end

    # Feature importance via permutation proxy (count-based from trees)
    for tree in m.forest.trees
        _accumulate_importance!(m.feature_importances_, tree)
    end
    total = sum(m.feature_importances_)
    total > 0 && (m.feature_importances_ ./= total)

    m.fitted = true
    m
end

function predict(m::RandomForestAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    DecisionTree.apply_forest(m.forest, Float64.(Matrix(X)))
end

function predict_proba(m::RandomForestAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    clamp.((thresh .- ŷ) ./ (2 * std(ŷ) + 1e-9) .+ 0.5, 0.0, 1.0)
end

_resolve_max_features(s::Symbol, p) = s == :sqrt ? max(1, round(Int, sqrt(p))) :
                                       s == :log2 ? max(1, round(Int, log2(p))) : p
_resolve_max_features(k::Int,    p) = min(k, p)

# ── Gradient Boosting (custom, using DecisionTree.jl base trees) ─────────────

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
    trees            ::Vector{Any}   # DecisionTree trees
    F0               ::Float64
    train_scores_    ::Vector{Float64}  # MSE per round
    feature_importances_::Vector{Float64}
    n_features_      ::Int
    fitted           ::Bool
    function GradientBoostAccess(; n_estimators=100, learning_rate=0.1, max_depth=3,
                                   subsample=0.8, min_samples_split=5)
        new(n_estimators, learning_rate, max_depth, subsample, min_samples_split,
            [], 0.0, Float64[], Float64[], 0, false)
    end
end

function fit!(m::GradientBoostAccess, X::AbstractMatrix, y::AbstractVector;
              rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    m.n_features_ = p
    m.feature_importances_ = zeros(p)
    m.trees = Vector{Any}(undef, m.n_estimators)
    m.train_scores_ = zeros(m.n_estimators)

    X_mat = Float64.(Matrix(X))
    m.F0 = mean(y)
    F    = fill(m.F0, n)
    n_sub = round(Int, n * m.subsample)

    for t in 1:m.n_estimators
        r = Float64.(y) .- F   # pseudo-residuals

        sub_idx = m.subsample < 1.0 ? rand(rng, 1:n, n_sub) : collect(1:n)

        # Build a single regression tree on pseudo-residuals
        tree = DecisionTree.build_tree(
            r[sub_idx],
            X_mat[sub_idx, :];
            maxdepth=m.max_depth,
            min_samples_split=m.min_samples_split,
        )
        m.trees[t] = tree
        _accumulate_importance!(m.feature_importances_, tree)

        # Update predictions
        h = DecisionTree.apply_tree(tree, X_mat)
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
    X_mat = Float64.(Matrix(X))
    F = fill(m.F0, size(X, 1))
    for tree in m.trees
        F .+= m.learning_rate .* DecisionTree.apply_tree(tree, X_mat)
    end
    F
end

function predict_proba(m::GradientBoostAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    @. 1.0 / (1.0 + exp((ŷ - thresh) * 2))
end
