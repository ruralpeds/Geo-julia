# trees.jl — Decision tree and ridge regression models
# Chapter 35.2
#
# Pure-Julia implementations (no MLJ.jl dependency) for portability.
# These mirror the scikit-learn API: fit!, predict, predict_proba.

# ── Abstract interface ─────────────────────────────────────────────────────────

abstract type AccessModel end

"""
    fit!(model, X, y) -> model

Train the model on feature matrix X (n × p) and target vector y (n,).
Returns the mutated model.
"""
function fit! end

"""
    predict(model, X) -> Vector{Float64}

Predict continuous access scores for feature matrix X.
"""
function predict end

"""
    predict_proba(model, X) -> Vector{Float64}

Predict probability of "low access" (access_score < median training value).
"""
function predict_proba end

# ── Ridge Regression ──────────────────────────────────────────────────────────

"""
    RidgeAccess(; λ=1.0)

L2-regularised linear regression for access prediction.

Closed-form: β = (X'X + λI)⁻¹ X'y
"""
mutable struct RidgeAccess <: AccessModel
    λ       ::Float64
    β       ::Vector{Float64}
    intercept::Float64
    fitted  ::Bool
    function RidgeAccess(; λ=1.0)
        new(λ, Float64[], 0.0, false)
    end
end

function fit!(m::RidgeAccess, X::AbstractMatrix, y::AbstractVector)
    n, p = size(X)
    # Add intercept column
    X1  = hcat(ones(n), X)
    # Ridge: (X'X + λ·diag([0, I]))⁻¹ X'y  (don't regularise intercept)
    reg = diagm(vcat(0.0, fill(m.λ, p)))
    β   = (X1'X1 + reg) \ (X1'y)
    m.intercept = β[1]
    m.β         = β[2:end]
    m.fitted    = true
    m
end

function predict(m::RidgeAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    m.intercept .+ X * m.β
end

function predict_proba(m::RidgeAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    # Logistic transform centred at median training prediction
    thresh = median(ŷ)
    @. 1.0 / (1.0 + exp(ŷ - thresh))
end

# ── Decision Tree ─────────────────────────────────────────────────────────────

"""
    DecisionTreeNode

Internal node for a CART regression tree.
Stores split feature index, threshold, left/right children or leaf value.
"""
mutable struct DecisionTreeNode
    feature   ::Int
    threshold ::Float64
    left      ::Union{DecisionTreeNode, Nothing}
    right     ::Union{DecisionTreeNode, Nothing}
    value     ::Float64   # only used for leaf nodes
    is_leaf   ::Bool
end

"""
    DecisionTreeAccess(; max_depth=5, min_samples_split=5, min_impurity_decrease=1e-7)

CART regression tree for healthcare access prediction.

Splitting criterion: variance reduction (equivalent to MSE minimisation).
"""
mutable struct DecisionTreeAccess <: AccessModel
    max_depth           ::Int
    min_samples_split   ::Int
    min_impurity_decrease::Float64
    root                ::Union{DecisionTreeNode, Nothing}
    feature_importances_ ::Vector{Float64}
    n_features_         ::Int
    fitted              ::Bool
    function DecisionTreeAccess(; max_depth=5, min_samples_split=5, min_impurity_decrease=1e-7)
        new(max_depth, min_samples_split, min_impurity_decrease, nothing, Float64[], 0, false)
    end
end

function fit!(m::DecisionTreeAccess, X::AbstractMatrix, y::AbstractVector)
    n, p = size(X)
    m.n_features_         = p
    m.feature_importances_ = zeros(p)
    indices = collect(1:n)
    m.root = _build_tree(m, X, Float64.(y), indices, 0)
    # Normalise importances
    total = sum(m.feature_importances_)
    total > 0 && (m.feature_importances_ ./= total)
    m.fitted = true
    m
end

function _build_tree(m::DecisionTreeAccess, X, y, indices, depth)
    n = length(indices)
    leaf_val = mean(y[indices])

    if depth >= m.max_depth || n < m.min_samples_split
        return DecisionTreeNode(0, 0.0, nothing, nothing, leaf_val, true)
    end

    best_feat, best_thresh, best_gain = 0, 0.0, -Inf
    parent_var = var(y[indices])

    for feat in 1:size(X, 2)
        vals = X[indices, feat]
        sorted_vals = sort(unique(vals))
        length(sorted_vals) < 2 && continue

        for t_idx in 1:length(sorted_vals)-1
            thresh = (sorted_vals[t_idx] + sorted_vals[t_idx+1]) / 2
            left_mask  = vals .<= thresh
            right_mask = .!left_mask
            nl, nr = sum(left_mask), sum(right_mask)
            (nl < 2 || nr < 2) && continue

            y_left  = y[indices[left_mask]]
            y_right = y[indices[right_mask]]
            gain = parent_var - (nl/n)*var(y_left) - (nr/n)*var(y_right)

            if gain > best_gain
                best_gain, best_feat, best_thresh = gain, feat, thresh
            end
        end
    end

    if best_gain < m.min_impurity_decrease || best_feat == 0
        return DecisionTreeNode(0, 0.0, nothing, nothing, leaf_val, true)
    end

    # Track feature importance: weighted variance reduction
    m.feature_importances_[best_feat] += best_gain * n

    left_idx  = indices[X[indices, best_feat] .<= best_thresh]
    right_idx = indices[X[indices, best_feat] .>  best_thresh]
    left  = _build_tree(m, X, y, left_idx,  depth+1)
    right = _build_tree(m, X, y, right_idx, depth+1)
    DecisionTreeNode(best_feat, best_thresh, left, right, leaf_val, false)
end

function _predict_one(node::DecisionTreeNode, x::AbstractVector)
    node.is_leaf && return node.value
    if x[node.feature] <= node.threshold
        return _predict_one(node.left,  x)
    else
        return _predict_one(node.right, x)
    end
end

function predict(m::DecisionTreeAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    [_predict_one(m.root, X[i, :]) for i in 1:size(X, 1)]
end

function predict_proba(m::DecisionTreeAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    clamp.((thresh .- ŷ) ./ (2 * std(ŷ) + 1e-9) .+ 0.5, 0.0, 1.0)
end
