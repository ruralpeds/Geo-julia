# gwrf.jl — Geographically Weighted Random Forest
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia
#
# Geographically weighted variant of random forests:
# For each prediction location, fit a local random forest using
# spatially kernel-weighted bootstrap sampling.
#
# Inspired by: Georganos et al. (2019) — GW-RF for spatial prediction

"""
    GWRFModel

Geographically Weighted Random Forest.
Stores the spatial bandwidth and global training data for local re-fitting.
"""
struct GWRFModel
    coords     :: Matrix{Float64}
    bandwidth  :: Float64
    kernel     :: Symbol
    n_trees    :: Int
    max_depth  :: Int
    X_train    :: Matrix{Float64}
    y_train    :: Vector{Float64}
    global_rmse :: Float64
end

# ── Simple CART decision tree (re-used from Vol 5 pattern) ───────────────────

mutable struct _TreeNode
    feature  :: Int
    thresh   :: Float64
    left     :: Union{_TreeNode, Nothing}
    right    :: Union{_TreeNode, Nothing}
    pred     :: Float64
    is_leaf  :: Bool
end

function _build_tree(X, y, depth, max_depth, min_samples)
    n = length(y)
    if depth >= max_depth || n < min_samples || var(y) < 1e-12
        return _TreeNode(0, 0.0, nothing, nothing, mean(y), true)
    end

    best_feat = 0; best_thresh = 0.0; best_gain = -Inf
    base_var = var(y) * n

    for j in 1:size(X, 2)
        vals = sort(unique(X[:, j]))
        length(vals) < 2 && continue
        for t in (vals[1:end-1] .+ vals[2:end]) ./ 2
            left  = y[X[:, j] .<= t]
            right = y[X[:, j] .>  t]
            isempty(left) || isempty(right) && continue
            gain = base_var - var(left)*length(left) - var(right)*length(right)
            if gain > best_gain
                best_gain = gain; best_feat = j; best_thresh = t
            end
        end
    end

    best_feat == 0 && return _TreeNode(0, 0.0, nothing, nothing, mean(y), true)

    mask_l = X[:, best_feat] .<= best_thresh
    mask_r = .!mask_l
    node = _TreeNode(best_feat, best_thresh, nothing, nothing, mean(y), false)
    node.left  = _build_tree(X[mask_l, :], y[mask_l], depth+1, max_depth, min_samples)
    node.right = _build_tree(X[mask_r, :], y[mask_r], depth+1, max_depth, min_samples)
    node
end

function _predict_tree(node::_TreeNode, x::AbstractVector)
    node.is_leaf && return node.pred
    if x[node.feature] <= node.thresh
        return _predict_tree(node.left, x)
    else
        return _predict_tree(node.right, x)
    end
end

function _fit_local_rf(X_loc, y_loc, n_trees, max_depth, min_samples, rng)
    trees = _TreeNode[]
    n, p = size(X_loc)
    m_feats = max(1, round(Int, sqrt(p)))  # feature subspace

    for _ in 1:n_trees
        # Bootstrap sample
        idx = rand(rng, 1:n, n)
        X_b = X_loc[idx, :]; y_b = y_loc[idx]

        # Random feature subset
        feat_idx = sort(randperm(rng, p)[1:m_feats])
        tree = _build_tree(X_b[:, feat_idx], y_b, 0, max_depth, min_samples)

        # Store feature mapping in a wrapper (hack: set feature indices relative to feat_idx)
        push!(trees, tree)
    end
    trees
end

"""
    gwrf_fit(y, X, coords; bandwidth, kernel, n_trees, max_depth) -> GWRFModel

Fit a Geographically Weighted Random Forest.
"""
function gwrf_fit(
    y          :: AbstractVector{<:Real},
    X          :: AbstractMatrix{<:Real},
    coords     :: AbstractMatrix{<:Real};
    bandwidth  :: Float64 = -1.0,
    kernel     :: Symbol  = :gaussian,
    n_trees    :: Int     = 50,
    max_depth  :: Int     = 4,
    min_samples :: Int    = 5,
    metric     :: Symbol  = :euclidean,
    rng                   = Random.GLOBAL_RNG,
)
    n = size(X, 1)
    D = distance_matrix(coords; metric=metric)

    if bandwidth < 0
        # Use median distance as default bandwidth
        dists_upper = [D[i,j] for i in 1:n for j in (i+1):n]
        bandwidth = median(dists_upper) * 0.5
    end

    kern_fn = get(KERNELS, kernel, gaussian_kernel)

    # Global RF for comparison
    global_trees = _fit_local_rf(X, collect(y), min(n_trees, 20), max_depth, min_samples, rng)
    global_pred  = [mean(_predict_tree(t, X[i,:]) for t in global_trees) for i in 1:n]
    global_rmse  = sqrt(mean((collect(y) .- global_pred).^2))

    GWRFModel(Matrix(coords), bandwidth, kernel, n_trees, max_depth,
              Matrix{Float64}(X), collect(Float64, y), global_rmse)
end

"""
    gwrf_predict(model, X_new, coords_new; rng) -> (mean, std)

Predict at new locations using locally fitted random forests.
Returns posterior mean and std (from tree variance).
"""
function gwrf_predict(
    model      :: GWRFModel,
    X_new      :: AbstractMatrix{<:Real},
    coords_new :: AbstractMatrix{<:Real};
    rng                   = Random.GLOBAL_RNG,
    n_trees    :: Int     = 30,
    max_depth  :: Int     = 4,
    min_samples :: Int    = 3,
)
    n_new = size(X_new, 1)
    n_train = size(model.X_train, 1)
    kern_fn = get(KERNELS, model.kernel, gaussian_kernel)

    μ_preds = zeros(n_new)
    σ_preds = zeros(n_new)

    for i in 1:n_new
        # Distances from new point to all training points
        dists = [distance_matrix(vcat(coords_new[i:i,:], model.coords[j:j,:]); metric=:euclidean)[1,2]
                 for j in 1:n_train]
        weights = [kern_fn(d, model.bandwidth) for d in dists]
        sum_w = sum(weights)
        sum_w < 1e-8 && (weights .= 1.0/n_train)  # fallback: uniform

        # Sample with replacement proportional to spatial weights
        n_local = max(10, round(Int, sum(weights .> 0)))
        probs = weights ./ sum(weights)
        idx = [sample_weighted(probs, rng) for _ in 1:n_local]

        X_loc = model.X_train[idx, :]
        y_loc = model.y_train[idx]

        length(unique(y_loc)) < 2 && (μ_preds[i] = mean(y_loc); σ_preds[i] = std(y_loc); continue)

        trees = _fit_local_rf(X_loc, y_loc, n_trees, max_depth, min_samples, rng)
        tree_preds = [_predict_tree(t, X_new[i,:]) for t in trees]
        μ_preds[i] = mean(tree_preds)
        σ_preds[i] = std(tree_preds)
    end

    μ_preds, σ_preds
end

function sample_weighted(probs::AbstractVector, rng)
    u = rand(rng)
    cumsum_p = 0.0
    for (i, p) in enumerate(probs)
        cumsum_p += p
        cumsum_p >= u && return i
    end
    length(probs)
end
