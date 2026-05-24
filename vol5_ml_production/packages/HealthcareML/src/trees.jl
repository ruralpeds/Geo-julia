# trees.jl — Decision tree and ridge regression models
# Chapter 35.2
#
# Wraps DecisionTree.jl for CART regression trees.
# Preserves the same public API: fit!, predict, predict_proba.

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

# ── Decision Tree (wraps DecisionTree.jl) ─────────────────────────────────────

"""
    DecisionTreeAccess(; max_depth=5, min_samples_split=5, min_impurity_decrease=1e-7)

CART regression tree for healthcare access prediction.
Wraps `DecisionTree.DecisionTreeRegressor`.
"""
mutable struct DecisionTreeAccess <: AccessModel
    max_depth           ::Int
    min_samples_split   ::Int
    min_impurity_decrease::Float64
    tree                ::Union{DecisionTree.Root, DecisionTree.Leaf, Nothing}
    feature_importances_ ::Vector{Float64}
    n_features_         ::Int
    fitted              ::Bool
    function DecisionTreeAccess(; max_depth=5, min_samples_split=5, min_impurity_decrease=1e-7)
        new(max_depth, min_samples_split, min_impurity_decrease, nothing, Float64[], 0, false)
    end
end

function fit!(m::DecisionTreeAccess, X::AbstractMatrix, y::AbstractVector)
    n, p = size(X)
    m.n_features_ = p

    # Build regression tree using DecisionTree.jl
    m.tree = DecisionTree.build_tree(
        Float64.(y),
        Float64.(Matrix(X));
        maxdepth=m.max_depth,
        min_samples_split=m.min_samples_split,
    )

    # Compute feature importances via impurity-based scoring
    m.feature_importances_ = _compute_importances(m.tree, p)
    total = sum(m.feature_importances_)
    total > 0 && (m.feature_importances_ ./= total)

    m.fitted = true
    m
end

function _compute_importances(tree, p::Int)
    imp = zeros(p)
    _accumulate_importance!(imp, tree)
    imp
end

function _accumulate_importance!(imp::Vector{Float64}, node::DecisionTree.Node)
    feat = node.featid
    if 1 <= feat <= length(imp)
        imp[feat] += 1.0  # count-based importance proxy
    end
    _accumulate_importance!(imp, node.left)
    _accumulate_importance!(imp, node.right)
end
_accumulate_importance!(::Vector{Float64}, ::DecisionTree.Leaf) = nothing

function predict(m::DecisionTreeAccess, X::AbstractMatrix)
    @assert m.fitted "Call fit! first"
    DecisionTree.apply_tree(m.tree, Float64.(Matrix(X)))
end

function predict_proba(m::DecisionTreeAccess, X::AbstractMatrix)
    ŷ = predict(m, X)
    thresh = median(ŷ)
    clamp.((thresh .- ŷ) ./ (2 * std(ŷ) + 1e-9) .+ 0.5, 0.0, 1.0)
end
